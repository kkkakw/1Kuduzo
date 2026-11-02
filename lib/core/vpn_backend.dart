import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'server.dart';
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

  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun});

  Future<void> stop();

  static VpnBackend create() {
    if (Platform.isAndroid || Platform.isIOS) return MobileVpnBackend();
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
  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun}) async {
    final allowed = await _ch.invokeMethod<bool>('prepare') ?? false;
    if (!allowed) {
      _ctrl.add(const VpnStatus(VpnState.error, 'Нужно разрешить подключение VPN'));
      return;
    }
    final config = XrayConfigBuilder.build(server, routing: routing, inbound: InboundMode.tunMobile);
    _ctrl.add(const VpnStatus(VpnState.connecting));
    await _ch.invokeMethod('start', {'config': jsonEncode(config), 'name': server.name});
  }

  @override
  Future<void> stop() async {
    await _ch.invokeMethod('stop');
  }

  void dispose() => _sub?.cancel();
}

/// Windows / macOS — запускаем xray как отдельный процесс.
class DesktopVpnBackend implements VpnBackend {
  final _ctrl = StreamController<VpnStatus>.broadcast();
  Process? _proc;
  bool _proxySet = false;
  bool _stopping = false;

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
  Future<void> start(ServerConfig server, RoutingMode routing, {required bool tun}) async {
    await stop();
    _stopping = false;
    _ctrl.add(const VpnStatus(VpnState.connecting));

    final xray = xrayPath();
    if (!File(xray).existsSync()) {
      _ctrl.add(VpnStatus(VpnState.error, 'Не найдено ядро Xray: $xray'));
      return;
    }

    final inbound = tun ? InboundMode.tunDesktop : InboundMode.proxy;
    final config = XrayConfigBuilder.build(server, routing: routing, inbound: inbound);
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
    void collect(String line) {
      errLines.add(line);
      if (errLines.length > 20) errLines.removeAt(0);
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
