import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ping.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/subscription.dart';
import '../../core/vpn_backend.dart';
import '../../theme.dart';
import '../../version.dart';
import '../apps_screen.dart';
import '../widgets.dart';
import 'kit.dart';
import 'sysinfo.dart';

// ============================================================================
// Корень раздела «Настройки»
// ============================================================================

class SettingsRoot extends StatelessWidget {
  const SettingsRoot({super.key, this.showTitle = true});
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.settings;
    String onOff(bool v) => v ? 'Вкл.' : 'Выкл.';

    final groups = <Widget>[
      SGroup(title: 'Интерфейс', children: [
        SChoice<ThemePref>(
          title: 'Тема оформления',
          value: st.theme,
          options: const [(ThemePref.system, 'Как в системе'), (ThemePref.light, 'Светлая'), (ThemePref.dark, 'Тёмная')],
          onChanged: (v) => setS(context, (x) => x.theme = v),
        ),
        SChoice<UiSize>(
          title: 'Размер текста',
          value: st.textSize,
          options: [for (final v in UiSize.values) (v, sizeLabel(v))],
          onChanged: (v) => setS(context, (x) => x.textSize = v),
        ),
        SChoice<UiSize>(
          title: 'Размер кнопки',
          value: st.buttonSize,
          options: [for (final v in UiSize.values) (v, sizeLabel(v))],
          onChanged: (v) => setS(context, (x) => x.buttonSize = v),
        ),
        if (Plat.mobile)
          SSwitch(
            title: 'Вибрация при нажатии',
            value: st.haptics,
            onChanged: (v) => setS(context, (x) => x.haptics = v),
          ),
      ]),
      SGroup(title: 'Туннель', children: [
        SNav(
          title: 'Маршрутизация',
          value: st.routingEnabled ? (st.routingName.isEmpty ? 'Вкл.' : st.routingName) : 'Выкл.',
          onTap: () => pushPage(context, const RoutingPage()),
        ),
        SNav(title: 'Фрагментирование', value: onOff(st.fragment), onTap: () => pushPage(context, const FragmentPage())),
        SNav(title: 'Мультиплексирование (Mux)', value: onOff(st.mux), onTap: () => pushPage(context, const MuxPage())),
        SChoice<IpType>(
          title: 'Предпочитаемый тип IP',
          value: st.ipType,
          options: const [(IpType.ipv4, 'IPv4'), (IpType.ipv6, 'IPv6'), (IpType.auto, 'IPv6 и IPv4')],
          onChanged: (v) => setS(context, (x) => x.ipType = v, reconnect: true),
        ),
        SNav(title: 'DNS', value: st.dns, onTap: () => pushPage(context, const DnsPage())),
        SNav(title: 'Входящие соединения', onTap: () => pushPage(context, const InboundPage())),
        if (Plat.ios) SNav(title: 'On Demand', value: onOff(st.onDemand), onTap: () => pushPage(context, const OnDemandPage())),
        if (Plat.android)
          SNav(
            title: 'Приложения через VPN',
            value: switch (st.splitMode) {
              SplitMode.all => 'Все',
              SplitMode.only => 'Только выбранные',
              SplitMode.except => 'Кроме выбранных',
            },
            onTap: () => pushPage(context, const SplitPage()),
          ),
      ]),
      SGroup(title: 'Соединение', children: [
        SSwitch(
          title: 'Подключать при запуске',
          value: st.autoConnect,
          onChanged: (v) => setS(context, (x) => x.autoConnect = v),
        ),
        if (Plat.windows)
          SSwitch(
            title: 'Запускать вместе с Windows',
            value: st.launchAtStartup,
            onChanged: (v) => setS(context, (x) => x.launchAtStartup = v),
          ),
        if (Plat.windows && st.launchAtStartup)
          SSwitch(
            title: 'Запускать свёрнутым в трей',
            value: st.startMinimized,
            onChanged: (v) => setS(context, (x) => x.startMinimized = v),
          ),
        if (Plat.windows)
          SSwitch(
            title: 'Защита от утечек DNS',
            subtitle: 'Режим TUN: запросы DNS других программ не уйдут мимо VPN',
            value: st.leakProtection,
            onChanged: (v) => setS(context, (x) => x.leakProtection = v, reconnect: true),
          ),
        SSwitch(
          title: 'Разрешить LAN подключения',
          subtitle: 'Роутер, принтер и устройства дома — напрямую, мимо VPN',
          value: st.allowLan,
          onChanged: (v) => setS(context, (x) => x.allowLan = v, reconnect: true),
        ),
      ]),
      SGroup(title: 'Расширенные настройки', children: [
        SNav(title: 'Dev Settings', onTap: () => pushPage(context, const DevPage())),
        SNav(title: 'Подписки', onTap: () => pushPage(context, const SubsPage())),
        SNav(title: 'Пинг', value: SettingsLabels.method(Pinger.effective(st.pingMethod)), onTap: () => pushPage(context, const PingPage())),
      ]),
      SGroup(title: 'Другие настройки', children: [
        SNav(title: 'Статистика', value: onOff(st.statsEnabled), onTap: () => pushPage(context, const StatsPage())),
        SNav(title: 'Логи', onTap: () => pushPage(context, const LogsMenuPage())),
        SNav(title: 'Сброс', danger: true, onTap: () => pushPage(context, const ResetPage())),
      ]),
      SGroup(title: 'Подробнее', children: [
        SNav(title: 'FAQ', onTap: () => pushPage(context, const FaqPage())),
        SNav(title: 'Схемы URL-адресов', onTap: () => pushPage(context, const UrlSchemesPage())),
        SNav(title: 'О приложении', value: appVersion, onTap: () => pushPage(context, const AboutPage())),
      ]),
    ];

