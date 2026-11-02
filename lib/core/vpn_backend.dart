import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'platform.dart';
import 'server.dart';
import 'settings.dart';
import 'system_proxy.dart';
import 'xray_config.dart';

enum VpnState { disconnected, connecting, connected, error }

class VpnStatus {
  const VpnStatus(this.state, [this.message = '']);
  final VpnState state;
  final String message;
}

/// Общий интерфейс: на телефонах — системный VPN, на компьютерах — процесс xray.
abstract class VpnBackend {
  Stream<VpnStatus> get status;

  /// Поддерживается ли режим «весь трафик» через TUN.
  Future<bool> tunAvailable();

  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun, AppSettings? settings});

  Future<void> stop();

  /// Последние строки журнала ядра (только компьютер).
  List<String> get logs => const [];

  /// Журнал ядра (на Android читается из logcat).
  Future<List<String>> fetchLogs() async => logs;

  /// Сколько байт ушло/пришло через сервер с прошлого вызова. null — статистика недоступна.
  Future<({int up, int down})?> trafficDelta() async => null;

  static VpnBackend create() {
    if (Plat.web) return DemoVpnBackend();
    if (Plat.mobile) return MobileVpnBackend();
    return DesktopVpnBackend();
  }
}

/// Android (VpnService) / iOS (NetworkExtension) — через платформенный канал.
class MobileVpnBackend implements VpnBackend {
  static const _ch = MethodChannel('kuduzo/vpn');
  static const _ev = EventChannel('kuduzo/vpn/events');

  final _ctrl = StreamController<VpnStatus>.broadcast();
  StreamSubscription<dynamic>? _sub;

  MobileVpnBackend() {
    _sub = _ev.receiveBroadcastStream().listen((e) {
      final s = e.toString();
      if (s == 'connected') {
        _ctrl.add(const VpnStatus(VpnState.connected));
      } else if (s == 'connecting') {
        _ctrl.add(const VpnStatus(VpnState.connecting));
      } else if (s == 'disconnected') {
        _ctrl.add(const VpnStatus(VpnState.disconnected));
      } else if (s.startsWith('error:')) {
        _ctrl.add(VpnStatus(VpnState.error, s.substring(6)));
      }
    }, onError: (Object e) {
      _ctrl.add(VpnStatus(VpnState.error, e.toString()));
    });
  }

  @override
  Stream<VpnStatus> get status => _ctrl.stream;

  @override
  Future<bool> tunAvailable() async => true;

  @override
  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun, AppSettings? settings}) async {
    final allowed = await _ch.invokeMethod<bool>('prepare') ?? false;
    if (!allowed) {
      _ctrl.add(const VpnStatus(VpnState.error, 'Нужно разрешить подключение VPN'));
      return;
    }
    final st = settings ?? AppSettings();
    final config = XrayConfigBuilder.build(server,
        routing: routing,
        inbound: InboundMode.tunMobile,
        settings: st,
        lite: Plat.ios,
        stats: Plat.android);
    _ctrl.add(const VpnStatus(VpnState.connecting));
    await _ch.invokeMethod('start', {
      'config': jsonEncode(config),
      'name': server.name,
      'splitMode': st.splitMode.name,
      'splitApps': st.splitApps,
    });
  }

  @override
  Future<({int up, int down})?> trafficDelta() async {
    if (!Plat.android) return null;
    try {
      final s = await _ch.invokeMethod<String>('stats') ?? '';
      return parseLibStats(s);
    } catch (_) {
      return null;
    }
  }

  /// Формат libv2ray: «tag,uplink,123;tag,downlink,456;» (счётчики сбрасываются при чтении).
  static ({int up, int down}) parseLibStats(String s) {
    var up = 0, down = 0;
    for (final part in s.split(';')) {
      final f = part.split(',');
      if (f.length != 3 || f[0] != 'proxy') continue;
      final v = int.tryParse(f[2]) ?? 0;
      if (f[1] == 'uplink') up += v;
      if (f[1] == 'downlink') down += v;
    }
    return (up: up, down: down);
  }

  @override
  Future<List<String>> fetchLogs() async {
    if (!Plat.android) return const ['Журнал на iPhone пока недоступен'];
    try {
      final list = await _ch.invokeListMethod<String>('logs') ?? const [];
      return list;
    } catch (e) {
      return ['Не удалось прочитать журнал: $e'];
    }
  }

  /// Android: приложения с ярлыком на рабочем столе.
  static Future<List<({String pkg, String label, Uint8List? icon})>> installedApps() async {
    final raw = await _ch.invokeListMethod<Map<dynamic, dynamic>>('apps') ?? const [];
    return raw
        .map((m) => (
              pkg: m['pkg'] as String,
              label: (m['label'] as String?) ?? (m['pkg'] as String),
              icon: m['icon'] as Uint8List?,
            ))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  @override
  Future<void> stop() async {
    await _ch.invokeMethod('stop');
  }

  @override
  List<String> get logs => const [];

  void dispose() => _sub?.cancel();
}

