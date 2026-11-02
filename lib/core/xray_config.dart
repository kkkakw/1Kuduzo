import 'server.dart';
import 'settings.dart';

/// Режим маршрутизации.
enum RoutingMode {
  /// Российские сайты напрямую, остальное через VPN.
  smart,

  /// Весь трафик через VPN (кроме локальной сети).
  all,
}

/// Как трафик попадает в Xray.
enum InboundMode {
  /// Локальные SOCKS5 + HTTP прокси (десктоп, «системный прокси»).
  proxy,

  /// TUN на Android/iOS: fd передаёт система (VpnService / NetworkExtension).
  tunMobile,

  /// TUN на Windows/macOS: Xray сам создаёт адаптер и маршруты (нужны права администратора).
  tunDesktop,
}

class XrayConfigBuilder {
  static const socksPort = 10808;
  static const httpPort = 10809;

  static Map<String, dynamic> build(
    ServerConfig s, {
    required RoutingMode routing,
    required InboundMode inbound,
    AppSettings? settings,
    bool windows = false,
    bool lite = false, // iOS: без geosite.dat — расширению VPN доступно ~50 МБ памяти
  }) {
    final st = settings ?? AppSettings();
    final sniffing = {
      'enabled': st.sniffing,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': st.routeOnly,
    };
    final socks = {
      'tag': 'socks',
      'listen': '127.0.0.1',
      'port': socksPort,
      'protocol': 'socks',
      'settings': {'udp': true},
      'sniffing': sniffing,
    };

    final inbounds = <Map<String, dynamic>>[];
    switch (inbound) {
      case InboundMode.proxy:
        inbounds.addAll([
          socks,
          {
            'tag': 'http',
            'listen': '127.0.0.1',
            'port': httpPort,
            'protocol': 'http',
            'sniffing': sniffing,
          },
        ]);
      case InboundMode.tunMobile:
        inbounds.add({
          'tag': 'tun',
          'protocol': 'tun',
          'settings': {'name': 'xray0', 'mtu': st.mtu},
          'sniffing': sniffing,
        });
      case InboundMode.tunDesktop:
        inbounds.add({
          'tag': 'tun',
          'protocol': 'tun',
          'settings': {
            'name': 'Kuduzo',
            'mtu': st.mtu,
            'gateway': ['172.19.0.1/30'],
            'dns': [_tunDns(st)],
            'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
            if (windows && st.leakProtection) 'autoSystemWfpBlockLeak': ['dns'],
          },
          'sniffing': sniffing,
        });
        // Локальный прокси тоже оставляем — удобно для отладки и браузерных расширений.
        inbounds.add(socks);
    }

    final rules = <Map<String, dynamic>>[
      if (inbound != InboundMode.proxy)
        {
          'type': 'field',
          'inboundTag': ['tun'],
          'port': '53',
          'outboundTag': 'dns-out',
        },
      if (st.allowLan)
        {
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        },
      if (routing == RoutingMode.smart) ...[
        {
          'type': 'field',
          'domain': [if (!lite) 'geosite:category-ru', 'domain:ru', 'domain:su', 'domain:xn--p1ai'],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'ip': ['geoip:ru'],
          'outboundTag': 'direct',
        },
      ],
    ];

    return {
      'log': {'loglevel': st.logLevel},
      'dns': _dns(st),
      'policy': _policy(st),
      'inbounds': inbounds,
      'outbounds': [
        outbound(s, settings: st),
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': _freedomStrategy(st)},
        },
        {'tag': 'block', 'protocol': 'blackhole'},
        {'tag': 'dns-out', 'protocol': 'dns'},
        if (_dialer(s, st) != null) _dialer(s, st)!,
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      },
    };
  }

  /// Один процесс Xray для замера задержки сразу у многих серверов:
  /// i-й HTTP-вход на порту basePort+i ведёт на i-й сервер.
  static Map<String, dynamic> forDelayTest(List<ServerConfig> servers, int basePort, AppSettings st) {
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    var needDialer = false;
    for (var i = 0; i < servers.length; i++) {
      inbounds.add({'tag': 'in$i', 'listen': '127.0.0.1', 'port': basePort + i, 'protocol': 'http'});
      outbounds.add(outbound(servers[i], tag: 'out$i', settings: st));
      rules.add({'type': 'field', 'inboundTag': ['in$i'], 'outboundTag': 'out$i'});
      if (_dialer(servers[i], st) != null) needDialer = true;
    }
    if (needDialer) outbounds.add(_dialerOutbound(st));
    return {
      'log': {'loglevel': 'none'},
      'dns': _dns(st),
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'rules': rules},
    };
  }

  static String _tunDns(AppSettings st) {
    for (final d in st.dnsServers) {
      if (RegExp(r'^[0-9.]+$').hasMatch(d) || (d.contains(':') && !d.contains('/'))) return d;
    }
    return '1.1.1.1';
  }

  static Map<String, dynamic> _dns(AppSettings st) => {
        'servers': [...st.dnsServers, if (!st.dnsServers.contains('8.8.8.8')) '8.8.8.8'],
        'queryStrategy': switch (st.ipType) {
          IpType.auto => 'UseIP',
          IpType.ipv4 => 'UseIPv4',
          IpType.ipv6 => 'UseIPv6',
        },
      };

  static String _freedomStrategy(AppSettings st) => switch (st.ipType) {
        IpType.auto => 'AsIs',
        IpType.ipv4 => 'UseIPv4',
        IpType.ipv6 => 'UseIPv6',
      };

  static Map<String, dynamic> _policy(AppSettings st) => {
        'levels': {
          '0': {'connIdle': st.connIdle},
        },
      };

  static bool _tlsLike(ServerConfig s) =>
      s.protocol != 'hysteria2' && (s.security == 'tls' || s.security == 'reality');

  /// Нужен ли промежуточный freedom-выход для фрагментации/шума.
  static Map<String, dynamic>? _dialer(ServerConfig s, AppSettings st) {
    final frag = st.fragment && _tlsLike(s);
    if (!frag && !st.noises) return null;
    return _dialerOutbound(st);
  }

  static Map<String, dynamic> _dialerOutbound(AppSettings st) => {
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': _freedomStrategy(st),
          if (st.fragment)
            'fragment': {
              'packets': st.fragmentPackets,
              'length': st.fragmentLength,
              'interval': st.fragmentInterval,
            },
          if (st.noises)
            'noises': [
              {'type': 'rand', 'packet': '10-20', 'delay': '10-16'},
            ],
        },
      };

  /// Исходящее соединение к серверу с учётом Mux и фрагментации.
  static Map<String, dynamic> outbound(ServerConfig s, {String tag = 'proxy', AppSettings? settings}) {
    final st = settings ?? AppSettings();
    final o = _outboundBase(s);
    o['tag'] = tag;
    final muxOk = st.mux &&
        s.flow.isEmpty &&
        s.network != 'xhttp' &&
        s.protocol != 'hysteria2' &&
        s.protocol != 'shadowsocks';
    if (muxOk) {
      o['mux'] = {'enabled': true, 'concurrency': st.muxConcurrency};
    }
    if (_dialer(s, st) != null) {
      final stream = Map<String, dynamic>.from((o['streamSettings'] as Map?) ?? const {});
      stream['sockopt'] = {'dialerProxy': 'fragment'};
      o['streamSettings'] = stream;
    }
    return o;
  }

  static Map<String, dynamic> _outboundBase(ServerConfig s) {
    switch (s.protocol) {
      case 'vless':
        return {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': s.address,
                'port': s.port,
                'users': [
                  {
                    'id': s.secret,
                    'encryption': 'none',
                    if (s.flow.isNotEmpty) 'flow': s.flow,
                  }
                ],
              }
            ],
          },
          'streamSettings': _stream(s),
        };
      case 'vmess':
        return {
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': s.address,
                'port': s.port,
                'users': [
                  {'id': s.secret, 'alterId': s.alterId, 'security': s.vmessSecurity}
                ],
              }
            ],
          },
          'streamSettings': _stream(s),
        };
      case 'trojan':
        return {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {'address': s.address, 'port': s.port, 'password': s.secret}
            ],
          },
          'streamSettings': _stream(s),
        };
      case 'shadowsocks':
        return {
          'tag': 'proxy',
          'protocol': 'shadowsocks',
          'settings': {
            'servers': [
              {'address': s.address, 'port': s.port, 'method': s.method, 'password': s.secret}
            ],
          },
        };
      case 'hysteria2':
        return {
          'tag': 'proxy',
          'protocol': 'hysteria',
          'settings': {'version': 2, 'address': s.address, 'port': s.port},
          'streamSettings': {
            'network': 'hysteria',
            'security': 'tls',
            'tlsSettings': {
              'serverName': s.sni.isNotEmpty ? s.sni : s.address,
              'alpn': ['h3'],
              ..._pin(s),
            },
            'hysteriaSettings': {'version': 2, 'auth': s.secret},
          },
        };
    }
    throw ArgumentError('Неизвестный протокол ${s.protocol}');
  }

  static Map<String, dynamic> _pin(ServerConfig s) => {
        if (s.pinnedSha256.isNotEmpty) 'pinnedPeerCertSha256': s.pinnedSha256,
        if (s.verifyName.isNotEmpty) 'verifyPeerCertByName': s.verifyName,
      };

  static Map<String, dynamic> _stream(ServerConfig s) {
    final st = <String, dynamic>{'network': s.network, 'security': s.security};
    final host = s.hostHeader;

    switch (s.network) {
      case 'ws':
        st['wsSettings'] = {
          'path': s.path.isEmpty ? '/' : s.path,
          if (host.isNotEmpty) 'host': host,
        };
      case 'httpupgrade':
        st['httpupgradeSettings'] = {
          'path': s.path.isEmpty ? '/' : s.path,
          if (host.isNotEmpty) 'host': host,
        };
      case 'grpc':
        st['grpcSettings'] = {
          'serviceName': s.serviceName.isNotEmpty ? s.serviceName : s.path.replaceFirst('/', ''),
          if (s.xhttpMode == 'multi') 'multiMode': true,
        };
      case 'xhttp':
        st['xhttpSettings'] = {
          'path': s.path.isEmpty ? '/' : s.path,
          if (host.isNotEmpty) 'host': host,
          'mode': s.xhttpMode.isEmpty ? 'auto' : s.xhttpMode,
        };
      case 'tcp':
        if (s.headerType == 'http') {
          st['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [s.path.isEmpty ? '/' : s.path],
                if (host.isNotEmpty)
                  'headers': {
                    'Host': [host]
                  },
              },
            },
          };
        }
    }

    if (s.security == 'tls') {
      st['tlsSettings'] = {
        'serverName': s.sni.isNotEmpty ? s.sni : (host.isNotEmpty ? host : s.address),
        'fingerprint': s.fingerprint.isNotEmpty ? s.fingerprint : 'chrome',
        if (s.alpn.isNotEmpty) 'alpn': s.alpn,
        ..._pin(s),
      };
    } else if (s.security == 'reality') {
      st['realitySettings'] = {
        'serverName': s.sni,
        'fingerprint': s.fingerprint.isNotEmpty ? s.fingerprint : 'chrome',
        'publicKey': s.publicKey,
        'shortId': s.shortId,
        'spiderX': s.spiderX,
      };
    }
    return st;
  }
}
