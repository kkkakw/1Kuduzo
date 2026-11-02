import 'dart:convert';

enum PingMethod { real, tcp, httpGet, httpHead, icmp }

enum ServerSort { none, ping, name }

enum IpType { auto, ipv4, ipv6 }

/// Все настройки приложения. Хранятся одной JSON-строкой.
class AppSettings {
  // ---- Соединение ----
  bool autoConnect = false;
  bool launchAtStartup = false;
  bool allowLan = true;
  bool leakProtection = false; // Windows TUN: фильтры WFP против утечек DNS

  // ---- Туннель ----
  bool fragment = false;
  String fragmentPackets = 'tlshello'; // tlshello | 1-3 | 1-5
  String fragmentLength = '50-100';
  String fragmentInterval = '10-20';
  bool noises = false;
  bool mux = false;
  int muxConcurrency = 8;
  IpType ipType = IpType.auto;
  String dns = '1.1.1.1';
  int mtu = 1500;

  // ---- Провайдеры (подписки) ----
  bool autoUpdate = true;
  int updateIntervalHours = 2;
  bool updateOnLaunch = true;
  bool pingOnLaunch = true;
  bool pingAfterUpdate = true;
  bool sendHwid = true;
  String userAgent = defaultUserAgent;
  ServerSort sort = ServerSort.ping;

  // ---- Пинг ----
  PingMethod pingMethod = PingMethod.real;
  String testUrl = testUrls['Google']!;
  int pingTimeoutSec = 3;

  // ---- Производительность ----
  bool sniffing = true;
  bool routeOnly = true;
  int connIdle = 300;
  String logLevel = 'warning'; // none | error | warning | info | debug

  static const defaultUserAgent = 'v2rayN/7.10.0';

  static const testUrls = {
    'Google': 'https://www.gstatic.com/generate_204',
    'Cloudflare': 'https://cp.cloudflare.com/generate_204',
    'Apple': 'https://captive.apple.com/hotspot-detect.html',
  };

  static const dnsPresets = {
    'Cloudflare': '1.1.1.1',
    'Google': '8.8.8.8',
    'Quad9': '9.9.9.9',
    'Cloudflare DoH': 'https://1.1.1.1/dns-query',
  };

  /// Список DNS-серверов для конфига Xray (через запятую или пробел).
  List<String> get dnsServers {
    final list = dns.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? ['1.1.1.1'] : list;
  }

  Map<String, dynamic> toJson() => {
        'autoConnect': autoConnect,
        'launchAtStartup': launchAtStartup,
        'allowLan': allowLan,
        'leakProtection': leakProtection,
        'fragment': fragment,
        'fragmentPackets': fragmentPackets,
        'fragmentLength': fragmentLength,
        'fragmentInterval': fragmentInterval,
        'noises': noises,
        'mux': mux,
        'muxConcurrency': muxConcurrency,
        'ipType': ipType.name,
        'dns': dns,
        'mtu': mtu,
        'autoUpdate': autoUpdate,
        'updateIntervalHours': updateIntervalHours,
        'updateOnLaunch': updateOnLaunch,
        'pingOnLaunch': pingOnLaunch,
        'pingAfterUpdate': pingAfterUpdate,
        'sendHwid': sendHwid,
        'userAgent': userAgent,
        'sort': sort.name,
        'pingMethod': pingMethod.name,
        'testUrl': testUrl,
        'pingTimeoutSec': pingTimeoutSec,
        'sniffing': sniffing,
        'routeOnly': routeOnly,
        'connIdle': connIdle,
        'logLevel': logLevel,
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    int i(String k, int d) => j[k] is int ? j[k] as int : d;
    String t(String k, String d) => j[k] is String && (j[k] as String).isNotEmpty ? j[k] as String : d;
    s.autoConnect = b('autoConnect', s.autoConnect);
    s.launchAtStartup = b('launchAtStartup', s.launchAtStartup);
    s.allowLan = b('allowLan', s.allowLan);
    s.leakProtection = b('leakProtection', s.leakProtection);
    s.fragment = b('fragment', s.fragment);
    s.fragmentPackets = t('fragmentPackets', s.fragmentPackets);
    s.fragmentLength = t('fragmentLength', s.fragmentLength);
    s.fragmentInterval = t('fragmentInterval', s.fragmentInterval);
    s.noises = b('noises', s.noises);
    s.mux = b('mux', s.mux);
    s.muxConcurrency = i('muxConcurrency', s.muxConcurrency);
    s.ipType = _enum(IpType.values, j['ipType'], s.ipType);
    s.dns = t('dns', s.dns);
    s.mtu = i('mtu', s.mtu);
    s.autoUpdate = b('autoUpdate', s.autoUpdate);
    s.updateIntervalHours = i('updateIntervalHours', s.updateIntervalHours);
    s.updateOnLaunch = b('updateOnLaunch', s.updateOnLaunch);
    s.pingOnLaunch = b('pingOnLaunch', s.pingOnLaunch);
    s.pingAfterUpdate = b('pingAfterUpdate', s.pingAfterUpdate);
    s.sendHwid = b('sendHwid', s.sendHwid);
    s.userAgent = t('userAgent', s.userAgent);
    s.sort = _enum(ServerSort.values, j['sort'], s.sort);
    s.pingMethod = _enum(PingMethod.values, j['pingMethod'], s.pingMethod);
    s.testUrl = t('testUrl', s.testUrl);
    s.pingTimeoutSec = i('pingTimeoutSec', s.pingTimeoutSec);
    s.sniffing = b('sniffing', s.sniffing);
    s.routeOnly = b('routeOnly', s.routeOnly);
    s.connIdle = i('connIdle', s.connIdle);
    s.logLevel = t('logLevel', s.logLevel);
    return s;
  }

  String encode() => jsonEncode(toJson());

  static AppSettings decode(String? s) {
    if (s == null || s.isEmpty) return AppSettings();
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }
}