    return ListView(
      padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (showTitle)
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 4, 6, 18),
            child: Text('Настройки', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.9)),
          ),
        for (var i = 0; i < groups.length; i++) FadeSlideIn(index: i, child: groups[i]),
      ],
    );
  }
}

class SettingsLabels {
  static String method(PingMethod m) => switch (m) {
        PingMethod.real => 'Реальная задержка',
        PingMethod.tcp => 'TCP',
        PingMethod.httpGet => 'Через прокси (GET)',
        PingMethod.httpHead => 'Через прокси (HEAD)',
        PingMethod.icmp => 'ICMP',
      };

  static String methodDesc(PingMethod m) => switch (m) {
        PingMethod.real => 'Запрос через сервер, показывает время одного обмена — привычное низкое число',
        PingMethod.tcp => 'Прямое TCP-соединение с сервером — быстро, но VPN не проверяет',
        PingMethod.httpGet => 'HTTP GET к тестовому адресу через сервер, с установкой соединения',
        PingMethod.httpHead => 'То же, но запрос HEAD — без тела ответа',
        PingMethod.icmp => 'Системный ping до сервера (часть серверов не отвечает)',
      };
}

// ============================================================================
// Туннель
// ============================================================================

class RoutingPage extends StatelessWidget {
  const RoutingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    Widget list(String title, List<String> items, String hint, void Function(AppSettings, List<String>) save) => SNav(
          title: title,
          value: items.isEmpty ? 'нет' : '${items.length}',
          onTap: () => pushPage(
            context,
            ListEditPage(
              title: title,
              items: items,
              hint: hint,
              footer: _routingHelp,
              onSave: (v) => setS(context, (x) => save(x, v), reconnect: true),
            ),
          ),
        );

    return SettingsPage(title: 'Маршрутизация', children: [
      SGroup(
        footer: 'Свои правила работают поверх режима на главном экране. Порядок: «Блокировать» → «Через VPN» → «Напрямую».',
        children: [
          SSwitch(
            title: 'Использовать свои правила',
            value: st.routingEnabled,
            onChanged: (v) => setS(context, (x) => x.routingEnabled = v, reconnect: true),
          ),
          SText(
            title: 'Название профиля',
            value: st.routingName,
            hint: 'Например: Мой профиль',
            compact: true,
            onChanged: (v) => setS(context, (x) => x.routingName = v.trim()),
          ),
        ],
      ),
      SGroup(title: 'Напрямую (Direct)', children: [
        list('Сайты напрямую', st.directSites, 'example.ru\ngeosite:category-ru', (x, v) => x.directSites = v),
        list('IP напрямую', st.directIps, '192.168.0.0/16\ngeoip:ru', (x, v) => x.directIps = v),
      ]),
      SGroup(title: 'Через VPN (Proxy)', children: [
        list('Сайты через VPN', st.proxySites, 'youtube.com\ninstagram.com', (x, v) => x.proxySites = v),
        list('IP через VPN', st.proxyIps, '8.8.8.8/32', (x, v) => x.proxyIps = v),
      ]),
      SGroup(title: 'Блокировать (Block)', children: [
        list('Сайты блокировать', st.blockSites, 'ads.example.com\ngeosite:category-ads-all', (x, v) => x.blockSites = v),
        list('IP блокировать', st.blockIps, '1.2.3.4/32', (x, v) => x.blockIps = v),
      ]),
      SGroup(
        footer: 'Профиль можно добавить ссылкой kuduzo://routing/add/… или скопировать JSON/base64 и импортировать отсюда. Понимает и профили Happ.',
        children: [
          SAction(
            title: 'Импортировать из буфера обмена',
            icon: Icons.content_paste_rounded,
            onTap: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              final text = d?.text?.trim() ?? '';
              if (!context.mounted) return;
              if (text.isEmpty) {
                toast(context, 'Буфер обмена пуст');
                return;
              }
              final payload = text.contains('routing/') ? text.substring(text.indexOf('routing/') + 8).replaceFirst(RegExp(r'^(on)?add/'), '') : text;
              final msg = await AppScope.read(context).importRouting(payload, enable: true);
              if (context.mounted) toast(context, msg);
            },
          ),
          SAction(
            title: 'Скопировать профиль',
            icon: Icons.ios_share_rounded,
            onTap: () async {
              final j = {
                'Name': st.routingName,
                'DirectSites': st.directSites,
                'DirectIp': st.directIps,
                'ProxySites': st.proxySites,
                'ProxyIp': st.proxyIps,
                'BlockSites': st.blockSites,
                'BlockIp': st.blockIps,
              };
              final link = 'kuduzo://routing/onadd/${base64Url.encode(utf8.encode(jsonEncode(j)))}';
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) toast(context, 'Ссылка на профиль скопирована');
            },
          ),
        ],
      ),
    ]);
  }

  static const _routingHelp = 'Сайт: example.com (вместе с поддоменами), full:точный.домен, keyword:слово, '
      'geosite:категория. IP: адрес, подсеть 10.0.0.0/8 или geoip:код страны. '
      'На iPhone наборы geosite не используются — не хватает памяти расширения VPN.';
}

class FragmentPage extends StatelessWidget {
  const FragmentPage({super.key});

