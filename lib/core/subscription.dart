import 'dart:convert';

import 'package:http/http.dart' as http;

import 'link_parser.dart';
import 'platform.dart';
import 'server.dart';

/// Подписка: ссылка, по которой сервер отдаёт список ключей.
class Subscription {
  Subscription({
    required this.id,
    required this.url,
    this.title = '',
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
    this.updatedAt,
    this.links = const [],
    this.supportUrl = '',
    this.webPageUrl = '',
    this.announce = '',
    this.announceUrl = '',
    this.infoText = '',
    this.infoColor = '',
    this.infoButtonText = '',
    this.infoButtonUrl = '',
    this.renewUrl = '',
    this.updateHours = 0,
  });

  final String id;
  final String url;
  String title;
  int upload;
  int download;
  int total;
  DateTime? expire;
  DateTime? updatedAt;

  /// Последний полученный список ключей (кэш на случай, когда сервер подписок недоступен).
  List<String> links;

  /// Ссылки из заголовков подписки: поддержка (support-url) и страница профиля (profile-web-page-url).
  String supportUrl;
  String webPageUrl;

  /// Объявление провайдера (announce) и ссылка по нажатию на него (announce-url).
  String announce;
  String announceUrl;

  /// Информационная плашка провайдера (sub-info-text/-color/-button-text/-button-link, как в Happ).
  String infoText;
  String infoColor;
  String infoButtonText;
  String infoButtonUrl;

  /// Ссылка «Продлить» (sub-expire-button-link) и рекомендуемый интервал обновления в часах.
  String renewUrl;
  int updateHours;

  /// Служебные записи подписки вида «Осталось 30 дней» — ключи-заглушки с адресом 0.0.0.0.
  List<String> get notes => [
        for (final x in LinkParser.parseMany(links.join('\n'), subscriptionId: id))
          if (x.isInfo) x.title,
      ];

  String get displayTitle {
    if (title.isNotEmpty) return title;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? 'Подписка' : host;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'links': links,
        'supportUrl': supportUrl,
        'webPageUrl': webPageUrl,
        'announce': announce,
        'announceUrl': announceUrl,
        'infoText': infoText,
        'infoColor': infoColor,
        'infoButtonText': infoButtonText,
        'infoButtonUrl': infoButtonUrl,
        'renewUrl': renewUrl,
        'updateHours': updateHours,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        url: j['url'] as String,
        title: (j['title'] ?? '') as String,
        upload: (j['upload'] ?? 0) as int,
        download: (j['download'] ?? 0) as int,
        total: (j['total'] ?? 0) as int,
        expire: j['expire'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['expire'] as int),
        updatedAt: j['updatedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
        links: ((j['links'] ?? const []) as List).cast<String>(),
        supportUrl: (j['supportUrl'] ?? '') as String,
        webPageUrl: (j['webPageUrl'] ?? '') as String,
        announce: (j['announce'] ?? '') as String,
        announceUrl: (j['announceUrl'] ?? '') as String,
        infoText: (j['infoText'] ?? '') as String,
        infoColor: (j['infoColor'] ?? '') as String,
        infoButtonText: (j['infoButtonText'] ?? '') as String,
        infoButtonUrl: (j['infoButtonUrl'] ?? '') as String,
        renewUrl: (j['renewUrl'] ?? '') as String,
        updateHours: (j['updateHours'] ?? 0) as int,
      );

  /// Настоящие серверы (без служебных записей-заглушек).
  List<ServerConfig> get servers =>
      LinkParser.parseMany(links.join('\n'), subscriptionId: id).where((x) => !x.isInfo).toList();
}

class SubscriptionException implements Exception {
  SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SubscriptionClient {
  /// Панели подписок отдают список ключей только «знакомым» клиентам —
  /// по заголовку User-Agent. Представляемся так же, как v2rayN.
  static const userAgent = 'v2rayN/7.10.0';

  /// Журнал запросов подписок (раздел «Логи → Подписки»).
  static final List<String> log = [];

  static void _log(Subscription sub, String text) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final host = Uri.tryParse(sub.url)?.host ?? sub.url;
    log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $host — $text');
    if (log.length > 200) log.removeRange(0, log.length - 200);
  }

  static Future<void> refresh(Subscription sub, {String? deviceId, String? agent, int timeoutSec = 20}) async {
    try {
      await _refresh(sub, deviceId: deviceId, agent: agent, timeoutSec: timeoutSec);
      _log(sub, 'обновлена, серверов: ${sub.links.length}');
    } on SubscriptionException catch (e) {
      _log(sub, 'ошибка: ${e.message}');
      rethrow;
    }
  }

