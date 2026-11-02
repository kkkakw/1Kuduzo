import 'server.dart';

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
    String logLevel = 'warning',
  }) {
    final sniffing = {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    };

    final inbounds = <Map<String, dynamic>>[];
    switch (inbound) {
      case InboundMode.proxy:
        inbounds.addAll([
          {
            'tag': 'socks',
            'listen': '127.0.0.1',
            'port': socksPort,
            'protocol': 'socks',
            'settings': {'udp': true},
            'sniffing': sniffing,
          },
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
          'settings': {'name': 'xray0', 'mtu': 1500},
          'sniffing': sniffing,
        });
      case InboundMode.tunDesktop:
        inbounds.add({
          'tag': 'tun',
          'protocol': 'tun',
          'settings': {
            'name': 'Kuduzo',
            'mtu': 1500,
            'gateway': ['172.19.0.1/30'],
            'dns': ['1.1.1.1'],
            'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
          },
          'sniffing': sniffing,
        });
        // Локальный прокси тоже оставляем — удобно для отладки и браузерных расширений.
        inbounds.add({
          'tag': 'socks',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': {'udp': true},
          'sniffing': sniffing,
        });
    }

    final rules = <Map<String, dynamic>>[
      if (inbound != InboundMode.proxy)
        {
          'type': 'field',
          'inboundTag': ['tun'],
          'port': '53',
          'outboundTag': 'dns-out',
        },
      {
        'type': 'field',
        'ip': ['geoip:private'],
        'outboundTag': 'direct',
      },
      if (routing == RoutingMode.smart) ...[
        {
          'type': 'field',
          'domain': ['geosite:category-ru', 'domain:ru', 'domain:su', 'domain:xn--p1ai'],
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
      'log': {'loglevel': logLevel},
      'dns': {
        'servers': ['1.1.1.1', '8.8.8.8'],
      },
      'inbounds': inbounds,
      'outbounds': [
        outbound(s),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
        {'tag': 'dns-out', 'protocol': 'dns'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      },
    };
  }

  /// Конфиг только для замера задержки: один SOCKS-вход и исходящий на сервер.
  static Map<String, dynamic> forDelayTest(ServerConfig s) => {
        'log': {'loglevel': 'none'},
        'inbounds': <Map<String, dynamic>>[],
        'outbounds': [outbound(s)],
      };

  static Map<String, dynamic> outbound(ServerConfig s) {
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