  static void _range(BuildContext context, String v, void Function(AppSettings, String) apply) {
    final t = v.replaceAll(' ', '');
    if (RegExp(r'^\d+(-\d+)?$').hasMatch(t)) setS(context, (x) => apply(x, t), reconnect: true);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Фрагментирование', children: [
      SGroup(
        footer: 'Обход DPI: первое TLS-сообщение отправляется по частям. Помогает, если провайдер режет соединение с сервером.',
        children: [
          SSwitch(
            title: 'Использовать фрагментирование',
            value: st.fragment,
            onChanged: (v) => setS(context, (x) => x.fragment = v, reconnect: true),
          ),
        ],
      ),
      AnimatedSize(
        duration: kMedium,
        curve: Curves.easeOutCubic,
        child: st.fragment
            ? SGroup(title: 'Параметры', children: [
                SChoice<String>(
                  title: 'Packets',
                  value: st.fragmentPackets,
                  options: const [('tlshello', 'tlshello'), ('1-3', '1-3'), ('1-5', '1-5')],
                  onChanged: (v) => setS(context, (x) => x.fragmentPackets = v, reconnect: true),
                ),
                SText(
                  title: 'Length',
                  value: st.fragmentLength,
                  compact: true,
                  onChanged: (v) => _range(context, v, (x, r) => x.fragmentLength = r),
                ),
                SText(
                  title: 'Interval',
                  value: st.fragmentInterval,
                  compact: true,
                  onChanged: (v) => _range(context, v, (x, r) => x.fragmentInterval = r),
                ),
              ])
            : const SizedBox(width: double.infinity),
      ),
      SGroup(
        footer: 'Перед данными отправляются случайные UDP-пакеты. Иногда помогает для Hysteria2 и QUIC.',
        children: [
          SSwitch(
            title: 'Noises',
            value: st.noises,
            onChanged: (v) => setS(context, (x) => x.noises = v, reconnect: true),
          ),
        ],
      ),
    ]);
  }
}

class MuxPage extends StatelessWidget {
  const MuxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Mux', children: [
      SGroup(
        footer: 'Объединяет много соединений в один канал. Не используется с XHTTP, Vision и Hysteria2 — для них включается автоматически выключенным.',
        children: [
          SSwitch(
            title: 'Использовать Mux',
            value: st.mux,
            onChanged: (v) => setS(context, (x) => x.mux = v, reconnect: true),
          ),
          if (st.mux)
            SStepper(
              title: 'Потоков в канале',
              value: st.muxConcurrency,
              min: 1,
              max: 32,
              onChanged: (v) => setS(context, (x) => x.muxConcurrency = v, reconnect: true),
            ),
        ],
      ),
    ]);
  }
}

class DnsPage extends StatelessWidget {
  const DnsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'DNS', children: [
      SGroup(title: 'Готовые', children: [
        SChips(
          items: AppSettings.dnsPresets.keys.toList(),
          selected: (k) => st.dns == AppSettings.dnsPresets[k],
          onTap: (k) => setS(context, (x) => x.dns = AppSettings.dnsPresets[k]!, reconnect: true),
        ),
      ]),
      SGroup(
        footer: 'Несколько серверов — через запятую. Поддерживается DNS-over-HTTPS (https://…). Для системного туннеля используется первый IP-адрес.',
        children: [
          SText(
            title: 'Свой DNS',
            value: st.dns,
            hint: '1.1.1.1, 8.8.8.8',
            onChanged: (v) => setS(context, (x) => x.dns = v.trim().isEmpty ? '1.1.1.1' : v.trim(), reconnect: true),
          ),
        ],
      ),
    ]);
  }
}

class InboundPage extends StatelessWidget {
  const InboundPage({super.key});

  static void _port(BuildContext context, String v, void Function(AppSettings, int) apply) {
    final p = int.tryParse(v.trim());
    if (p != null && p >= 1024 && p <= 65535) setS(context, (x) => apply(x, p), reconnect: true);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Входящие соединения', children: [
      if (Plat.mobile)
        SGroup(
          footer: 'Другие приложения на телефоне смогут подключаться к Kuduzo как к прокси 127.0.0.1.',
          children: [
            SSwitch(
              title: 'Открыть локальный прокси',
              value: st.mobileLocalProxy,
              onChanged: (v) => setS(context, (x) => x.mobileLocalProxy = v, reconnect: true),
            ),
          ],
        ),
      SGroup(
        title: 'SOCKS5',
        footer: st.socksAuth
            ? 'Вход по логину и паролю на порту ${st.socksPort}.'
            : 'Без авторизации, на порту ${st.socksPort}.',
        children: [
          SText(title: 'Порт', value: '${st.socksPort}', compact: true, number: true, onChanged: (v) => _port(context, v, (x, p) => x.socksPort = p)),
          SChoice<bool>(
            title: 'Режим авторизации',
            value: st.socksAuth,
            options: const [(false, 'Отключено'), (true, 'Логин и пароль')],
            onChanged: (v) => setS(context, (x) => x.socksAuth = v, reconnect: true),
          ),
          if (st.socksAuth) ...[
            SText(title: 'Логин', value: st.socksUser, compact: true, onChanged: (v) => setS(context, (x) => x.socksUser = v.trim(), reconnect: true)),
            SText(title: 'Пароль', value: st.socksPass, compact: true, obscure: true, onChanged: (v) => setS(context, (x) => x.socksPass = v, reconnect: true)),
          ],
        ],
      ),
      SGroup(
        title: 'HTTP',
        footer: Plat.desktop ? 'На компьютере HTTP-прокси нужен для режима «Системный прокси» и работает всегда.' : null,
        children: [
          if (!Plat.desktop)
            SSwitch(title: 'HTTP-прокси', value: st.httpInbound, onChanged: (v) => setS(context, (x) => x.httpInbound = v, reconnect: true)),
          SText(title: 'Порт', value: '${st.httpPort}', compact: true, number: true, onChanged: (v) => _port(context, v, (x, p) => x.httpPort = p)),
        ],
      ),
    ]);
  }
}