/// Windows / macOS — запускаем xray как отдельный процесс.
class DesktopVpnBackend implements VpnBackend {
  final _ctrl = StreamController<VpnStatus>.broadcast();
  Process? _proc;
  bool _proxySet = false;
  bool _stopping = false;
  final List<String> _logs = [];

  @override
  List<String> get logs => List.unmodifiable(_logs);

  @override
  Future<List<String>> fetchLogs() async => logs;

  @override
  Future<({int up, int down})?> trafficDelta() async {
    if (_proc == null) return null;
    try {
      final r = await Process.run(xrayPath(), [
        'api',
        'statsquery',
        '--server=127.0.0.1:${XrayConfigBuilder.apiPort}',
        '-pattern',
        'outbound>>>proxy>>>',
        '-reset',
      ]).timeout(const Duration(seconds: 3));
      if (r.exitCode != 0) return null;
      final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
      var up = 0, down = 0;
      for (final e in (j['stat'] as List? ?? const [])) {
        final m = e as Map<String, dynamic>;
        final name = m['name'] as String? ?? '';
        final v = int.tryParse('${m['value'] ?? 0}') ?? 0;
        if (name.endsWith('uplink')) up += v;
        if (name.endsWith('downlink')) down += v;
      }
      return (up: up, down: down);
    } catch (_) {
      return null;
    }
  }

