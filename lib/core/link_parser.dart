import 'dart:convert';

import 'server.dart';

/// Разбор ссылок-ключей. Возвращает null, если ссылка не распознана.
class LinkParser {
  static const schemes = ['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2'];

  static bool looksLikeLink(String s) {
    final t = s.trim().toLowerCase();
    return schemes.any((p) => t.startsWith('$p://'));
  }

  static ServerConfig? parse(String raw, {String? subscriptionId}) {
    final link = raw.trim();
    try {
      final lower = link.toLowerCase();
      ServerConfig? s;
      if (lower.startsWith('vless://')) {
        s = _parseUrlStyle(link, 'vless');
      } else if (lower.startsWith('trojan://')) {
        s = _parseUrlStyle(link, 'trojan');
      } else if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
        s = _parseUrlStyle(link, 'hysteria2');
      } else if (lower.startsWith('vmess://')) {
        s = _parseVmess(link);
      } else if (lower.startsWith('ss://')) {
        s = _parseShadowsocks(link);
      }
      return s?.withSubscription(subscriptionId);
    } catch (_) {
      return null;
    }
  }

  /// Разбирает текст: одна ссылка на строку или base64 от такого списка.
  static List<ServerConfig> parseMany(String text, {String? subscriptionId}) {
    var body = text.trim();
    if (!looksLikeLink(body) && !body.contains('://')) {
      final decoded = tryBase64(body);
      if (decoded != null) body = decoded;
    }
    final out = <ServerConfig>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(body)) {
      final l = line.trim();
      if (!looksLikeLink(l)) continue;
      final s = parse(l, subscriptionId: subscriptionId);
      if (s != null && seen.add(s.id)) out.add(s);
    }
    return out;
  }

  // ---------- общие помощники ----------

  static String _dec(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  static String? tryBase64(String input) {
    var s = input.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (s.isEmpty || !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(s)) return null;
    s = s.replaceAll('=', '');
    while (s.length % 4 != 0) {
      s += '=';
    }
    try {
      return utf8.decode(base64.decode(s), allowMalformed: false);
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _query(String q) {
    final m = <String, String>{};
    for (final part in q.split('&')) {
      if (part.isEmpty) continue;
      final i = part.indexOf('=');
      if (i < 0) {
        m[_dec(part)] = '';
      } else {
        m[_dec(part.substring(0, i))] = _dec(part.substring(i + 1));
      }
    }
    return m;
  }

  /// Делит "host:port" с поддержкой IPv6 в квадратных скобках.
  static (String, int) _hostPort(String hp) {
    hp = hp.trim();
    if (hp.endsWith('/')) hp = hp.substring(0, hp.length - 1);
    if (hp.startsWith('[')) {
      final end = hp.indexOf(']');
      final host = hp.substring(1, end);
      final port = int.parse(hp.substring(end + 2));
      return (host, port);
    }
    final i = hp.lastIndexOf(':');
    return (hp.substring(0, i), int.parse(hp.substring(i + 1)));
  }

  static ({String userInfo, String host, int port, Map<String, String> q, String name})
      _split(String link) {
    var rest = link.substring(link.indexOf('://') + 3);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = _dec(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    var q = <String, String>{};
    final qi = rest.indexOf('?');
    if (qi >= 0) {
      q = _query(rest.substring(qi + 1));
      rest = rest.substring(0, qi);
    }
    var userInfo = '';
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      userInfo = _dec(rest.substring(0, at));
      rest = rest.substring(at + 1);
    }
    final (host, port) = _hostPort(rest);
    return (userInfo: userInfo, host: host, port: port, q: q, name: name);
  }

  static List<String> _list(String? s) =>
      (s == null || s.isEmpty) ? const [] : s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static String _network(String? t) {
    final n = (t ?? 'tcp').toLowerCase();
    if (n == 'splithttp') return 'xhttp';
    if (n == 'raw' || n.isEmpty) return 'tcp';
    return n;
  }

  // ---------- форматы ----------

  static ServerConfig _parseUrlStyle(String link, String protocol) {
    final p = _split(link);
    final q = p.q;
    final isHy = protocol == 'hysteria2';
    var security = (q['security'] ?? (protocol == 'trojan' || isHy ? 'tls' : 'none')).toLowerCase();
    if (security.isEmpty) security = 'none';
    return ServerConfig(
      protocol: protocol,
      name: p.name.isEmpty ? '${p.host}:${p.port}' : p.name,
      address: p.host,
      port: p.port,
      secret: p.userInfo,
      link: link,
      network: isHy ? 'hysteria' : _network(q['type']),
      security: isHy ? 'tls' : security,
      sni: q['sni'] ?? q['peer'] ?? '',
      fingerprint: q['fp'] ?? '',
      publicKey: q['pbk'] ?? '',
      shortId: q['sid'] ?? '',
      spiderX: q['spx'] ?? '',
      path: q['path'] ?? '',
      hostHeader: q['host'] ?? '',
      serviceName: q['serviceName'] ?? '',
      xhttpMode: q['mode'] ?? '',
      flow: q['flow'] ?? '',
      alpn: _list(q['alpn']),
      pinnedSha256: q['pcs'] ?? q['pinSHA256'] ?? '',
      verifyName: q['vcn'] ?? '',
      headerType: q['headerType'] ?? '',
    );
  }

  static ServerConfig _parseVmess(String link) {
    final body = link.substring(8).split('#').first;
    final json = jsonDecode(tryBase64(body)!) as Map<String, dynamic>;
    String s(String k) => (json[k] ?? '').toString();
    final tls = s('tls').toLowerCase();
    return ServerConfig(
      protocol: 'vmess',
      name: s('ps').isEmpty ? '${s('add')}:${s('port')}' : s('ps'),
      address: s('add'),
      port: int.parse(s('port')),
      secret: s('id'),
      link: link,
      alterId: int.tryParse(s('aid')) ?? 0,
      vmessSecurity: s('scy').isEmpty ? 'auto' : s('scy'),
      network: _network(s('net')),
      security: tls == 'tls' || tls == 'reality' ? tls : 'none',
      sni: s('sni'),
      fingerprint: s('fp'),
      path: s('path'),
      hostHeader: s('host'),
      serviceName: s('net') == 'grpc' ? s('path') : '',
      alpn: _list(s('alpn')),
      headerType: s('type'),
    );
  }

  static ServerConfig _parseShadowsocks(String link) {
    var rest = link.substring(5);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = _dec(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    final qi = rest.indexOf('?');
    if (qi >= 0) rest = rest.substring(0, qi); // плагины не поддерживаются
    String method, password, hostPort;
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      // SIP002: ss://base64(method:password)@host:port
      var cred = _dec(rest.substring(0, at));
      final decoded = tryBase64(cred);
      if (decoded != null && decoded.contains(':')) cred = decoded;
      final c = cred.indexOf(':');
      method = cred.substring(0, c);
      password = cred.substring(c + 1);
      hostPort = rest.substring(at + 1);
    } else {
      // старый формат: ss://base64(method:password@host:port)
      final decoded = tryBase64(rest)!;
      final a = decoded.lastIndexOf('@');
      final cred = decoded.substring(0, a);
      final c = cred.indexOf(':');
      method = cred.substring(0, c);
      password = cred.substring(c + 1);
      hostPort = decoded.substring(a + 1);
    }
    final (host, port) = _hostPort(hostPort);
    return ServerConfig(
      protocol: 'shadowsocks',
      name: name.isEmpty ? '$host:$port' : name,
      address: host,
      port: port,
      secret: password,
      method: method,
      link: link,
    );
  }
}