class OnDemandPage extends StatelessWidget {
  const OnDemandPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'On Demand', children: [
      SGroup(
        footer: 'iPhone сам включает VPN, когда появляется сеть. После ручного выключения правило отключается до следующего включения.',
        children: [
          SSwitch(title: 'Включить On Demand', value: st.onDemand, onChanged: (v) => setS(context, (x) => x.onDemand = v)),
        ],
      ),
      AnimatedSize(
        duration: kMedium,
        curve: Curves.easeOutCubic,
        child: st.onDemand
            ? Column(children: [
                SGroup(title: 'Подключаться', children: [
                  SSwitch(title: 'В сетях Wi‑Fi', value: st.onDemandWifi, onChanged: (v) => setS(context, (x) => x.onDemandWifi = v)),
                  SSwitch(
                      title: 'В мобильной сети', value: st.onDemandCellular, onChanged: (v) => setS(context, (x) => x.onDemandCellular = v)),
                ]),
                SGroup(
                  footer: 'В этих Wi‑Fi сетях (например, дома) VPN будет выключаться.',
                  children: [
                    SNav(
                      title: 'Исключённые Wi‑Fi сети',
                      value: st.onDemandExcludedSsids.isEmpty ? 'нет' : '${st.onDemandExcludedSsids.length}',
                      onTap: () => pushPage(
                        context,
                        ListEditPage(
                          title: 'Исключённые Wi‑Fi',
                          items: st.onDemandExcludedSsids,
                          hint: 'Название сети (SSID)',
                          onSave: (v) => setS(context, (x) => x.onDemandExcludedSsids = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ])
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

class SplitPage extends StatelessWidget {
  const SplitPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Приложения', children: [
      SGroup(children: [
        for (final m in SplitMode.values)
          SRadio(
            title: switch (m) {
              SplitMode.all => 'Все приложения через VPN',
              SplitMode.only => 'Только выбранные',
              SplitMode.except => 'Все, кроме выбранных',
            },
            selected: st.splitMode == m,
            onTap: () => setS(context, (x) => x.splitMode = m, reconnect: true),
          ),
      ]),
      if (st.splitMode != SplitMode.all)
        SGroup(children: [
          SNav(title: 'Выбрать приложения', value: '${st.splitApps.length}', onTap: () => pushPage(context, const AppsScreen())),
        ]),
    ]);
  }
}

// ============================================================================
// Расширенные
// ============================================================================

class DevPage extends StatefulWidget {
  const DevPage({super.key});

  @override
  State<DevPage> createState() => _DevPageState();
}

class _DevPageState extends State<DevPage> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (Plat.ios) _t = Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.settings;
    return SettingsPage(title: 'Dev Settings', children: [
      SGroup(title: 'Ядро', children: [
        if (Plat.ios)
          SSlider(
            title: 'Лимит памяти Xray',
            subtitle: 'Мягкий лимит памяти ядра. Если соединение часто обрывается — уменьшите',
            value: st.memoryLimitMb.clamp(30, 50).toInt(),
            min: 30,
            max: 50,
            unit: 'МБ',
            onChanged: (v) => setS(context, (x) => x.memoryLimitMb = v, reconnect: true),
          ),
        SStepper(
          title: 'Таймаут простоя',
          subtitle: 'Через сколько секунд закрывать неактивные соединения',
          value: st.connIdle,
          min: 60,
          max: 1800,
          step: 60,
          onChanged: (v) => setS(context, (x) => x.connIdle = v, reconnect: true),
        ),
        SSwitch(
          title: 'Анализ пакетов',
          subtitle: 'Sniffing: определение сайта по трафику, нужно для правил по доменам',
          value: st.sniffing,
          onChanged: (v) => setS(context, (x) => x.sniffing = v, reconnect: true),
        ),
        SSwitch(
          title: 'Сниффинг только для маршрутов',
          subtitle: 'Выключите, если не устанавливаются UDP/QUIC-звонки',
          value: st.routeOnly,
          onChanged: (v) => setS(context, (x) => x.routeOnly = v, reconnect: true),
        ),
        SChoice<String>(
          title: 'Тип логирования',
          value: st.logLevel,
          options: const [('none', 'None'), ('error', 'Error'), ('warning', 'Warning'), ('info', 'Info'), ('debug', 'Debug')],
          onChanged: (v) => setS(context, (x) => x.logLevel = v, reconnect: true),
        ),
      ]),
      if (Plat.ios)
        SGroup(title: 'Память', children: [
          SSwitch(
            title: 'Показывать на главном экране',
            value: st.showMemory,
            onChanged: (v) => setS(context, (x) => x.showMemory = v),
          ),
          SInfo(title: 'Сейчас занято', value: s.memoryBytes == null ? '—' : fmtBytes(s.memoryBytes!)),
        ]),
      if (!Plat.web)
        SGroup(
          title: 'Маршруты туннеля',
          footer: 'Исключённые — идут мимо VPN. Включённые — только они идут через VPN (пусто — весь трафик).',
          children: [
            SNav(
              title: 'Исключённые маршруты',
              value: st.excludedRoutes.isEmpty ? 'нет' : '${st.excludedRoutes.length}',
              onTap: () => pushPage(
                context,
                ListEditPage(
                  title: 'Исключённые маршруты',
                  items: st.excludedRoutes,
                  hint: '17.0.0.0/8\n192.168.1.0/24',
                  presets: AppSettings.routePresets,
                  footer: Plat.android ? 'На Android исключение маршрутов работает с версии 13.' : null,
                  onSave: (v) => setS(context, (x) => x.excludedRoutes = v, reconnect: true),
                ),
              ),
            ),
            SNav(
              title: 'Включённые маршруты',
              value: st.includedRoutes.isEmpty ? 'все' : '${st.includedRoutes.length}',
              onTap: () => pushPage(
                context,
                ListEditPage(
                  title: 'Включённые маршруты',
                  items: st.includedRoutes,
                  hint: '0.0.0.0/0',
                  onSave: (v) => setS(context, (x) => x.includedRoutes = v, reconnect: true),
                ),
              ),
            ),
            SStepper(
              title: 'MTU туннеля',
              subtitle: 'Меняйте только при подвисаниях: 1420, затем 1380, затем 1280',
              value: st.mtu,
              min: 1200,
              max: 1500,
              step: 20,
              onChanged: (v) => setS(context, (x) => x.mtu = v, reconnect: true),
            ),
          ],
        ),
      if (Plat.ios)
        SGroup(
          footer: '«Включить все сети» — весь трафик устройства, даже системный, только через VPN. '
              '«Отключение в спящем режиме» продлевает работу батареи.',
          children: [
            SSwitch(
              title: 'Включить все сети',
              value: st.includeAllNetworks,
              onChanged: (v) => setS(context, (x) => x.includeAllNetworks = v, reconnect: true),
            ),
            SSwitch(
              title: 'Отключение при переходе в спящий режим',
              value: st.disconnectOnSleep,
              onChanged: (v) => setS(context, (x) => x.disconnectOnSleep = v, reconnect: true),
            ),
          ],
        ),
      SGroup(children: [
        SNav(title: 'Информация о системе', onTap: () => pushPage(context, const SystemInfoPage())),
      ]),
    ]);
  }
}

class SubsPage extends StatelessWidget {
  const SubsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Подписки', children: [
      SGroup(
        title: 'Обновление',
        footer: 'Подписки обновляются в фоне, пока программа открыта.',
        children: [
          SSwitch(title: 'Автообновления', value: st.autoUpdate, onChanged: (v) => setS(context, (x) => x.autoUpdate = v)),
          if (st.autoUpdate)
            SStepper(
              title: 'Интервал обновлений',
              value: st.updateIntervalHours,
              unit: 'ч',
              min: 1,
              max: 24,
              onChanged: (v) => setS(context, (x) => x.updateIntervalHours = v),
            ),
          SSwitch(title: 'Уведомлять об обновлении', value: st.notifyUpdates, onChanged: (v) => setS(context, (x) => x.notifyUpdates = v)),
        ],
      ),
      SGroup(children: [
        SSlider(
          title: 'Тайм-аут запроса подписки',
          value: st.subTimeoutSec.clamp(5, 30).toInt(),
          min: 5,
          max: 30,
          unit: 'сек',
          onChanged: (v) => setS(context, (x) => x.subTimeoutSec = v),
        ),
      ]),
      SGroup(
        footer: 'Выполняется при каждом запуске программы.',
        children: [
          SSwitch(title: 'Обновить при открытии', value: st.updateOnLaunch, onChanged: (v) => setS(context, (x) => x.updateOnLaunch = v)),
          SSwitch(title: 'Пинг при запуске', value: st.pingOnLaunch, onChanged: (v) => setS(context, (x) => x.pingOnLaunch = v)),
          SSwitch(title: 'Пинг после обновления', value: st.pingAfterUpdate, onChanged: (v) => setS(context, (x) => x.pingAfterUpdate = v)),
          SSwitch(title: 'Подключать при запуске', value: st.autoConnect, onChanged: (v) => setS(context, (x) => x.autoConnect = v)),
        ],
      ),
      SGroup(
        footer: 'Сервер подписки получит версию программы и ID устройства (HWID) — без личных данных. Нужно для лимита устройств.',
        children: [
          SSwitch(title: 'Отправлять HWID', value: st.sendHwid, onChanged: (v) => setS(context, (x) => x.sendHwid = v)),
          SText(
            title: 'User-Agent',
            value: st.userAgent,
            hint: AppSettings.defaultUserAgent,
            onChanged: (v) => setS(context, (x) => x.userAgent = v.trim().isEmpty ? AppSettings.defaultUserAgent : v.trim()),
          ),
        ],
      ),
      SGroup(title: 'Список серверов', children: [
        SRadio(title: 'Без сортировки', selected: st.sort == ServerSort.none, onTap: () => setS(context, (x) => x.sort = ServerSort.none)),
        SRadio(title: 'Сортировать по пингу', selected: st.sort == ServerSort.ping, onTap: () => setS(context, (x) => x.sort = ServerSort.ping)),
        SRadio(title: 'Сортировать по алфавиту', selected: st.sort == ServerSort.name, onTap: () => setS(context, (x) => x.sort = ServerSort.name)),
      ]),
      SGroup(
        footer: 'Флаг страны берётся из названия сервера (🇳🇱, «Нидерланды», «DE-2»). Если страны в названии нет, '
            'приложение один раз узнаёт её по IP-адресу сервера через сервисы country.is и ipwho.is.',
        children: [
          SSwitch(title: 'Определять страну по IP', value: st.geoLookup, onChanged: (v) => setS(context, (x) => x.geoLookup = v)),
        ],
      ),
      SGroup(
        footer: 'При добавлении той же ссылки существующая подписка обновится, а не появится второй раз.',
        children: [
          SSwitch(title: 'Запретить дубликаты', value: st.forbidDuplicates, onChanged: (v) => setS(context, (x) => x.forbidDuplicates = v)),
        ],
      ),
      SGroup(
        footer: 'Нажатие на название подписки в списке серверов будет сворачивать её.',
        children: [
          SSwitch(title: 'Сворачивание подписок', value: st.collapseSubs, onChanged: (v) => setS(context, (x) => x.collapseSubs = v)),
        ],
      ),
    ]);
  }
}

class PingPage extends StatelessWidget {
  const PingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.settings;
    final effective = Pinger.effective(st.pingMethod);
    return SettingsPage(title: 'Пинг', children: [
      SGroup(
        title: 'Протоколы пинга',
        footer: Plat.ios
            ? 'При включённом VPN замер делает само расширение VPN напрямую, мимо туннеля, поэтому числа честные.'
            : null,
        children: [
        for (final m in Pinger.available)
          SRadio(
            title: SettingsLabels.method(m) + (m == PingMethod.real ? ' (рекомендуется)' : ''),
            subtitle: SettingsLabels.methodDesc(m),
            selected: effective == m,
            onTap: () => setS(context, (x) => x.pingMethod = m),
          ),
        ],
      ),
      SGroup(title: 'Таймаут', children: [
        SSlider(
          title: 'Таймаут прокси-пинга',
          value: st.pingTimeoutSec.clamp(1, 15).toInt(),
          min: 1,
          max: 15,
          unit: 'сек',
          onChanged: (v) => setS(context, (x) => x.pingTimeoutSec = v),
        ),
      ]),
      SGroup(title: 'Настройки URL-теста', children: [
        SText(title: 'Тестовый адрес', value: st.testUrl, onChanged: (v) => setS(context, (x) => x.testUrl = v.trim())),
        SChips(
          items: AppSettings.testUrls.keys.toList(),
          selected: (k) => st.testUrl == AppSettings.testUrls[k],
          onTap: (k) => setS(context, (x) => x.testUrl = AppSettings.testUrls[k]!),
        ),
      ]),
      SGroup(
        title: 'Интерфейс',
        footer: 'Как показывать результат: число в мс, шкала или оба варианта.',
        children: [
          SChoice<PingView>(
            title: 'Способ отображения',
            value: st.pingView,
            options: const [(PingView.time, 'Время'), (PingView.bars, 'Шкала'), (PingView.both, 'Оба')],
            onChanged: (v) => setS(context, (x) => x.pingView = v),
          ),
        ],
      ),
      SGroup(children: [
        SAction(
          title: s.pinging ? 'Замеряем…' : 'Проверить пинг сейчас',
          icon: Icons.speed_rounded,
          busy: s.pinging,
          onTap: s.pingAll,
        ),
      ]),
    ]);
  }
}

