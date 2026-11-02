import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';

import '../core/link_parser.dart';
import '../core/ping.dart';
import '../core/platform.dart';
import '../core/server.dart';
import '../core/settings.dart';
import '../core/subscription.dart';
import '../core/vpn_backend.dart';
import '../core/xray_config.dart';

/// Состояние приложения: подписки, серверы, выбранный сервер, подключение.
class AppState extends ChangeNotifier {
  AppState({VpnBackend? backend}) : _backend = backend ?? VpnBackend.create();

  static const autoId = 'auto';

  final VpnBackend _backend;
  late SharedPreferences _prefs;
  StreamSubscription<VpnStatus>? _statusSub;
  Timer? _updateTimer;

  AppSettings settings = AppSettings();

  final List<Subscription> subscriptions = [];
  final List<String> _manualLinks = [];
  List<ServerConfig> servers = [];

  /// Задержка в мс; -1 — не отвечает; отсутствие ключа — ещё не мерили.
  final Map<String, int> pings = {};
  bool pinging = false;

  String selectedId = autoId;
  RoutingMode routing = RoutingMode.smart;

  /// На компьютере: true — весь трафик через TUN (нужны права администратора), false — системный прокси.
  bool desktopTun = false;
  bool tunAvailable = false;

  VpnState state = VpnState.disconnected;
  String message = '';
  DateTime? connectedAt;
  ServerConfig? activeServer;
  String deviceId = '';

  bool get isOn => state == VpnState.connected || state == VpnState.connecting;
  bool get isDesktop => Plat.desktop;

  // ---- Скорость и трафик ----
  Timer? _trafficTimer;
  int speedUp = 0; // байт/с
  int speedDown = 0;
  int totalUp = 0;
  int totalDown = 0;
  bool hasTraffic = false;

  // ---- Обновления программы ----
  String? updateVersion;

  // ---- Сообщения для всплывающих подсказок ----
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;
  void say(String text) => _messages.add(text);

  /// Подписка, срок которой скоро закончится (или уже закончился).
  ({Subscription sub, int days})? get expiring {
    for (final s in subscriptions) {
      final e = s.expire;
      if (e == null) continue;
      final days = e.difference(DateTime.now()).inHours / 24;
      if (days < 3) return (sub: s, days: days.floor());
    }
    return null;
  }

  Future<List<String>> fetchLogs() => _backend.fetchLogs();

