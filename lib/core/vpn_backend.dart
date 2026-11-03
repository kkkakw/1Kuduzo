import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    bool allowed;
    try {
      allowed = await _ch.invokeMethod<bool>('prepare') ?? false;
    } on PlatformException catch (e) {
      // iPhone: система отказала в создании VPN — почти всегда это подпись без Network Extension.
      final raw = e.message ?? '';
      final low = raw.toLowerCase();
      final signing = low.contains('permission') ||
          low.contains('ipc') ||
          low.contains('nevpnerrordomain 5') ||
          low.contains('configuration') ||
          low.contains('entitlement');
      _ctrl.add(VpnStatus(
          VpnState.error,
          signing
              ? 'iOS не разрешил создать VPN: в подписи приложения нет права Network Extension ($raw)'
              : 'iOS не разрешил создать VPN: $raw'));
      return;
    }
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
        stats: st.statsEnabled || st.showMemory);
    _ctrl.add(const VpnStatus(VpnState.connecting));
    _prevUp = _prevDown = null;
    _statsError = null;
    final ctl = Plat.ios ? await _newCtl() : null;
    await _ch.invokeMethod('start', {
      'config': jsonEncode(config),
      'name': server.name,
      if (ctl != null) 'ctlPort': ctl.port,
      if (ctl != null) 'ctlToken': ctl.token,
      'splitMode': st.splitMode.name,
      'splitApps': st.splitApps,
      ...tunnelOptions(st),
      'tunnelJson': jsonEncode(tunnelOptions(st)),
    });
  }

  /// Параметры системного туннеля (маршруты, DNS, On Demand, память).
  static Map<String, dynamic> tunnelOptions(AppSettings st) => {
        'dns': XrayConfigBuilder.tunnelDns(st),
        'mtu': st.mtu,
        'excludedRoutes': [
          ...st.excludedRoutes,
          // Android: локальная сеть мимо VPN через исключённые маршруты; на iPhone — флаг excludeLocalNetworks.
          if (st.allowLan && Plat.android) ...AppSettings.routePresets['Локальные сети']!,
        ],
        'includedRoutes': st.includedRoutes,
        'allowLan': st.allowLan,
        'memoryLimit': st.memoryLimitMb,
        'includeAllNetworks': st.includeAllNetworks,
        'disconnectOnSleep': st.disconnectOnSleep,
        'onDemand': st.onDemand,
        'onDemandWifi': st.onDemandWifi,
        'onDemandCellular': st.onDemandCellular,
        'onDemandExcludedSsids': st.onDemandExcludedSsids,
      };

  /// iPhone: применить настройки туннеля (On Demand и т.п.) без подключения.
  Future<void> applyOptions(AppSettings st) async {
    if (!Plat.ios) return;
    try {
      await _ch.invokeMethod('configure', tunnelOptions(st));
    } catch (_) {}
  }

  int? _memoryBytes;
  int? _prevUp, _prevDown;
  String? _statsError;
  final List<String> _diag = [];

  /// iPhone: сколько памяти занимает ядро в расширении VPN.
  int? get memoryBytes => _memoryBytes;

  /// iPhone: почему нет данных о трафике (null — всё в порядке).
  String? get statsError => _statsError;

  void _setStatsError(String? e) {
    if (e != null && e != _statsError) _note('Трафик: $e');
    _statsError = e;
  }

  void _note(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _diag.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $line');
    if (_diag.length > 100) _diag.removeRange(0, _diag.length - 100);
  }

  // ---------- iPhone: связь с расширением VPN ----------

  /// Секретный ключ и порт локального канала 127.0.0.1 к расширению (новые при каждом подключении).
  ({int port, String token})? _ctl;

  Future<({int port, String token})?> _ctlInfo() async {
    if (_ctl != null) return _ctl;
    try {
      final p = await SharedPreferences.getInstance();
      final port = p.getInt('ctlPort');
      final token = p.getString('ctlToken');
      if (port != null && token != null) _ctl = (port: port, token: token);
    } catch (_) {}
    return _ctl;
  }

  Future<({int port, String token})> _newCtl() async {
    final r = Random.secure();
    final token = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    final c = (port: 20000 + r.nextInt(40000), token: token);
    _ctl = c;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('ctlPort', c.port);
      await p.setString('ctlToken', c.token);
    } catch (_) {}
    return c;
  }

  String? _ctlError, _ipcError;

  /// Команда расширению VPN: сначала локальный канал 127.0.0.1, потом сообщение iOS.
  /// null — не ответил ни один путь (причины — в [tunnelError]).
  Future<String?> tunnelCall(String msg, {Duration timeout = const Duration(seconds: 4)}) async {
    final c = await _ctlInfo();
    if (c != null) {
      Socket? sock;
      try {
        sock = await Socket.connect(InternetAddress.loopbackIPv4, c.port, timeout: const Duration(seconds: 2));
        sock.add(utf8.encode('${c.token}\n$msg\n<<end>>\n'));
        await sock.flush();
        final bytes = <int>[];
        await for (final chunk in sock.timeout(timeout)) {
          bytes.addAll(chunk);
        }
        final reply = utf8.decode(bytes, allowMalformed: true);
        if (reply.isNotEmpty) {
          _ctlError = null;
          return reply;
        }
        _ctlError = 'пустой ответ';
      } on TimeoutException {
        _ctlError = 'нет ответа за ${timeout.inSeconds} с';
      } catch (e) {
        _ctlError = e is SocketException ? (e.osError?.message ?? e.message) : '$e';
      } finally {
        sock?.destroy();
      }
    } else {
      _ctlError = 'переподключите VPN';
    }
    try {
      final reply = await _ch.invokeMethod<String>('message', {'text': msg}).timeout(timeout);
      if (reply != null && reply.isNotEmpty && !reply.startsWith('err:')) {
        _ipcError = null;
        return reply;
      }
      _ipcError = reply == null || reply.isEmpty ? 'пустой ответ' : reply.substring(4);
    } on TimeoutException {
      _ipcError = 'нет ответа за ${timeout.inSeconds} с';
    } catch (e) {
      _ipcError = '$e';
    }
    return null;
  }

  /// Почему расширение VPN не ответило.
  String get tunnelError => 'нет связи с расширением VPN (127.0.0.1: ${_ctlError ?? '—'}; iOS: ${_ipcError ?? '—'})';

  @override
  Future<({int up, int down})?> trafficDelta() async {
    if (!Plat.ios) {
      try {
        return parseLibStats(await _ch.invokeMethod<String>('stats').timeout(const Duration(seconds: 4)) ?? '');
      } catch (_) {
        return null;
      }
    }
    final s = (await tunnelCall('stats'))?.trim();
    if (s == null) {
      _setStatsError(tunnelError);
      return null;
    }
    // Расширение VPN отвечает «отправлено,получено,память» — итог с момента подключения.
    final f = s.split(',');
    final up = f.isNotEmpty ? int.tryParse(f[0].trim()) : null;
    final down = f.length > 1 ? int.tryParse(f[1].trim()) : null;
    if (up == null || down == null) {
      _setStatsError('непонятный ответ «$s»');
      return null;
    }
    _setStatsError(null);
    if (f.length >= 3) _memoryBytes = int.tryParse(f[2].trim());
    final pu = _prevUp, pd = _prevDown;
    _prevUp = up;
    _prevDown = down;
    // Первый ответ (или ядро перезапустилось) — весь трафик сессии, дальше — прирост.
    return (
      up: pu == null || up < pu ? up : up - pu,
      down: pd == null || down < pd ? down : down - pd,
    );
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

  /// Ответ ядра «id мс» построчно → карта.
  static Map<String, int> parsePingReply(String reply) {
    final out = <String, int>{};
    for (final line in reply.split('\n')) {
      final f = line.trim().split(' ');
      if (f.length == 2) out[f[0]] = int.tryParse(f[1]) ?? -1;
    }
    return out;
  }

  /// iPhone с включённым VPN: пинг из расширения VPN — его соединения идут мимо туннеля.
  /// [kind]: ping (TCP), icmp или proxy. null — расширение не ответило.
  Future<Map<String, int>?> pingInTunnel(
    String kind,
    List<ServerConfig> servers,
    Duration timeout, {
    AppSettings? settings,
    String method = 'GET',
    String url = '',
  }) async {
    final String msg;
    if (kind == 'proxy') {
      final st = settings ?? AppSettings();
      final batch = [
        for (final s in servers) {'id': s.id, 'config': XrayConfigBuilder.forSingleDelay(s, st)},
      ];
      msg = 'proxy\n${timeout.inMilliseconds}\n$method\n$url\n${jsonEncode(batch)}';
    } else {
      msg = '$kind\n${timeout.inMilliseconds}\n${servers.map((s) => '${s.id} ${s.address} ${s.port}').join('\n')}';
    }
    final waves = kind == 'proxy' ? (servers.length / 2).ceil() : (servers.length / 8).ceil();
    final reply = await tunnelCall(msg, timeout: timeout * (waves + 1) + const Duration(seconds: 3));
    if (reply == null) {
      _note('Пинг: $tunnelError');
      return null;
    }
    return parsePingReply(reply);
  }

  /// iPhone с выключенным VPN: ICMP и пинг через прокси делает ядро Xray внутри приложения.
  Future<Map<String, int>?> pingInApp(
    String kind,
    List<ServerConfig> servers,
    Duration timeout, {
    AppSettings? settings,
    String method = 'GET',
    String url = '',
  }) async {
    try {
      final String? reply;
      if (kind == 'proxy') {
        final st = settings ?? AppSettings();
        final batch = [
          for (final s in servers) {'id': s.id, 'config': XrayConfigBuilder.forSingleDelay(s, st)},
        ];
        reply = await _ch.invokeMethod<String>('coreProxy', {
          'batch': jsonEncode(batch),
          'url': url,
          'method': method,
          'timeoutMs': timeout.inMilliseconds,
          'parallel': 6,
        });
      } else {
        reply = await _ch.invokeMethod<String>('coreIcmp', {
          'list': servers.map((s) => '${s.id} ${s.address} ${s.port}').join('\n'),
          'timeoutMs': timeout.inMilliseconds,
        });
      }
      return reply == null ? null : parsePingReply(reply);
    } catch (e) {
      _note('Пинг: $e');
      return null;
    }
  }

  /// Android: пинг через прокси силами libv2ray (приложение и так идёт мимо VPN).
  Future<Map<String, int>?> proxyPingAndroid(List<ServerConfig> servers, AppSettings st, String url) async {
    try {
      final raw = await _ch.invokeMapMethod<String, dynamic>('proxyPing', {
        'items': [
          for (final s in servers) {'id': s.id, 'config': jsonEncode(XrayConfigBuilder.forSingleDelay(s, st))},
        ],
        'url': url,
      });
      return raw?.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return null;
    }
  }

  /// Android: «Постоянный VPN» и «Блокировать без VPN» (null — VPN выключен или Android старше 10).
  static Future<Map<String, bool>?> alwaysOnState() async {
    try {
      final m = await _ch.invokeMapMethod<String, bool>('alwaysOn');
      return m;
    } catch (_) {
      return null;
    }
  }

  /// Android: открыть системные настройки VPN.
  static Future<bool> openVpnSettings() async {
    try {
      return await _ch.invokeMethod<bool>('openVpnSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Версия ядра Xray (iPhone — ядро в приложении, Android — libv2ray).
  static Future<String?> coreVersion() async {
    try {
      final v = await _ch.invokeMethod<String>('coreVersion');
      if (v == null) return null;
      final m = RegExp(r'Xray-core v?([\w.\-]+)').firstMatch(v);
      return m?.group(1) ?? v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> fetchLogs() async {
    if (Plat.ios) {
      final core = await tunnelCall('logs');
      return [
        ..._diag,
        if (core != null) ...core.split('\n').where((l) => l.trim().isNotEmpty),
        if (core == null) 'Журнал ядра доступен, когда VPN включён ($tunnelError)',
      ];
    }
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
        final st = settings ?? AppSettings();
        await SystemProxy.enable('127.0.0.1', st.httpPort, st.socksPort);
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