// ============================================================================
// Другие
// ============================================================================

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.settings;
    return SettingsPage(title: 'Статистика', children: [
      SGroup(
        footer: 'Скорость и трафик на главном экране. Включение статистики может немного увеличить расход батареи.',
        children: [
          SSwitch(title: 'Включить статистику', value: st.statsEnabled, onChanged: (v) => setS(context, (x) => x.statsEnabled = v, reconnect: true)),
        ],
      ),
      if (st.statsEnabled)
        SGroup(title: 'Текущий сеанс', children: [
          SInfo(title: 'Отправлено', value: fmtBytes(s.totalUp)),
          SInfo(title: 'Получено', value: fmtBytes(s.totalDown)),
          SInfo(title: 'Скорость', value: '↓ ${fmtSpeed(s.speedDown)}   ↑ ${fmtSpeed(s.speedUp)}'),
        ]),
    ]);
  }
}

class LogsMenuPage extends StatelessWidget {
  const LogsMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context).settings;
    return SettingsPage(title: 'Логи', children: [
      SGroup(
        footer: 'Тип логирования ядра Xray. Установите Error для снижения нагрузки на процессор.',
        children: [
          SChoice<String>(
            title: 'Тип логирования',
            value: st.logLevel,
            options: const [('none', 'None'), ('error', 'Error'), ('warning', 'Warning'), ('info', 'Info'), ('debug', 'Debug')],
            onChanged: (v) => setS(context, (x) => x.logLevel = v, reconnect: true),
          ),
        ],
      ),
      SGroup(children: [
        SNav(title: 'Tunnel', subtitle: 'Сообщения ядра Xray', onTap: () => pushPage(context, const LogViewPage(core: true))),
        SNav(
          title: 'Подписки',
          subtitle: 'Обновления и ошибки подписок',
          value: '${SubscriptionClient.log.length}',
          onTap: () => pushPage(context, const LogViewPage(core: false)),
        ),
      ]),
    ]);
  }
}

