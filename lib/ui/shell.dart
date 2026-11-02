import 'package:flutter/material.dart';

import '../core/platform.dart';
import '../theme.dart';
import 'home_panel.dart';
import 'servers_panel.dart';
import 'settings_panel.dart';
import 'widgets.dart';

/// Телефон: вкладки внизу. Компьютер (широкое окно): меню слева.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0; // телефон: 0 главная, 1 серверы, 2 настройки
  int page = 0; // компьютер: 0 главная, 1 настройки, 2 журнал

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) return _wide(context);
      return _narrow(context);
    });
  }

  Widget _logo() =>
      const Text('Kuduzo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8));

  Widget _narrow(BuildContext context) {
    Widget body;
    switch (tab) {
      case 0:
        body = ListView(children: [
          SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: _logo())),
          HomePanel(onOpenServers: () => setState(() => tab = 1)),
          const SizedBox(height: 24),
        ]);
      case 1:
        body = const ServersPanel();
      default:
        body = SettingsPanel(
          onOpenLogs: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(backgroundColor: K.bg, surfaceTintColor: Colors.transparent),
              body: const SafeArea(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: LogsPanel()),
              ),
            ),
          )),
        );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (Plat.web)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(14)),
              child: const Text(
                'Демо-версия: интерфейс как на Android, но VPN внутри чата не подключается',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: K.text2, fontWeight: FontWeight.w500),
              ),
            ),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 0), child: body)),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: K.surface,
        indicatorColor: K.chip,
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.power_settings_new_rounded), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Серверы'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Настройки'),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final s = AppScope.of(context);

    Widget content;
    switch (page) {
      case 0:
        content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: KCard(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 36),
                child: HomePanel(onOpenServers: () {}, wide: true),
              ),
            ),
          ),
          const SizedBox(width: 28),
          const Expanded(flex: 2, child: ServersPanel()),
        ]);
      case 1:
        content = Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SettingsPanel(onOpenLogs: () => setState(() => page = 2)),
          ),
        );
      default:
        content = const Padding(padding: EdgeInsets.only(bottom: 28), child: LogsPanel());
    }

    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFE7E5E1),
            border: Border(right: BorderSide(color: Color(0xFFDCD9D4))),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(left: 8, bottom: 24), child: _logo()),
            _NavItem(icon: Icons.power_settings_new_rounded, label: 'Главная', selected: page == 0, onTap: () => setState(() => page = 0)),
            _NavItem(icon: Icons.settings_rounded, label: 'Настройки', selected: page == 1, onTap: () => setState(() => page = 1)),
            _NavItem(icon: Icons.receipt_long_rounded, label: 'Журнал', selected: page == 2, onTap: () => setState(() => page = 2)),
            const Spacer(),
            for (final sub in s.subscriptions)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF2F1EE), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sub.displayTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${sub.links.length} серверов', style: const TextStyle(fontSize: 12, color: K.muted)),
                ]),
              ),
          ]),
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.fromLTRB(36, 32, 36, 0), child: content),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? K.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(icon, size: 20, color: selected ? Colors.white : const Color(0xFF3D3A37)),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Colors.white : const Color(0xFF3D3A37),
                    )),
              ]),
            ),
          ),
        ),
      );
}