  void _log(String line) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _logs.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $line');
    if (_logs.length > 400) _logs.removeRange(0, _logs.length - 400);
  }

  /// Версия ядра (первая строка `xray version`).
  static Future<String> coreVersion() async {
    try {
      final r = await Process.run(xrayPath(), ['version']);
      final line = r.stdout.toString().split('\n').first.trim();
      return line.isEmpty ? 'неизвестно' : line;
    } catch (_) {
      return 'не найдено';
    }
  }

  @override
  Stream<VpnStatus> get status => _ctrl.stream;

  /// Папка с xray, geoip.dat, geosite.dat (и wintun.dll на Windows).
  static Directory coreDir() {
    final exe = File(Platform.resolvedExecutable);
    if (Platform.isMacOS) {
      // Kuduzo.app/Contents/MacOS/kuduzo -> Kuduzo.app/Contents/Resources/xray
      return Directory('${exe.parent.parent.path}/Resources/xray');
    }
    return Directory('${exe.parent.path}${Platform.pathSeparator}xray');
  }

  static String xrayPath() =>
      '${coreDir().path}${Platform.pathSeparator}${Platform.isWindows ? 'xray.exe' : 'xray'}';

  @override
  Future<bool> tunAvailable() async {
    if (!Platform.isWindows) return false; // macOS: TUN требует root — следующий этап
    try {
      final r = await Process.run('net', ['session'], runInShell: true);
      return r.exitCode == 0; // 0 = запущено от имени администратора
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun, AppSettings? settings}) async {
    await stop();
    _stopping = false;
    _ctrl.add(const VpnStatus(VpnState.connecting));

    final xray = xrayPath();
    if (!File(xray).existsSync()) {
      final p = xray.toLowerCase();
      final fromArchive = p.contains('rartemp') || p.contains(r'\temp\') || p.contains('7zo');
      _ctrl.add(VpnStatus(
          VpnState.error,
          fromArchive
              ? 'Программа запущена прямо из архива. Распакуйте архив целиком (например, на Рабочий стол) и запустите kuduzo.exe из распакованной папки'
              : 'Не найдено ядро Xray: $xray. Рядом с kuduzo.exe должна быть папка xray'));
      return;
    }

    final inbound = tun ? InboundMode.tunDesktop : InboundMode.proxy;
    final config = XrayConfigBuilder.build(server,
        routing: routing,
        inbound: inbound,
        settings: settings,
        windows: Platform.isWindows,
        stats: true,
        statsApi: true);
    final dir = await getApplicationSupportDirectory();
    final cfgFile = File('${dir.path}${Platform.pathSeparator}config.json');
    await cfgFile.writeAsString(jsonEncode(config));

    try {
      _proc = await Process.start(
        xray,
        ['run', '-c', cfgFile.path],
        workingDirectory: coreDir().path,
        environment: {'XRAY_LOCATION_ASSET': coreDir().path},
      );
    } catch (e) {
      _ctrl.add(VpnStatus(VpnState.error, 'Не удалось запустить Xray: $e'));
      return;
    }

    final errLines = <String>[];
    _log('— запуск: ${server.name} (${tun ? 'TUN' : 'системный прокси'})');
    void collect(String line) {
      errLines.add(line);
      if (errLines.length > 20) errLines.removeAt(0);
      _log(line);
    }

    _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(collect);
    _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(collect);

    final started = Completer<bool>();
    unawaited(_proc!.exitCode.then((code) async {
      _proc = null;
      if (_proxySet) {
        await SystemProxy.disable();
        _proxySet = false;
      }
      if (!started.isCompleted) started.complete(false);
      if (_stopping) {
        _ctrl.add(const VpnStatus(VpnState.disconnected));
      } else {
        final last = errLines.where((l) => l.contains('Failed') || l.contains('failed')).toList();
        _ctrl.add(VpnStatus(VpnState.error,
            last.isNotEmpty ? last.last : 'Xray завершился с кодом $code'));
      }
    }));

    // Даём ядру секунду на старт: если за это время не упало — считаем, что работает.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!started.isCompleted) started.complete(_proc != null);
    });
    if (!await started.future) return;

    if (!tun) {
      try {
        await SystemProxy.enable('127.0.0.1', XrayConfigBuilder.httpPort, XrayConfigBuilder.socksPort);
        _proxySet = true;
      } catch (e) {
        _ctrl.add(VpnStatus(VpnState.error, 'Не удалось включить системный прокси: $e'));
        await stop();
        return;
      }
    }
    _ctrl.add(const VpnStatus(VpnState.connected));
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    if (_proxySet) {
      await SystemProxy.disable();
      _proxySet = false;
    }
    final p = _proc;
    if (p != null) {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
      _proc = null;
    } else {
      _ctrl.add(const VpnStatus(VpnState.disconnected));
    }
  }
}

/// Веб-демо внутри чата: настоящий VPN из браузера невозможен, поэтому только показываем состояния.
class DemoVpnBackend implements VpnBackend {
  final _ctrl = StreamController<VpnStatus>.broadcast();
  final List<String> _logs = [];

  @override
  Stream<VpnStatus> get status => _ctrl.stream;

  @override
  List<String> get logs => List.unmodifiable(_logs);

  @override
  Future<bool> tunAvailable() async => false;

  @override
  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun, AppSettings? settings}) async {
    _ctrl.add(const VpnStatus(VpnState.connecting));
    _logs.add('демо: подключение к ${server.name}');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _on = true;
    _ctrl.add(const VpnStatus(VpnState.connected));
  }

  @override
  Future<void> stop() async {
    _logs.add('демо: отключено');
    _on = false;
    _ctrl.add(const VpnStatus(VpnState.disconnected));
  }

  bool _on = false;
  final _rnd = Random();

  @override
  Future<List<String>> fetchLogs() async => logs;

  @override
  Future<({int up, int down})?> trafficDelta() async =>
      _on ? (up: 2000 + _rnd.nextInt(40000), down: 20000 + _rnd.nextInt(900000)) : null;
}
