import 'dart:convert';

enum PingMethod { real, tcp, httpGet, httpHead, icmp }

enum ServerSort { none, ping, name }

enum IpType { auto, ipv4, ipv6 }

/// Android: какие приложения идут через VPN.
enum SplitMode { all, only, except }

/// Оформление.
enum ThemePref { system, light, dark }

/// Размер текста и кнопки.
enum UiSize { small, normal, large }

/// Как показывать пинг: число, шкала или оба.
enum PingView { time, bars, both }

/// Все настройки приложения. Хранятся одной JSON-строкой.
class AppSettings {
  // ---- Интерфейс ----
  ThemePref theme = ThemePref.system;
  UiSize textSize = UiSize.normal;
  UiSize buttonSize = UiSize.normal;
  bool haptics = true;

  // ---- Соединение ----
  bool autoConnect = false;
  bool launchAtStartup = false;
  bool allowLan = true;
  bool leakProtection = false; // Windows TUN: фильтры WFP против утечек DNS
  bool startMinimized = false; // Windows: при автозапуске — сразу в трей
  SplitMode splitMode = SplitMode.all;
  List<String> splitApps = [];

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

  // ---- Маршрутизация (свои правила) ----
  bool routingEnabled = false;
  String routingName = '';
  List<String> directSites = [];
  List<String> directIps = [];
  List<String> proxySites = [];
  List<String> proxyIps = [];
  List<String> blockSites = [];
  List<String> blockIps = [];

  // ---- Входящие соединения ----
  int socksPort = 10808;
  bool socksAuth = false;
  String socksUser = 'kuduzo';
  String socksPass = '';
  bool httpInbound = true;
  int httpPort = 10809;
  bool mobileLocalProxy = false; // телефон: открыть SOCKS/HTTP для других приложений

  // ---- On Demand (iPhone) ----
  bool onDemand = false;
  bool onDemandWifi = true;
  bool onDemandCellular = true;
  List<String> onDemandExcludedSsids = [];

  // ---- Туннель телефона (Dev Settings) ----
  int memoryLimitMb = 40; // iPhone: мягкий лимит памяти ядра
  bool showMemory = false;
  List<String> excludedRoutes = [];
  List<String> includedRoutes = [];
  bool includeAllNetworks = false;
  bool disconnectOnSleep = false;

  // ---- Провайдеры (подписки) ----
  bool autoUpdate = true;
  int updateIntervalHours = 2;
  bool updateOnLaunch = true;
  bool pingOnLaunch = true;
  bool pingAfterUpdate = true;
  bool sendHwid = true;
  String userAgent = defaultUserAgent;
  ServerSort sort = ServerSort.ping;
  int subTimeoutSec = 12;
  bool notifyUpdates = false;
  bool forbidDuplicates = true;
  bool geoLookup = true; // страна сервера по IP, если её нет в названии
  bool collapseSubs = false;

  // ---- Пинг ----
  PingMethod pingMethod = PingMethod.real;
  String testUrl = testUrls['Google']!;
  int pingTimeoutSec = 3;
  PingView pingView = PingView.time;

  // ---- Статистика ----
  bool statsEnabled = true;

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

