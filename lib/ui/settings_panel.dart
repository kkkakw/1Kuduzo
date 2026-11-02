import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ping.dart';
import '../core/settings.dart';
import '../core/vpn_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../version.dart';
import 'widgets.dart';

/// Раздел «Настройки» (как в INCY, в стиле Kuduzo).
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, this.onOpenLogs});

  final VoidCallback? onOpenLogs;

  static Future<String>? _coreVersion;

  static String methodTitle(PingMethod m) => switch (m) {
        PingMethod.real => 'Реальная задержка',
        PingMethod.tcp => 'TCP',
        PingMethod.httpGet => 'HTTP GET',
        PingMethod.httpHead => 'HTTP HEAD',
        PingMethod.icmp => 'ICMP',
      };

  static String methodDesc(PingMethod m) => switch (m) {
        PingMethod.real => 'Запрос к тестовому адресу через сервер, показывает время одного обмена',
        PingMethod.tcp => 'Прямое TCP-соединение с сервером — быстро, но не проверяет VPN',
        PingMethod.httpGet => 'Полный HTTP GET через сервер, включая установку соединения',
        PingMethod.httpHead => 'HTTP HEAD через сервер — то же, но без тела ответа',
        PingMethod.icmp => 'Системный ping до сервера (некоторые серверы не отвечают)',
      };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.settings;
    final win = Platform.isWindows;
    final desktop = s.isDesktop;

    Future<void> set(void Function(AppSettings x) f, {bool reconnect = false}) =>
        s.updateSettings(f, reconnect: reconnect);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16, top: 4),
          child: Text('Настройки', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        ),

        // ---------------- Пинг ----------------
        _Section(title: 'Пинг', icon: Icons.speed_rounded, children: [
          for (final m in Pinger.available)
            _RadioRow(
              title: methodTitle(m) + (m == PingMethod.real ? ' (рекомендуется)' : ''),
              subtitle: methodDesc(m),
              selected: st.pingMethod == m,
              onTap: () => set((x) => x.pingMethod = m),
            ),
          const _Divider(),
          _TextSetting(
            title: 'Тестовый адрес',
            value: st.testUrl,
            onChanged: (v) => set((x) => x.testUrl = v.trim()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in AppSettings.testUrls.entries)
                _Chip(
                  label: e.key,
                  selected: st.testUrl == e.value,
                  onTap: () => set((x) => x.testUrl = e.value),
                ),
            ]),
          ),
          _StepperRow(
            title: 'Таймаут',
            value: st.pingTimeoutSec,
            unit: 'сек',
            min: 1,
            max: 10,
            onChanged: (v) => set((x) => x.pingTimeoutSec = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                  backgroundColor: K.chip, foregroundColor: K.ink, minimumSize: const Size.fromHeight(44)),
              onPressed: s.pinging ? null : s.pingAll,
              icon: s.pinging
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: K.ink))
                  : const Icon(Icons.speed_rounded, size: 18),
              label: Text(s.pinging ? 'Замеряем…' : 'Проверить пинг сейчас'),
            ),
          ),
        ]),

        // ---------------- Провайдеры ----------------
        _Section(title: 'Провайдеры (подписки)', icon: Icons.sync_rounded, children: [
          _SwitchRow(
            title: 'Автообновление',
            subtitle: 'Обновлять подписки автоматически',
            value: st.autoUpdate,
            onChanged: (v) => set((x) => x.autoUpdate = v),
          ),
          if (st.autoUpdate)
            _StepperRow(
              title: 'Интервал',
              value: st.updateIntervalHours,
              unit: 'ч',
              min: 1,
              max: 24,
              onChanged: (v) => set((x) => x.updateIntervalHours = v),
            ),
          _SwitchRow(
            title: 'Обновлять при запуске',
            value: st.updateOnLaunch,
            onChanged: (v) => set((x) => x.updateOnLaunch = v),
          ),
          _SwitchRow(
            title: 'Пинг при запуске',
            value: st.pingOnLaunch,
            onChanged: (v) => set((x) => x.pingOnLaunch = v),
          ),
          _SwitchRow(
            title: 'Пинг после обновления',
            value: st.pingAfterUpdate,
            onChanged: (v) => set((x) => x.pingAfterUpdate = v),
          ),
          _SwitchRow(
            title: 'Отправлять HWID',
            subtitle: 'ID устройства для лимита устройств в подписке',
            value: st.sendHwid,
            onChanged: (v) => set((x) => x.sendHwid = v),
          ),
          _TextSetting(
            title: 'User-Agent',
            value: st.userAgent,
            hint: AppSettings.defaultUserAgent,
            onChanged: (v) => set((x) => x.userAgent = v.trim().isEmpty ? AppSettings.defaultUserAgent : v.trim()),
          ),
          const _Divider(),
          const _Label('Сортировка серверов'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Segmented<ServerSort>(
              items: const [
                (ServerSort.none, 'Без сортировки'),
                (ServerSort.ping, 'По пингу'),
                (ServerSort.name, 'По имени'),
              ],
              value: st.sort,
              onChanged: (v) => set((x) => x.sort = v),
            ),
          ),
        ]),

        // ---------------- Соединение ----------------
        _Section(title: 'Соединение', icon: Icons.wifi_rounded, children: [
          _SwitchRow(
            title: 'Автоподключение',
            subtitle: 'Подключаться при запуске программы',
            value: st.autoConnect,
            onChanged: (v) => set((x) => x.autoConnect = v),
          ),
          if (win)
            _SwitchRow(
              title: 'Запускать вместе с Windows',
              value: st.launchAtStartup,
              onChanged: (v) => set((x) => x.launchAtStartup = v),
            ),
          _SwitchRow(
            title: 'Разрешить локальную сеть',
            subtitle: 'Принтеры, роутер и устройства дома — напрямую, мимо VPN',
            value: st.allowLan,
            onChanged: (v) => set((x) => x.allowLan = v, reconnect: true),
          ),
          if (win)
            _SwitchRow(
              title: 'Защита от утечек DNS',
              subtitle: 'Только в режиме TUN: запросы DNS других программ не уйдут мимо VPN',
              value: st.leakProtection,
              onChanged: (v) => set((x) => x.leakProtection = v, reconnect: true),
            ),
        ]),

        // ---------------- Туннель ----------------
        _Section(title: 'Туннель', icon: Icons.shield_outlined, children: [
          _SwitchRow(
            title: 'Фрагментирование',
            subtitle: 'Обход DPI: TLS-приветствие отправляется по частям',
            value: st.fragment,
            onChanged: (v) => set((x) => x.fragment = v, reconnect: true),
          ),
          if (st.fragment) ...[
            const _Label('Packets'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Segmented<String>(
                items: const [('tlshello', 'tlshello'), ('1-3', '1-3'), ('1-5', '1-5')],
                value: st.fragmentPackets,
                onChanged: (v) => set((x) => x.fragmentPackets = v, reconnect: true),
              ),
            ),
            _TextSetting(
              title: 'Length',
              value: st.fragmentLength,
              compact: true,
              onChanged: (v) => _range(v, (r) => set((x) => x.fragmentLength = r, reconnect: true)),
            ),
            _TextSetting(
              title: 'Interval',
              value: st.fragmentInterval,
              compact: true,
              onChanged: (v) => _range(v, (r) => set((x) => x.fragmentInterval = r, reconnect: true)),
            ),
          ],
          _SwitchRow(
            title: 'Noises',
            subtitle: 'Случайные пакеты перед данными (для UDP/QUIC)',
            value: st.noises,
            onChanged: (v) => set((x) => x.noises = v, reconnect: true),
          ),
          _SwitchRow(
            title: 'Мультиплексирование (Mux)',
            subtitle: 'Объединение соединений в один канал. Не используется с XHTTP и Vision',
            value: st.mux,
            onChanged: (v) => set((x) => x.mux = v, reconnect: true),
          ),
          if (st.mux)
            _StepperRow(
              title: 'Потоков в канале',
              value: st.muxConcurrency,
              min: 1,
              max: 32,
              onChanged: (v) => set((x) => x.muxConcurrency = v, reconnect: true),
            ),
          const _Divider(),
          const _Label('Тип IP'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Segmented<IpType>(
              items: const [(IpType.auto, 'Авто'), (IpType.ipv4, 'IPv4'), (IpType.ipv6, 'IPv6')],
              value: st.ipType,
              onChanged: (v) => set((x) => x.ipType = v, reconnect: true),
            ),
          ),
          const _Label('VPN DNS'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in AppSettings.dnsPresets.entries)
                _Chip(
                  label: e.key,
                  selected: st.dns == e.value,
                  onTap: () => set((x) => x.dns = e.value, reconnect: true),
                ),
            ]),
          ),
          _TextSetting(
            title: 'Свой DNS',
            value: st.dns,
            hint: '1.1.1.1, 8.8.8.8',
            onChanged: (v) => set((x) => x.dns = v.trim().isEmpty ? '1.1.1.1' : v.trim(), reconnect: true),
          ),
          _StepperRow(
            title: 'MTU туннеля',
            subtitle: 'Меняйте только при подвисаниях: 1420, затем 1380, затем 1280',
            value: st.mtu,
            min: 1200,
            max: 1500,
            step: 20,
            onChanged: (v) => set((x) => x.mtu = v, reconnect: true),
          ),
        ]),

        // ---------------- Производительность ----------------
        _Section(title: 'Производительность', icon: Icons.tune_rounded, children: [
          _SwitchRow(
            title: 'Анализ трафика',
            subtitle: 'Sniffing: определение сайта, нужно для режима «Только заблокированное»',
            value: st.sniffing,
            onChanged: (v) => set((x) => x.sniffing = v, reconnect: true),
          ),
          _SwitchRow(
            title: 'Сниффинг только для маршрутов',
            subtitle: 'Домен используется только для выбора маршрута. Выключите, если не работают звонки',
            value: st.routeOnly,
            onChanged: (v) => set((x) => x.routeOnly = v, reconnect: true),
          ),
          _StepperRow(
            title: 'Таймаут простоя',
            subtitle: 'Через сколько секунд закрывать неактивные соединения',
            value: st.connIdle,
            min: 60,
            max: 1800,
            step: 60,
            onChanged: (v) => set((x) => x.connIdle = v, reconnect: true),
          ),
        ]),

        // ---------------- Отладка ----------------
        _Section(title: 'Отладка', icon: Icons.bug_report_outlined, children: [
          const _Label('Подробность журнала'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Segmented<String>(
              items: const [('error', 'Ошибки'), ('warning', 'Обычный'), ('info', 'Подробный'), ('debug', 'Всё')],
              value: st.logLevel,
              onChanged: (v) => set((x) => x.logLevel = v, reconnect: true),
            ),
          ),
          if (desktop && onOpenLogs != null)
            _NavRow(title: 'Журнал ядра', icon: Icons.receipt_long_rounded, onTap: onOpenLogs!),
          _NavRow(
            title: 'Скопировать ID устройства',
            icon: Icons.copy_rounded,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: s.deviceId));
              if (context.mounted) toast(context, 'ID устройства скопирован');
            },
          ),
        ]),

        // ---------------- О программе ----------------
        _Section(title: 'О программе', icon: Icons.info_outline_rounded, children: [
          const _InfoRow(title: 'Kuduzo', value: 'версия $appVersion'),
          if (desktop)
            FutureBuilder<String>(
              future: _coreVersion ??= DesktopVpnBackend.coreVersion(),
              builder: (_, snap) => _InfoRow(title: 'Ядро', value: snap.data ?? '…'),
            )
          else
            const _InfoRow(title: 'Ядро', value: 'Xray-core'),
        ]),
      ],
    );
  }

  /// Принимаем «50-100» или «20».
  static void _range(String v, void Function(String) apply) {
    final t = v.replaceAll(' ', '');
    if (RegExp(r'^\d+(-\d+)?$').hasMatch(t)) apply(t);
  }
}