class LogViewPage extends StatefulWidget {
  const LogViewPage({super.key, required this.core});
  final bool core;

  @override
  State<LogViewPage> createState() => _LogViewPageState();
}

class _LogViewPageState extends State<LogViewPage> {
  List<String> lines = const [];
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  Future<void> _tick() async {
    while (_alive && mounted) {
      final l = widget.core ? await AppScope.read(context).fetchLogs() : List<String>.of(SubscriptionClient.log);
      if (!mounted) return;
      setState(() => lines = l);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: widget.core ? 'Tunnel' : 'Подписки',
      action: IconButton(
        tooltip: 'Копировать',
        icon: Icon(Icons.copy_rounded, color: K.ink),
        onPressed: lines.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                if (context.mounted) toast(context, 'Журнал скопирован');
              },
      ),
      children: [
        SGroup(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: lines.isEmpty
                ? Text('Файлы журнала не найдены',
                    textAlign: TextAlign.center, style: TextStyle(color: K.muted, fontSize: 15, fontWeight: FontWeight.w600))
                : SelectableText(
                    lines.join('\n'),
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: K.text2),
                  ),
          ),
        ]),
      ],
    );
  }
}

class ResetPage extends StatelessWidget {
  const ResetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return SettingsPage(title: 'Сброс', children: [
      SGroup(
        footer: 'Подписки и ключи останутся, все настройки вернутся к значениям по умолчанию.',
        children: [
          SAction(
            title: 'Сбросить настройки',
            icon: Icons.restart_alt_rounded,
            danger: true,
            onTap: () async {
              if (await confirm(context, 'Сбросить настройки?', 'Все настройки вернутся к значениям по умолчанию.', ok: 'Сбросить', danger: true)) {
                await s.resetSettings();
                if (context.mounted) toast(context, 'Настройки сброшены');
              }
            },
          ),
        ],
      ),
      SGroup(
        footer: 'Удалит подписки, ключи и настройки. Отменить нельзя.',
        children: [
          SAction(
            title: 'Удалить всё',
            icon: Icons.delete_forever_rounded,
            danger: true,
            onTap: () async {
              if (await confirm(context, 'Удалить всё?', 'Подписки, ключи и настройки будут удалены.', ok: 'Удалить', danger: true)) {
                await s.resetAll();
                if (context.mounted) toast(context, 'Всё удалено');
              }
            },
          ),
        ],
      ),
    ]);
  }
}

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _items = [
    ('Как подключиться?', 'Откройте «Серверы» → «Добавить подписку или ключ», вставьте ссылку на подписку Kuduzo и нажмите на тумблер на главном экране.'),
    ('Чем отличаются режимы «Зарубежные сайты» и «Весь трафик»?',
        'В первом российские сайты открываются напрямую, а остальные — через VPN. Во втором через VPN идёт всё, кроме локальной сети.'),
    ('Тумблер не включается на iPhone', 'Приложение должно быть подписано с правом Network Extension. При первом включении iPhone спросит «Добавить конфигурацию VPN» — нажмите «Разрешить». Если окна нет — дело в подписи.'),
    ('Какой пинг выбрать?', '«Реальная задержка» показывает время через сам сервер и честнее всего. TCP быстрее, но проверяет только доступность сервера.'),
    ('Сайты открываются медленно или не открываются', 'Попробуйте другой сервер, включите «Фрагментирование» в настройках туннеля или уменьшите MTU в Dev Settings до 1380.'),
    ('Что такое свои правила маршрутизации?', 'Списки сайтов и IP, которые всегда идут напрямую, через VPN или блокируются — поверх выбранного режима.'),
    ('Сбивается подключение на iPhone', 'Уменьшите лимит памяти Xray в Dev Settings: расширению VPN iOS выделяет около 50 МБ.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'FAQ', children: [
      for (final (q, a) in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: K.surface,
              borderRadius: BorderRadius.circular(18),
              border: K.isDark ? Border.all(color: K.line) : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(q, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                iconColor: K.accent,
                collapsedIconColor: K.muted,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedAlignment: Alignment.centerLeft,
                children: [Text(a, style: TextStyle(fontSize: 14, color: K.text2, height: 1.4))],
              ),
            ),
          ),
        ),
    ]);
  }
}

