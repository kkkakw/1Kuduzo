import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuduzo/core/country.dart';
import 'package:kuduzo/core/link_parser.dart';
import 'package:kuduzo/core/settings.dart';
import 'package:kuduzo/core/subscription.dart';
import 'package:kuduzo/i18n.dart';
import 'package:kuduzo/core/vpn_backend.dart';
import 'package:kuduzo/core/xray_config.dart';

// Тестовые ключи: данные выдуманы, совпадает только формат.
const vlessReality =
    'vless://00000000-1111-2222-3333-444444444444@203.0.113.10:443?type=xhttp&security=reality&fp=firefox&sni=vpnkuduzo.ru&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef&spx=/&path=/testpath0001#%F0%9F%87%AA%F0%9F%87%AA%20%D0%AD%D1%81%D1%82%D0%BE%D0%BD%D0%B8%D1%8F';
const vlessVision =
    'vless://11111111-2222-3333-4444-555555555555@nl.example.com:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.microsoft.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=ab#NL';
const trojanWs = 'trojan://pass%40word@1.2.3.4:443?type=ws&security=tls&sni=a.example.com&path=%2Fws&host=a.example.com#Trojan%20WS';
const ssSip002 = 'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA@5.6.7.8:8388#SS';
const hy2 = 'hy2://secret@9.9.9.9:443?sni=h.example.com#HY2';

String vmessLink() {
  final j = {
    'v': '2',
    'ps': 'VMess gRPC',
    'add': '1.2.3.4',
    'port': '443',
    'id': '00000000-1111-2222-3333-444444444444',
    'aid': '0',
    'scy': 'auto',
    'net': 'grpc',
    'path': 'grpcsvc',
    'tls': 'tls',
    'sni': 'g.example.com',
    'alpn': 'h2',
  };
  return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
}