// ===================== строительные блоки =====================

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Row(children: [
              Icon(icon, size: 18, color: K.muted),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: K.text2)),
            ]),
          ),
          KCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
        ]),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(child: _Texts(title: title, subtitle: subtitle)),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: K.ink,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: K.chip,
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ]),
        ),
      );
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({required this.title, required this.selected, required this.onTap, this.subtitle});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(child: _Texts(title: title, subtitle: subtitle)),
            const SizedBox(width: 12),
            Icon(selected ? Icons.check_rounded : null, color: K.accent, size: 24),
          ]),
        ),
      );
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(child: _Texts(title: title, subtitle: subtitle)),
          Text(unit.isEmpty ? '$value' : '$value $unit',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: K.accent)),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Меньше',
                onPressed: value - step >= min ? () => onChanged(value - step) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Container(width: 1, height: 22, color: const Color(0xFFCFCBC5)),
              IconButton(
                tooltip: 'Больше',
                onPressed: value + step <= max ? () => onChanged(value + step) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
          ),
        ]),
      );
}

class _TextSetting extends StatefulWidget {
  const _TextSetting({
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
    this.compact = false,
  });
  final String title;
  final String value;
  final String? hint;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _c.text != widget.value) widget.onChanged(_c.text);
    });
  }

  @override
  void didUpdateWidget(covariant _TextSetting old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      focusNode: _focus,
      onSubmitted: widget.onChanged,
      style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        filled: true,
        fillColor: K.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: widget.compact
          ? Row(children: [
              Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              SizedBox(width: 160, child: field),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              field,
            ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? K.ink : K.chip,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : K.text2)),
          ),
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.icon, required this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20, color: K.ink),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right_rounded, color: K.muted),
          ]),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: K.muted)),
          ),
        ]),
      );
}

class _Texts extends StatelessWidget {
  const _Texts({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: K.muted, height: 1.3)),
        ],
      ]);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 12, thickness: 1, indent: 16, endIndent: 16, color: K.line);
}

/// Журнал ядра (Windows/macOS).
class LogsPanel extends StatefulWidget {
  const LogsPanel({super.key});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState s = AppScope.of(context);
    final lines = s.logs;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 4),
        child: Row(children: [
          const Expanded(
            child: Text('Журнал ядра', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
          ),
          TextButton.icon(
            onPressed: lines.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    if (context.mounted) toast(context, 'Журнал скопирован');
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Копировать'),
            style: TextButton.styleFrom(foregroundColor: K.ink),
          ),
        ]),
      ),
      Expanded(
        child: KCard(
          padding: const EdgeInsets.all(16),
          child: lines.isEmpty
              ? const Center(
                  child: Text('Пока пусто — включите VPN, и здесь появятся сообщения ядра Xray',
                      textAlign: TextAlign.center, style: TextStyle(color: K.muted)))
              : SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    lines.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: K.text2),
                  ),
                ),
        ),
      ),
    ]);
  }
}