  static Future<void> _refresh(Subscription sub, {String? deviceId, String? agent, required int timeoutSec}) async {
    if (Plat.web) {
      throw SubscriptionException('В демо-версии внутри чата подписки не загружаются — проверьте на телефоне или компьютере');
    }
    final http.Response res;
    try {
      res = await http.get(Uri.parse(sub.url), headers: {
        'User-Agent': (agent == null || agent.isEmpty) ? userAgent : agent,
        'Accept': '*/*',
        if (deviceId != null) 'x-hwid': deviceId,
      }).timeout(Duration(seconds: timeoutSec.clamp(3, 60).toInt()));
    } catch (e) {
      throw SubscriptionException('Не удалось загрузить подписку: проверьте интернет');
    }
    if (res.statusCode != 200) {
      throw SubscriptionException('Сервер подписки ответил ошибкой ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<')) {
      throw SubscriptionException('Вместо ключей пришла веб-страница — сервер не узнал приложение');
    }
    final servers = LinkParser.parseMany(body, subscriptionId: sub.id);
    if (servers.isEmpty) {
      throw SubscriptionException('В подписке не найдено ни одного ключа');
    }
    sub.links = servers.map((s) => s.link).toList();
    sub.updatedAt = DateTime.now();
    applyMeta(sub, collectMeta(res.headers, body));
  }

  /// Сведения о подписке из заголовков ответа и из строк «#ключ: значение» в начале тела
  /// (так их передают многие панели). Заголовки важнее строк в теле.
  static Map<String, String> collectMeta(Map<String, String> headers, String body) {
    final meta = <String, String>{};
    headers.forEach((k, v) => meta[k.toLowerCase().trim()] = v);
    var text = body.trim();
    if (!text.contains('://') && !text.startsWith('#')) text = LinkParser.tryBase64(text) ?? text;
    final re = RegExp(r'^\s*(?:#|//)\s*([A-Za-z][A-Za-z0-9_-]*)\s*[:=]\s*(.+?)\s*$');
    for (final line in const LineSplitter().convert(text)) {
      final m = re.firstMatch(line);
      if (m != null) meta.putIfAbsent(m.group(1)!.toLowerCase().replaceAll('_', '-'), () => m.group(2)!);
    }
    return meta;
  }

  /// Текстовое значение: поддерживает «base64:…» и обрезает слишком длинное.
  static String _text(String? v, {int max = 400}) {
    if (v == null) return '';
    var t = v.trim();
    if (t.startsWith('base64:')) t = LinkParser.tryBase64(t.substring(7))?.trim() ?? '';
    return t.length > max ? '${t.substring(0, max)}…' : t;
  }

  static void applyMeta(Subscription sub, Map<String, String> h) {
    final info = h['subscription-userinfo'];
    if (info != null) {
      for (final part in info.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length != 2) continue;
        final v = int.tryParse(kv[1].trim().split('.').first) ?? 0;
        switch (kv[0].trim().toLowerCase()) {
          case 'upload':
            sub.upload = v;
          case 'download':
            sub.download = v;
          case 'total':
            sub.total = v;
          case 'expire':
            sub.expire = v > 0 ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;
        }
      }
    }
    String link(String key, String old) {
      final v = _text(h[key], max: 2000);
      final u = Uri.tryParse(v);
      if (v.isEmpty || u == null) return h.containsKey(key) ? '' : old;
      return const {'https', 'http', 'tg', 'mailto'}.contains(u.scheme) ? v : old;
    }

    String text(String key, String old) => h.containsKey(key) ? _text(h[key]) : old;

    sub.supportUrl = link('support-url', sub.supportUrl);
    sub.webPageUrl = link('profile-web-page-url', sub.webPageUrl);
    sub.announce = text('announce', sub.announce);
    sub.announceUrl = link('announce-url', sub.announceUrl);
    sub.infoText = text('sub-info-text', sub.infoText);
    sub.infoColor = text('sub-info-color', sub.infoColor).toLowerCase();
    sub.infoButtonText = text('sub-info-button-text', sub.infoButtonText);
    sub.infoButtonUrl = link('sub-info-button-link', sub.infoButtonUrl);
    sub.renewUrl = link('sub-expire-button-link', sub.renewUrl);
    final hours = int.tryParse((h['profile-update-interval'] ?? '').trim());
    if (hours != null) sub.updateHours = hours.clamp(0, 168);

    // Название: profile-title, иначе имя файла из content-disposition (так делает v2rayN).
    var title = _text(h['profile-title'], max: 80);
    if (title.isEmpty) {
      final cd = h['content-disposition'] ?? '';
      final m = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(cd) ??
          RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(cd);
      if (m != null) {
        try {
          title = Uri.decodeComponent(m.group(1)!).trim();
        } catch (_) {
          title = m.group(1)!.trim();
        }
      }
    }
    if (title.isNotEmpty) sub.title = title;
  }
}