void main() {
  test('VLESS + Reality + XHTTP', () {
    final s = LinkParser.parse(vlessReality)!;
    expect(s.protocol, 'vless');
    expect(s.address, '203.0.113.10');
    expect(s.port, 443);
    expect(s.network, 'xhttp');
    expect(s.security, 'reality');
    expect(s.sni, 'vpnkuduzo.ru');
    expect(s.path, '/testpath0001');
    expect(s.badge, 'EE');
    expect(s.title, 'Эстония');
  });

  test('другие протоколы', () {
    expect(LinkParser.parse(vlessVision)!.flow, 'xtls-rprx-vision');
    final t = LinkParser.parse(trojanWs)!;
    expect(t.secret, 'pass@word');
    expect(t.path, '/ws');
    final ss = LinkParser.parse(ssSip002)!;
    expect(ss.method, 'chacha20-ietf-poly1305');
    expect(ss.secret, 'password');
    final h = LinkParser.parse(hy2)!;
    expect(h.protocol, 'hysteria2');
    final v = LinkParser.parse(vmessLink())!;
    expect(v.network, 'grpc');
    expect(v.serviceName, 'grpcsvc');
  });

  test('подписка в base64', () {
    final body = base64.encode(utf8.encode([vlessReality, trojanWs, 'мусор', hy2].join('\n')));
    expect(LinkParser.parseMany(body).length, 3);
  });

  test('конфиги Xray сохраняются для проверки ядром', () {
    final dir = Directory('build/xray_test_configs')..createSync(recursive: true);
    final links = [vlessReality, vlessVision, trojanWs, ssSip002, hy2, vmessLink()];
    var n = 0;
    for (final l in links) {
      final s = LinkParser.parse(l)!;
      for (final inb in InboundMode.values) {
        for (final r in RoutingMode.values) {
          final cfg = XrayConfigBuilder.build(s, routing: r, inbound: inb);
          File('${dir.path}/${s.protocol}_${inb.name}_${r.name}_${n++}.json')
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
        }
      }
    }
    expect(n, links.length * InboundMode.values.length * RoutingMode.values.length);

    // Все «тяжёлые» настройки сразу.
    final heavy = AppSettings()
      ..fragment = true
      ..fragmentPackets = '1-3'
      ..noises = true
      ..mux = true
      ..ipType = IpType.ipv4
      ..dns = 'https://1.1.1.1/dns-query, 8.8.8.8'
      ..allowLan = false
      ..sniffing = false
      ..mtu = 1380
      ..logLevel = 'debug'
      ..routingEnabled = true
      ..directSites = ['example.ru', 'geosite:category-ru', '*.local.test']
      ..directIps = ['192.168.0.0/16', 'geoip:ru']
      ..proxySites = ['https://youtube.com/watch', 'full:instagram.com']
      ..proxyIps = ['8.8.8.8/32']
      ..blockSites = ['keyword:ads']
      ..blockIps = ['1.2.3.4']
      ..socksAuth = true
      ..socksPass = 'secret'
      ..socksPort = 20808
      ..httpPort = 20809
      ..mobileLocalProxy = true
      ..excludedRoutes = ['17.0.0.0/8']
      ..includedRoutes = ['0.0.0.0/1', '128.0.0.0/1'];
    for (final l in links) {
      final s = LinkParser.parse(l)!;
      for (final inb in InboundMode.values) {
        final cfg = XrayConfigBuilder.build(s,
          routing: RoutingMode.smart, inbound: inb, settings: heavy, stats: true, statsApi: inb != InboundMode.tunMobile, lite: inb == InboundMode.tunMobile);
        File('${dir.path}/heavy_${s.protocol}_${inb.name}_${n++}.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
      }
    }

    // Пакетный замер задержки.
    final all = links.map((l) => LinkParser.parse(l)!).toList();
    for (final st in [AppSettings(), heavy]) {
      final cfg = XrayConfigBuilder.forDelayTest(all, 30000, st);
      File('${dir.path}/delay_${n++}.json').writeAsStringSync(jsonEncode(cfg));
    }
  });

  test('ссылки kuduzo://', () {
    const sub = 'https://vpnkuduzo.ru/sub/abc?device_key=XYZ';
    expect(LinkParser.fromAppLink('kuduzo://import/$sub'), sub);
    expect(LinkParser.fromAppLink('kuduzo://add/$sub'), sub);
    expect(LinkParser.fromAppLink('kuduzo://add?url=${Uri.encodeComponent(sub)}'), sub);
    expect(LinkParser.fromAppLink('kuduzo://${base64.encode(utf8.encode(sub))}'), sub);
    expect(LinkParser.fromAppLink('kuduzo://import/$vlessReality')!.startsWith('vless://'), true);
    expect(LinkParser.fromAppLink('kuduzo://'), null);
  });

  test('статистика libv2ray', () {
    final r = MobileVpnBackend.parseLibStats('proxy,uplink,100;proxy,downlink,2000;direct,downlink,5;');
    expect(r.up, 100);
    expect(r.down, 2000);
  });

  test('свои правила маршрутизации', () {
    expect(XrayConfigBuilder.domainRule('https://youtube.com/watch'), 'domain:youtube.com');
    expect(XrayConfigBuilder.domainRule('*.example.com'), 'domain:example.com');
    expect(XrayConfigBuilder.domainRule('geosite:google'), 'geosite:google');
    final st = AppSettings()
      ..routingEnabled = true
      ..blockSites = ['ads.com']
      ..proxyIps = ['8.8.8.8'];
    final r = XrayConfigBuilder.customRules(st);
    expect(r.first['outboundTag'], 'block');
    expect(r.last['outboundTag'], 'proxy');
    final happ = AppSettings();
    expect(happ.importRouting({'Name': 'RU', 'DirectSites': ['geosite:ru'], 'BlockIp': ['1.1.1.1']}), isTrue);
    expect(happ.routingName, 'RU');
    expect(happ.directSites, ['geosite:ru']);
    expect(happ.importRouting({'foo': 1}), isFalse);
  });

  test('настройки сохраняются и читаются', () {
    final a = AppSettings()
      ..pingMethod = PingMethod.httpHead
      ..sort = ServerSort.name
      ..updateIntervalHours = 6
      ..userAgent = 'Test/1.0'
      ..theme = ThemePref.dark
      ..pingView = PingView.both
      ..onDemandExcludedSsids = ['Home'];
    final b = AppSettings.decode(a.encode());
    expect(b.pingMethod, PingMethod.httpHead);
    expect(b.sort, ServerSort.name);
    expect(b.updateIntervalHours, 6);
    expect(b.userAgent, 'Test/1.0');
    expect(b.theme, ThemePref.dark);
    expect(b.pingView, PingView.both);
    expect(b.onDemandExcludedSsids, ['Home']);
    expect(AppSettings.decode('мусор').pingMethod, PingMethod.real);
  });

  test('страна сервера по названию и адресу', () {
    final cases = {
      '🇪🇪 Эстония': 'ee',
      'Нидерланды': 'nl',
      'Сервер в Германии': 'de',
      'DE-2 Frankfurt': 'de',
      'US West': 'us',
      'Великобритания': 'gb',
      'Финляндия 🔥': 'fi',
      'Япония': 'jp',
      'Tokyo #3': 'jp',
      'Казахстан, Алматы': 'kz',
      'Быстрый 🇸🇪': 'se',
      '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F} London': 'gb-eng',
      'nl-3': 'nl',
    };
    cases.forEach((name, code) => expect(Country.detect(name), code, reason: name));
    expect(Country.detect('Осталось 50 GB'), isNull);
    expect(Country.detect('VLESS Reality'), isNull);
    expect(Country.detect('Сервер 1', host: 'nl1.example.com'), 'nl');
    expect(Country.detect('Сервер 1', host: 'my.vpn.com'), isNull);
    expect(Country.detect('Сервер 1', host: '203.0.113.10'), isNull);
    expect(flagAsset('NL'), 'assets/flags/nl.png');
    expect(flagAsset('zz'), isNull);
    expect(File('assets/flags/nl.png').existsSync(), isTrue);
  });

  test('пинг через прокси: конфиг одного сервера и разбор ответа ядра', () {
    final srv = LinkParser.parse(vlessReality)!;
    final cfg = XrayConfigBuilder.forSingleDelay(srv, AppSettings());
    final outs = cfg['outbounds'] as List;
    expect((outs.first as Map)['tag'], 'proxy');
    expect(cfg.containsKey('inbounds'), isFalse);
    final r = MobileVpnBackend.parsePingReply('a1 120\nb2 -1\nмусор\n');
    expect(r, {'a1': 120, 'b2': -1});
  });

  test('документы для раздела «О приложении» на месте', () {
    for (final f in ['terms', 'privacy', 'consent']) {
      final text = File('assets/legal/$f.md').readAsStringSync();
      expect(text.startsWith('# '), isTrue, reason: f);
      expect(text.contains('t.me/kuduzohelpbot'), isTrue, reason: f);
    }
  });

  test('сведения подписки из заголовков и из тела', () {
    final body = [
      '#profile-title: base64:${base64.encode(utf8.encode('Мой VPN'))}',
      '#announce: Работаем по всему миру',
      '#support-url: https://t.me/example_support',
      vlessReality,
      'vless://00000000-1111-2222-3333-444444444444@0.0.0.0:1?type=tcp#Осталось%2030%20дней',
    ].join('\n');
    final meta = SubscriptionClient.collectMeta({
      'subscription-userinfo': 'upload=10; download=20; total=1000; expire=0',
      'profile-web-page-url': 'https://t.me/example_channel',
      'announce': 'base64:${base64.encode(utf8.encode('Из заголовка'))}',
      'profile-update-interval': '6',
    }, base64.encode(utf8.encode(body)));
    final sub = Subscription(id: 's1', url: 'https://example.com/sub');
    SubscriptionClient.applyMeta(sub, meta);
    sub.links = [vlessReality, 'vless://00000000-1111-2222-3333-444444444444@0.0.0.0:1?type=tcp#Осталось%2030%20дней'];
    expect(sub.title, 'Мой VPN');
    expect(sub.announce, 'Из заголовка'); // заголовок важнее строки в теле
    expect(sub.supportUrl, 'https://t.me/example_support');
    expect(sub.webPageUrl, 'https://t.me/example_channel');
    expect(sub.upload + sub.download, 30);
    expect(sub.total, 1000);
    expect(sub.expire, isNull);
    expect(sub.updateHours, 6);
    expect(sub.servers.length, 1);
    expect(sub.notes, ['Осталось 30 дней']);
    final back = Subscription.fromJson(jsonDecode(jsonEncode(sub.toJson())) as Map<String, dynamic>);
    expect(back.announce, 'Из заголовка');
    expect(back.updateHours, 6);

    final cd = Subscription(id: 's2', url: 'https://example.com/2');
    SubscriptionClient.applyMeta(cd, {'content-disposition': "attachment; filename*=UTF-8''%D0%9F%D1%80%D0%BE%D0%B2%D0%B0%D0%B9%D0%B4%D0%B5%D1%80"});
    expect(cd.title, 'Провайдер');
  });

  test('английский интерфейс: словарь и строки с числами', () {
    L.apply(AppLang.en);
    expect(tr('Настройки'), 'Settings');
    expect(tr('Соединение защищено'), 'Connection protected');
    expect(tr('Пока пусто.\nДобавьте ссылку на подписку Kuduzo.'), 'Nothing here yet.\nAdd your Kuduzo subscription link.');
    expect(tr('Осталось 1 день'), '1 day left');
    expect(tr('Осталось 348 дней'), '348 days left');
    expect(tr('31,6 ГБ'), '31.6 GB');
    expect(tr('Подписка обновлена: 2 серв.'), 'Subscription updated: 2 servers');
    expect(tr('Нет данных: пустой ответ'), 'No data: empty response');
    expect(tr('Нидерланды'), 'Нидерланды'); // названия серверов не трогаем
    L.apply(AppLang.ru);
    expect(tr('Настройки'), 'Настройки');
  });
}