  /// Готовые наборы для «Исключённых маршрутов».
  static const routePresets = {
    'Локальные сети': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16'],
    'Apple Push (APNs)': ['17.0.0.0/8'],
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
        'theme': theme.name,
        'textSize': textSize.name,
        'buttonSize': buttonSize.name,
        'haptics': haptics,
        'routingEnabled': routingEnabled,
        'routingName': routingName,
        'directSites': directSites,
        'directIps': directIps,
        'proxySites': proxySites,
        'proxyIps': proxyIps,
        'blockSites': blockSites,
        'blockIps': blockIps,
        'socksPort': socksPort,
        'socksAuth': socksAuth,
        'socksUser': socksUser,
        'socksPass': socksPass,
        'httpInbound': httpInbound,
        'httpPort': httpPort,
        'mobileLocalProxy': mobileLocalProxy,
        'onDemand': onDemand,
        'onDemandWifi': onDemandWifi,
        'onDemandCellular': onDemandCellular,
        'onDemandExcludedSsids': onDemandExcludedSsids,
        'memoryLimitMb': memoryLimitMb,
        'showMemory': showMemory,
        'excludedRoutes': excludedRoutes,
        'includedRoutes': includedRoutes,
        'includeAllNetworks': includeAllNetworks,
        'disconnectOnSleep': disconnectOnSleep,
        'subTimeoutSec': subTimeoutSec,
        'notifyUpdates': notifyUpdates,
        'forbidDuplicates': forbidDuplicates,
        'geoLookup': geoLookup,
        'collapseSubs': collapseSubs,
        'pingView': pingView.name,
        'statsEnabled': statsEnabled,
        'autoConnect': autoConnect,
        'launchAtStartup': launchAtStartup,
        'allowLan': allowLan,
        'leakProtection': leakProtection,
        'startMinimized': startMinimized,
        'splitMode': splitMode.name,
        'splitApps': splitApps,
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
    List<String> l(String k, List<String> d) => j[k] is List ? (j[k] as List).whereType<String>().toList() : d;
    s.theme = _enum(ThemePref.values, j['theme'], s.theme);
    s.textSize = _enum(UiSize.values, j['textSize'], s.textSize);
    s.buttonSize = _enum(UiSize.values, j['buttonSize'], s.buttonSize);
    s.haptics = b('haptics', s.haptics);
    s.routingEnabled = b('routingEnabled', s.routingEnabled);
    s.routingName = j['routingName'] is String ? j['routingName'] as String : s.routingName;
    s.directSites = l('directSites', s.directSites);
    s.directIps = l('directIps', s.directIps);
    s.proxySites = l('proxySites', s.proxySites);
    s.proxyIps = l('proxyIps', s.proxyIps);
    s.blockSites = l('blockSites', s.blockSites);
    s.blockIps = l('blockIps', s.blockIps);
    s.socksPort = i('socksPort', s.socksPort);
    s.socksAuth = b('socksAuth', s.socksAuth);
    s.socksUser = t('socksUser', s.socksUser);
    s.socksPass = j['socksPass'] is String ? j['socksPass'] as String : s.socksPass;
    s.httpInbound = b('httpInbound', s.httpInbound);
    s.httpPort = i('httpPort', s.httpPort);
    s.mobileLocalProxy = b('mobileLocalProxy', s.mobileLocalProxy);
    s.onDemand = b('onDemand', s.onDemand);
    s.onDemandWifi = b('onDemandWifi', s.onDemandWifi);
    s.onDemandCellular = b('onDemandCellular', s.onDemandCellular);
    s.onDemandExcludedSsids = l('onDemandExcludedSsids', s.onDemandExcludedSsids);
    s.memoryLimitMb = i('memoryLimitMb', s.memoryLimitMb);
    s.showMemory = b('showMemory', s.showMemory);
    s.excludedRoutes = l('excludedRoutes', s.excludedRoutes);
    s.includedRoutes = l('includedRoutes', s.includedRoutes);
    s.includeAllNetworks = b('includeAllNetworks', s.includeAllNetworks);
    s.disconnectOnSleep = b('disconnectOnSleep', s.disconnectOnSleep);
    s.subTimeoutSec = i('subTimeoutSec', s.subTimeoutSec);
    s.notifyUpdates = b('notifyUpdates', s.notifyUpdates);
    s.forbidDuplicates = b('forbidDuplicates', s.forbidDuplicates);
    s.geoLookup = b('geoLookup', s.geoLookup);
    s.collapseSubs = b('collapseSubs', s.collapseSubs);
    s.pingView = _enum(PingView.values, j['pingView'], s.pingView);
    s.statsEnabled = b('statsEnabled', s.statsEnabled);
    s.autoConnect = b('autoConnect', s.autoConnect);
    s.launchAtStartup = b('launchAtStartup', s.launchAtStartup);
    s.allowLan = b('allowLan', s.allowLan);
    s.leakProtection = b('leakProtection', s.leakProtection);
    s.startMinimized = b('startMinimized', s.startMinimized);
    s.splitMode = _enum(SplitMode.values, j['splitMode'], s.splitMode);
    if (j['splitApps'] is List) s.splitApps = (j['splitApps'] as List).whereType<String>().toList();
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

  /// Разбивает текст на элементы списка (запятые, пробелы, переводы строк).
  static List<String> splitList(String text) =>
      text.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool get hasCustomRouting =>
      routingEnabled &&
      [directSites, directIps, proxySites, proxyIps, blockSites, blockIps].any((x) => x.isNotEmpty);

  /// Импорт профиля маршрутизации (JSON: DirectSites, DirectIp, ProxySites, ProxyIp, BlockSites, BlockIp, Name).
  /// Понимает и формат Happ. Возвращает false, если это не профиль.
  bool importRouting(Map<String, dynamic> j) {
    List<String>? pick(List<String> keys) {
      for (final k in j.keys) {
        if (keys.contains(k.toLowerCase()) && j[k] is List) {
          return (j[k] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      }
      return null;
    }

    final ds = pick(['directsites', 'direct_sites', 'directdomains']);
    final di = pick(['directip', 'directips', 'direct_ip']);
    final ps = pick(['proxysites', 'proxy_sites', 'proxydomains']);
    final pi = pick(['proxyip', 'proxyips', 'proxy_ip']);
    final bs = pick(['blocksites', 'block_sites', 'blockdomains']);
    final bi = pick(['blockip', 'blockips', 'block_ip']);
    if ([ds, di, ps, pi, bs, bi].every((x) => x == null)) return false;
    directSites = ds ?? [];
    directIps = di ?? [];
    proxySites = ps ?? [];
    proxyIps = pi ?? [];
    blockSites = bs ?? [];
    blockIps = bi ?? [];
    for (final k in j.keys) {
      if (k.toLowerCase() == 'name' && j[k] is String) routingName = j[k] as String;
    }
    return true;
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
