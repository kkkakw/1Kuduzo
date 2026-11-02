import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/link_parser.dart';
import '../core/server.dart';
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
  bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
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
    _rebuildServers();

    _statusSub = _backend.status.listen(_onStatus);
    tunAvailable = await _backend.tunAvailable();
    if (!tunAvailable) desktopTun = false;
    notifyListeners();

    // Обновляем подписки при запуске и меряем пинг.
    unawaited(refreshAll(silent: true).then((_) => pingAll()));
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
      await SubscriptionClient.refresh(sub, deviceId: deviceId); // бросает SubscriptionException
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

  Future<String?> refreshAll({bool silent = false}) async {
    String? error;
    for (final sub in subscriptions) {
      try {
        await SubscriptionClient.refresh(sub, deviceId: deviceId);
      } on SubscriptionException catch (e) {
        error = e.message;
      }
    }
    _rebuildServers();
    await _save();
    notifyListeners();
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
      await _backend.start(s, routing, tun: isDesktop ? desktopTun : true);
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
    notifyListeners();
  }

  void _onStatus(VpnStatus st) {
    state = st.state;
    message = st.message;
    if (st.state == VpnState.connected) {
      connectedAt ??= DateTime.now();
    } else if (st.state != VpnState.connecting) {
      connectedAt = null;
    }
    notifyListeners();
  }

  // ---------- пинг ----------

  /// TCP-пинг: время установки соединения с сервером.
  static Future<int> tcpPing(ServerConfig s) async {
    if (s.protocol == 'hysteria2') return -2; // UDP — TCP-пингом не измерить
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(s.address, s.port, timeout: const Duration(seconds: 3));
      sw.stop();
      sock.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  Future<void> pingAll() async {
    if (pinging || servers.isEmpty) return;
    pinging = true;
    notifyListeners();
    await Future.wait(servers.map((s) async {
      pings[s.id] = await tcpPing(s);
      notifyListeners();
    }));
    pinging = false;
    notifyListeners();
  }

  Future<void> shutdown() async {
    if (isOn) await _backend.stop();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