class UrlSchemesPage extends StatelessWidget {
  const UrlSchemesPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget link(String l) => _CopyRow(text: l);
    return SettingsPage(title: 'Схемы URL-адресов', children: [
      SGroup(title: 'Запустить туннель', children: [link('kuduzo://connect'), link('kuduzo://open')]),
      SGroup(title: 'Остановить соединение', children: [link('kuduzo://disconnect'), link('kuduzo://close')]),
      SGroup(title: 'Переключить соединение', children: [link('kuduzo://toggle')]),
      SGroup(
        title: 'Добавить конфигурацию',
        footer: '{url} — ссылка на подписку, ключ vless:// и т.п. или их base64.',
        children: [link('kuduzo://add/{url}'), link('kuduzo://import/{url}')],
      ),
      SGroup(
        title: 'Роутинг',
        footer: '{base64} — профиль маршрутизации в JSON, закодированный base64. onadd — добавить и сразу включить.',
        children: [link('kuduzo://routing/add/{base64}'), link('kuduzo://routing/onadd/{base64}'), link('kuduzo://routing/off')],
      ),
    ]);
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static Future<String?>? _core;
  bool _checking = false;

  /// Версия Xray: на компьютере — у программы xray, на телефоне — у ядра внутри приложения.
  static Future<String?> _coreVersion() async {
    if (Plat.desktop) {
      final v = await DesktopVpnBackend.coreVersion();
      final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(v);
      return m?.group(1) ?? v;
    }
    if (Plat.mobile) return MobileVpnBackend.coreVersion();
    return null;
  }

