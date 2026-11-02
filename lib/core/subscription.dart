import 'dart:convert';

import 'package:http/http.dart' as http;

import 'link_parser.dart';
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
      );

  List<ServerConfig> get servers => LinkParser.parseMany(links.join('\n'), subscriptionId: id);
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

  static Future<void> refresh(Subscription sub, {String? deviceId, String? agent}) async {
    final http.Response res;
    try {
      res = await http.get(Uri.parse(sub.url), headers: {
        'User-Agent': (agent == null || agent.isEmpty) ? userAgent : agent,
        'Accept': '*/*',
        if (deviceId != null) 'x-hwid': deviceId,
      }).timeout(const Duration(seconds: 20));
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
    _applyHeaders(sub, res.headers);
  }

  static void _applyHeaders(Subscription sub, Map<String, String> h) {
    final info = h['subscription-userinfo'];
    if (info != null) {
      for (final part in info.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length != 2) continue;
        final v = int.tryParse(kv[1].trim()) ?? 0;
        switch (kv[0].trim()) {
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
    final t = h['profile-title'];
    if (t != null && t.isNotEmpty) {
      if (t.startsWith('base64:')) {
        sub.title = LinkParser.tryBase64(t.substring(7)) ?? sub.title;
      } else {
        sub.title = t;
      }
    }
  }
}