  Future<void> checkUpdates() async {
    if (Plat.web) return;
    try {
      final r = await http.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final build = (j['build'] as num?)?.toInt() ?? 0;
      if (build > appBuild) {
        updateVersion = (j['version'] ?? '').toString();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Ссылка kuduzo://… с сайта: добавить подписку или ключ.
  Future<void> handleLink(String link) async {
    final payload = LinkParser.fromAppLink(link);
    if (payload == null) {
      say('Не удалось разобрать ссылку');
      return;
    }
    try {
      say(await addFromText(payload));
    } on SubscriptionException catch (e) {
      say(e.message);
    } catch (e) {
      say('Ошибка: $e');
    }
  }

  void _startTraffic() {
    _trafficTimer?.cancel();
    speedUp = speedDown = totalUp = totalDown = 0;
    hasTraffic = false;
    final period = Plat.desktop ? 2 : 1;
    _trafficTimer = Timer.periodic(Duration(seconds: period), (_) async {
      if (state != VpnState.connected) return;
      final d = await _backend.trafficDelta();
      if (d == null) return;
      hasTraffic = true;
      totalUp += d.up;
      totalDown += d.down;
      speedUp = d.up ~/ period;
      speedDown = d.down ~/ period;
      notifyListeners();
    });
  }

  void _stopTraffic() {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    hasTraffic = false;
    speedUp = speedDown = 0;
  }

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // В песочнице браузера хранилище может быть недоступно — работаем в памяти.
      SharedPreferences.setMockInitialValues({});
      _prefs = await SharedPreferences.getInstance();
    }
    final subsJson = _prefs.getString('subs');
    if (subsJson != null) {
      for (final j in jsonDecode(subsJson) as List) {
        subscriptions.add(Subscription.fromJson(j as Map<String, dynamic>));
      }
    }
    _manualLinks.addAll(_prefs.getStringList('manual') ?? const []);
    selectedId = _prefs.getString('selected') ?? autoId;
    final ri = _prefs.getInt('routing') ?? 0;
    routing = (ri >= 0 && ri < RoutingMode.values.length) ? RoutingMode.values[ri] : RoutingMode.smart;
    desktopTun = _prefs.getBool('desktopTun') ?? false;
    deviceId = _prefs.getString('deviceId') ?? _newDeviceId();
    await _prefs.setString('deviceId', deviceId);
    settings = AppSettings.decode(_prefs.getString('settings'));
    if (Plat.web && subscriptions.isEmpty && _manualLinks.isEmpty) _addDemoData();
    _rebuildServers();

    _statusSub = _backend.status.listen(_onStatus);
    tunAvailable = await _backend.tunAvailable();
    if (!tunAvailable) desktopTun = false;
    notifyListeners();
    _scheduleUpdates();

    unawaited(_onLaunch());
  }

  /// Веб-демо: выдуманные серверы, чтобы было что посмотреть.
  void _addDemoData() {
    const names = ['🇳🇱 Нидерланды', '🇪🇪 Эстония', '🇩🇪 Германия', '🇫🇮 Финляндия', '🇹🇷 Турция'];
    final links = <String>[
      for (var i = 0; i < names.length; i++)
        'vless://00000000-0000-0000-0000-00000000000${i + 1}@203.0.113.${11 + i}:443'
            '?type=xhttp&security=reality&fp=firefox&sni=vpnkuduzo.ru'
            '&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=01&path=/demo#${Uri.encodeComponent(names[i])}',
    ];
    subscriptions.add(Subscription(
      id: 'demo',
      url: 'https://vpnkuduzo.ru/sub/demo',
      title: 'Kuduzo (демо)',
      expire: DateTime(2027, 10, 18),
      updatedAt: DateTime.now(),
      links: links,
    ));
  }

  Future<void> _onLaunch() async {
    unawaited(checkUpdates());
    if (settings.updateOnLaunch && subscriptions.isNotEmpty && !Plat.web) {
      await refreshAll(silent: true, ping: false);
    }
    if (settings.pingOnLaunch) await pingAll();
    if (settings.autoConnect && !isOn && servers.isNotEmpty) await connect();
  }

  void _scheduleUpdates() {
    _updateTimer?.cancel();
    if (!settings.autoUpdate) return;
    final h = settings.updateIntervalHours.clamp(1, 48).toInt();
    _updateTimer = Timer.periodic(Duration(hours: h), (_) => refreshAll(silent: true));
  }

  /// Меняет настройки, сохраняет и применяет. Переподключается, если это влияет на туннель.
  Future<void> updateSettings(void Function(AppSettings s) change, {bool reconnect = false}) async {
    final oldStartup = settings.launchAtStartup;
    final oldMin = settings.startMinimized;
    change(settings);
    await _prefs.setString('settings', settings.encode());
    _scheduleUpdates();
    if (oldStartup != settings.launchAtStartup || oldMin != settings.startMinimized) {
      await _applyStartup(settings.launchAtStartup);
    }
    notifyListeners();
    if (reconnect && isOn) await connect();
  }

  Future<void> _applyStartup(bool on) async {
    if (!Plat.windows) return;
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      if (on) {
        final cmd = '"${Platform.resolvedExecutable}"${settings.startMinimized ? ' --minimized' : ''}';
        await Process.run('reg', ['add', key, '/v', 'Kuduzo', '/t', 'REG_SZ', '/d', cmd, '/f']);
      } else {
        await Process.run('reg', ['delete', key, '/v', 'Kuduzo', '/f']);
      }
    } catch (_) {}
  }

  List<String> get logs => _backend.logs;

  /// Серверы в порядке, выбранном в настройках.
  List<ServerConfig> sorted(List<ServerConfig> list) {
    final l = [...list];
    switch (settings.sort) {
      case ServerSort.none:
        break;
      case ServerSort.name:
        l.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case ServerSort.ping:
        int key(ServerConfig s) {
          final p = pings[s.id];
          if (p == null || p < 0) return 1 << 30;
          return p;
        }
        l.sort((a, b) => key(a).compareTo(key(b)));
    }
    return l;
  }

  String _newDeviceId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _rebuildServers() {
    final list = <ServerConfig>[];
    final seen = <String>{};
    for (final sub in subscriptions) {
      for (final s in sub.servers) {
        if (seen.add(s.id)) list.add(s);
      }
    }
    for (final l in _manualLinks) {
      final s = LinkParser.parse(l);
      if (s != null && seen.add(s.id)) list.add(s);
    }
    servers = list;
    if (selectedId != autoId && !servers.any((s) => s.id == selectedId)) {
      selectedId = autoId;
    }
  }

  Future<void> _save() async {
    await _prefs.setString('subs', jsonEncode(subscriptions.map((s) => s.toJson()).toList()));
    await _prefs.setStringList('manual', _manualLinks);
    await _prefs.setString('selected', selectedId);
    await _prefs.setInt('routing', routing.index);
    await _prefs.setBool('desktopTun', desktopTun);
  }

  // ---------- добавление ----------

