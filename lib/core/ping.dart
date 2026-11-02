import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'server.dart';
import 'settings.dart';
import 'vpn_backend.dart';
import 'xray_config.dart';

/// Замер задержки серверов. Результат: мс; -1 — нет ответа; -2 — метод не подходит (UDP и т.п.).
class Pinger {
  static bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Какие методы доступны на этой платформе.
  static List<PingMethod> get available => _desktop
      ? PingMethod.values
      : const [PingMethod.tcp, PingMethod.icmp];

  static Future<Map<String, int>> pingAll(
    List<ServerConfig> servers,
    AppSettings st, {
    void Function(String id, int ms)? onResult,
  }) async {
    var method = st.pingMethod;
    if (!available.contains(method)) method = PingMethod.tcp;
    final timeout = Duration(seconds: st.pingTimeoutSec.clamp(1, 30).toInt());
    final out = <String, int>{};
    void put(String id, int ms) {
      out[id] = ms;
      onResult?.call(id, ms);
    }

    switch (method) {
      case PingMethod.tcp:
        await Future.wait(servers.map((s) async => put(s.id, await tcp(s, timeout))));
      case PingMethod.icmp:
        await _limited(servers, 8, (s) async => put(s.id, await icmp(s, timeout)));
      case PingMethod.real:
      case PingMethod.httpGet:
      case PingMethod.httpHead:
        await _viaXray(servers, st, method, timeout, put);
    }
    return out;
  }

  // ---------- TCP ----------

  static Future<int> tcp(ServerConfig s, Duration timeout) async {
    if (s.protocol == 'hysteria2') return -2; // UDP — TCP-пингом не измерить
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(s.address, s.port, timeout: timeout);
      sw.stop();
      sock.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  // ---------- ICMP (системная команда ping) ----------

  static Future<int> icmp(ServerConfig s, Duration timeout) async {
    try {
      final ProcessResult r;
      if (Platform.isWindows) {
        r = await Process.run('ping', ['-n', '1', '-w', '${timeout.inMilliseconds}', s.address]);
      } else if (Platform.isMacOS) {
        r = await Process.run('ping', ['-c', '1', '-W', '${timeout.inMilliseconds}', s.address]);
      } else {
        r = await Process.run('ping', ['-c', '1', '-W', '${timeout.inSeconds}', s.address]);
      }
      final text = r.stdout.toString();
      // Windows: «время=45мс TTL=56» / «time<1ms TTL=56» (кодировка консоли может исказить «мс»)
      final win = RegExp(r'[=<](\d+)\D{1,6}TTL', caseSensitive: false).firstMatch(text);
      if (win != null) return int.parse(win.group(1)!);
      final unix = RegExp(r'time[=<]([\d.]+)\s*ms').firstMatch(text);
      if (unix != null) return double.parse(unix.group(1)!).round();
      return -1;
    } catch (_) {
      return -1;
    }
  }

  // ---------- Через ядро: реальная задержка / HTTP GET / HEAD ----------

  static Future<void> _viaXray(
    List<ServerConfig> servers,
    AppSettings st,
    PingMethod method,
    Duration timeout,
    void Function(String, int) put,
  ) async {
    final xray = DesktopVpnBackend.xrayPath();
    if (!File(xray).existsSync() || servers.isEmpty) {
      for (final s in servers) {
        put(s.id, await tcp(s, timeout));
      }
      return;
    }
    final basePort = 21000 + Random().nextInt(20000);
    final cfg = XrayConfigBuilder.forDelayTest(servers, basePort, st);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}kuduzo-ping-$basePort.json');
    await file.writeAsString(jsonEncode(cfg));

    Process? proc;
    try {
      proc = await Process.start(
        xray,
        ['run', '-c', file.path],
        workingDirectory: DesktopVpnBackend.coreDir().path,
        environment: {'XRAY_LOCATION_ASSET': DesktopVpnBackend.coreDir().path},
      );
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();

      // Ждём, пока ядро откроет порт.
      final ready = await _waitPort(basePort, const Duration(seconds: 5));
      if (!ready) {
        for (final s in servers) {
          put(s.id, -1);
        }
        return;
      }

      final uri = Uri.parse(st.testUrl);
      var i = 0;
      final indexed = servers.map((s) => (i++, s)).toList();
      await _limited(indexed, 12, (e) async {
        final (idx, s) = e;
        put(s.id, await _httpDelay(basePort + idx, uri, method, timeout));
      });
    } catch (_) {
      for (final s in servers) {
        put(s.id, -1);
      }
    } finally {
      proc?.kill();
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static Future<bool> _waitPort(int port, Duration max) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < max) {
      try {
        final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 300));
        s.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  static Future<int> _httpDelay(int port, Uri uri, PingMethod method, Duration timeout) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 5)
      ..userAgent = 'Kuduzo';

    Future<int> once() async {
      final sw = Stopwatch()..start();
      final req = method == PingMethod.httpHead ? await client.headUrl(uri) : await client.getUrl(uri);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      sw.stop();
      if (res.statusCode >= 500) return -1;
      return sw.elapsedMilliseconds;
    }

    try {
      final first = await once().timeout(timeout * 2);
      if (method != PingMethod.real) return first;
      // «Реальная задержка»: второй запрос по уже открытому соединению —
      // время одного обмена через сервер, без установки TLS.
      try {
        return await once().timeout(timeout);
      } catch (_) {
        return first;
      }
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _limited<T>(List<T> items, int parallel, Future<void> Function(T) f) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        await f(item);
      }
    }

    await Future.wait(List.generate(min(parallel, items.length), (_) => worker()));
  }
}