  static String _short(String url) => url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // Ссылки поддержки из заголовков подписки (support-url, profile-web-page-url).
    final support = s.subscriptions.map((x) => x.supportUrl).firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final webPage = s.subscriptions.map((x) => x.webPageUrl).firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final telegram = supportTelegram.isNotEmpty ? supportTelegram : (support.contains('t.me/') ? support : '');

    return SettingsPage(title: 'О приложении', children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: const Color(0xFF000000), borderRadius: BorderRadius.circular(22)),
            alignment: Alignment.center,
            child: const Text('K', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          const Text('Kuduzo VPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
      ),
      SGroup(title: 'Информация', children: [
        FutureBuilder<String?>(
          future: _core ??= _coreVersion(),
          builder: (_, snap) => SInfo(
            title: 'Версия Xray',
            value: snap.connectionState == ConnectionState.done ? (snap.data ?? 'Xray-core') : '…',
          ),
        ),
        SInfo(title: 'Версия приложения', value: appVersion),
        SInfo(title: 'Сборка', value: '$appBuild'),
        SInfo(title: 'ID устройства', value: s.deviceId, copy: true),
      ]),
      SGroup(title: 'Ссылки', children: [
        SNav(
          title: 'Условия использования',
          onTap: () => pushPage(context, const LegalPage(title: 'Условия использования', asset: 'assets/legal/terms.md')),
        ),
        SNav(
          title: 'Политика конфиденциальности',
          onTap: () =>
              pushPage(context, const LegalPage(title: 'Политика конфиденциальности', asset: 'assets/legal/privacy.md')),
        ),
        SNav(
          title: 'Согласие на обработку данных',
          onTap: () => pushPage(context, const LegalPage(title: 'Согласие', asset: 'assets/legal/consent.md')),
        ),
        SNav(
          title: 'Лицензии сторонних компонентов',
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Kuduzo VPN',
            applicationVersion: '$appVersion ($appBuild)',
          ),
        ),
        _LinkRow(title: 'Сайт', value: 'vpnkuduzo.ru', onTap: () => openUrl('https://vpnkuduzo.ru')),
        if (webPage.isNotEmpty) _LinkRow(title: 'Моя подписка', value: _short(webPage), onTap: () => openUrl(webPage)),
        if (supportEmail.isNotEmpty)
          _LinkRow(title: 'Email', value: supportEmail, onTap: () => openUrl('mailto:$supportEmail')),
        if (telegram.isNotEmpty) _LinkRow(title: 'Поддержка', value: _short(telegram), onTap: () => openUrl(telegram)),
        if (support.isNotEmpty && _short(support) != _short(telegram))
          _LinkRow(title: 'Поддержка подписки', value: _short(support), onTap: () => openUrl(support)),
        if (telegramChannel.isNotEmpty)
          _LinkRow(title: 'Канал', value: _short(telegramChannel), onTap: () => openUrl(telegramChannel)),
      ]),
      SGroup(children: [
        if (s.updateVersion != null)
          SAction(title: 'Скачать версию ${s.updateVersion}', icon: Icons.system_update_rounded, onTap: () => openUrl(releasesPage))
        else if (!Plat.web)
          SAction(
            title: 'Проверить обновления',
            icon: Icons.refresh_rounded,
            busy: _checking,
            onTap: () async {
              setState(() => _checking = true);
              await s.checkUpdates();
              if (!mounted) return;
              setState(() => _checking = false);
              if (context.mounted) toast(context, s.updateVersion == null ? 'У вас последняя версия' : 'Доступна версия ${s.updateVersion}');
            },
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: Text(
          'Kuduzo VPN подключается только к серверам из ваших подписок и ключей. '
          'Подписки, настройки и журналы хранятся на этом устройстве.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: K.muted, height: 1.4),
        ),
      ),
    ]);
  }
}

/// Документ из assets/legal: «# » — заголовок, «## » — раздел, «- » — пункт списка.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.title, required this.asset});
  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: title, children: [
      FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString(asset),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          final blocks = <Widget>[];
          for (final raw in snap.data!.split('\n')) {
            final line = raw.trimRight();
            if (line.isEmpty) continue;
            if (line.startsWith('# ')) {
              blocks.add(Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line.substring(2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
              ));
            } else if (line.startsWith('## ')) {
              blocks.add(Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 6),
                child: Text(line.substring(3), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ));
            } else if (line.startsWith('- ')) {
              blocks.add(Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('•  ', style: TextStyle(fontSize: 15, color: K.accent, height: 1.45)),
                  Expanded(child: Text(line.substring(2), style: TextStyle(fontSize: 15, color: K.text2, height: 1.45))),
                ]),
              ));
            } else {
              blocks.add(Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line, style: TextStyle(fontSize: 15, color: K.text2, height: 1.45)),
              ));
            }
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 24),
            child: SelectionArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks),
            ),
          );
        },
      ),
    ]);
  }
}

/// Строка-ссылка: название слева, адрес цветом акцента справа (как в Happ).
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          haptic(context);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 15, color: K.accent, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
      );
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          haptic(context);
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) toast(context, 'Скопировано: $text');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Icon(Icons.copy_rounded, size: 16, color: K.radioOff),
          ]),
        ),
      );
}