  /// Принимает ссылку на подписку, один или несколько ключей, либо base64.
  /// Возвращает текст для пользователя.
  Future<String> addFromText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return 'Пусто — вставьте ссылку';
    if (t.startsWith('http://') || t.startsWith('https://')) {
      final url = t.split(RegExp(r'\s')).first;
      if (subscriptions.any((s) => s.url == url)) return 'Эта подписка уже добавлена';
      final sub = Subscription(id: _newDeviceId().substring(0, 8), url: url);
      await SubscriptionClient.refresh(sub,
          deviceId: settings.sendHwid ? deviceId : null, agent: settings.userAgent); // бросает SubscriptionException
      subscriptions.add(sub);
      _rebuildServers();
      await _save();
      notifyListeners();
      unawaited(pingAll());
      return 'Подписка добавлена: ${sub.servers.length} серв.';
    }
    final parsed = LinkParser.parseMany(t);
    if (parsed.isEmpty) return 'Не похоже на ключ или ссылку подписки';
    var added = 0;
    for (final s in parsed) {
      if (!_manualLinks.contains(s.link)) {
        _manualLinks.add(s.link);
        added++;
      }
    }
    _rebuildServers();
    await _save();
    notifyListeners();
    unawaited(pingAll());
    return added == 0 ? 'Эти ключи уже есть' : 'Добавлено ключей: $added';
  }

  Future<String?> refreshAll({bool silent = false, bool ping = true}) async {
    String? error;
    for (final sub in subscriptions) {
      try {
        await SubscriptionClient.refresh(sub,
            deviceId: settings.sendHwid ? deviceId : null, agent: settings.userAgent);
      } on SubscriptionException catch (e) {
        error = e.message;
      }
    }
    _rebuildServers();
    await _save();
    notifyListeners();
    if (ping && settings.pingAfterUpdate) unawaited(pingAll());
    return error;
  }

  Future<void> removeSubscription(String id) async {
    subscriptions.removeWhere((s) => s.id == id);
    _rebuildServers();
    await _save();
    notifyListeners();
  }

  Future<void> removeServer(ServerConfig s) async {
    _manualLinks.remove(s.link);
    _rebuildServers();
    await _save();
    notifyListeners();
  }

  // ---------- выбор и режимы ----------

  ServerConfig? get selectedServer {
    if (servers.isEmpty) return null;
    if (selectedId != autoId) {
      for (final s in servers) {
        if (s.id == selectedId) return s;
      }
    }
    return bestServer;
  }

  ServerConfig? get bestServer {
    if (servers.isEmpty) return null;
    ServerConfig? best;
    var bestMs = 1 << 30;
    for (final s in servers) {
      final p = pings[s.id];
      if (p != null && p >= 0 && p < bestMs) {
        best = s;
        bestMs = p;
      }
    }
    return best ?? servers.first;
  }

  Future<void> select(String id) async {
    selectedId = id;
    await _save();
    notifyListeners();
    if (isOn) await connect(); // переподключаемся на новый сервер
  }

  Future<void> setRouting(RoutingMode m) async {
    routing = m;
    await _save();
    notifyListeners();
    if (isOn) await connect();
  }

  Future<void> setDesktopTun(bool v) async {
    desktopTun = v && tunAvailable;
    await _save();
    notifyListeners();
    if (isOn) await connect();
  }

  // ---------- подключение ----------

  Future<void> toggle() async {
    if (isOn) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    final s = selectedServer;
    if (s == null) {
      state = VpnState.error;
      message = 'Сначала добавьте подписку или ключ';
      notifyListeners();
      return;
    }
    activeServer = s;
    state = VpnState.connecting;
    message = '';
    notifyListeners();
    try {
      await _backend.start(s, routing, tun: isDesktop ? desktopTun : true, settings: settings);
    } catch (e) {
      state = VpnState.error;
      message = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _backend.stop();
    state = VpnState.disconnected;
    connectedAt = null;
    _stopTraffic();
    notifyListeners();
  }

  void _onStatus(VpnStatus st) {
    final was = state;
    state = st.state;
    message = st.message;
    if (st.state == VpnState.connected) {
      connectedAt ??= DateTime.now();
      if (was != VpnState.connected) _startTraffic();
    } else if (st.state != VpnState.connecting) {
      connectedAt = null;
      _stopTraffic();
    }
    notifyListeners();
  }

  // ---------- пинг ----------

  Future<void> pingAll() async {
    if (pinging || servers.isEmpty) return;
    pinging = true;
    pings.clear();
    notifyListeners();
    try {
      await Pinger.pingAll(servers, settings, onResult: (id, ms) {
        pings[id] = ms;
        notifyListeners();
      });
    } finally {
      pinging = false;
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    if (isOn) await _backend.stop();
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _updateTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
