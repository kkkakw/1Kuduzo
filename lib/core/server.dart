import 'country.dart';
/// Один сервер (ключ), разобранный из ссылки vless://, vmess://, trojan://, ss://, hysteria2://.
class ServerConfig {
  ServerConfig({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
    required this.secret,
    required this.link,
    this.method = '',
    this.network = 'tcp',
    this.security = 'none',
    this.sni = '',
    this.fingerprint = '',
    this.publicKey = '',
    this.shortId = '',
    this.spiderX = '',
    this.path = '',
    this.hostHeader = '',
    this.serviceName = '',
    this.xhttpMode = '',
    this.flow = '',
    this.alpn = const [],
    this.pinnedSha256 = '',
    this.verifyName = '',
    this.alterId = 0,
    this.vmessSecurity = 'auto',
    this.headerType = '',
    this.subscriptionId,
  });

  /// vless | vmess | trojan | shadowsocks | hysteria2
  final String protocol;
  final String name;
  final String address;
  final int port;

  /// UUID (vless/vmess), пароль (trojan/ss), auth (hysteria2).
  final String secret;

  /// Исходная ссылка — по ней сервер хранится и восстанавливается.
  final String link;

  final String method; // шифрование shadowsocks
  final String network; // tcp, ws, grpc, xhttp, httpupgrade, kcp
  final String security; // none, tls, reality
  final String sni;
  final String fingerprint;
  final String publicKey;
  final String shortId;
  final String spiderX;
  final String path;
  final String hostHeader;
  final String serviceName;
  final String xhttpMode;
  final String flow;
  final List<String> alpn;
  /// pinnedPeerCertSha256 / verifyPeerCertByName (замена удалённого allowInsecure в Xray).
  final String pinnedSha256;
  final String verifyName;
  final int alterId;
  final String vmessSecurity;
  final String headerType;
  final String? subscriptionId;

  /// Стабильный идентификатор (FNV-1a от ссылки) — одинаковый между запусками.
  String get id {
    var h = 0x811c9dc5;
    for (final c in link.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// Страна по названию или адресу (код «nl», «de»…); null — определит AppState по IP.
  String? get country => Country.detect(name, host: address);

  /// Код страны из флага в названии (🇪🇪 → EE), иначе первые буквы.
  String get badge {
    final runes = name.runes.toList();
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 &&
        runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 &&
        runes[1] <= 0x1F1FF) {
      return String.fromCharCodes([runes[0] - 0x1F1E6 + 65, runes[1] - 0x1F1E6 + 65]);
    }
    final letters = name.replaceAll(RegExp(r'[^A-Za-zА-Яа-яЁё0-9]'), '');
    if (letters.isEmpty) return '•';
    return letters.substring(0, letters.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Название без флага в начале.
  String get title {
    final runes = name.runes.toList();
    var i = 0;
    while (i < runes.length && runes[i] >= 0x1F1E6 && runes[i] <= 0x1F1FF) {
      i++;
    }
    final rest = String.fromCharCodes(runes.sublist(i)).trim();
    return rest.isEmpty ? '$address:$port' : rest;
  }

  String get protocolLabel {
    const names = {
      'vless': 'VLESS',
      'vmess': 'VMess',
      'trojan': 'Trojan',
      'shadowsocks': 'Shadowsocks',
      'hysteria2': 'Hysteria2',
    };
    final p = names[protocol] ?? protocol;
    final parts = <String>[p];
    if (security == 'reality') parts.add('Reality');
    if (network != 'tcp' && protocol != 'hysteria2' && protocol != 'shadowsocks') {
      parts.add(network.toUpperCase() == 'XHTTP' ? 'XHTTP' : network);
    }
    return parts.join(' · ');
  }

  ServerConfig withSubscription(String? subId) => ServerConfig(
        protocol: protocol,
        name: name,
        address: address,
        port: port,
        secret: secret,
        link: link,
        method: method,
        network: network,
        security: security,
        sni: sni,
        fingerprint: fingerprint,
        publicKey: publicKey,
        shortId: shortId,
        spiderX: spiderX,
        path: path,
        hostHeader: hostHeader,
        serviceName: serviceName,
        xhttpMode: xhttpMode,
        flow: flow,
        alpn: alpn,
        pinnedSha256: pinnedSha256,
        verifyName: verifyName,
        alterId: alterId,
        vmessSecurity: vmessSecurity,
        headerType: headerType,
        subscriptionId: subId,
      );
}
