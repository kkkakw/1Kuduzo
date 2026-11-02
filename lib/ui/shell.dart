import 'package:flutter/material.dart';

import '../theme.dart';
import 'home_panel.dart';
import 'servers_panel.dart';
import 'widgets.dart';

/// Телефон: две вкладки. Компьютер (широкое окно): меню слева, тумблер и серверы рядом.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) return _wide(context);
      return _narrow(context);
    });
  }

  Widget _logo() => const Text('Kuduzo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8));

  Widget _narrow(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          child: tab == 0
              ? ListView(children: [
                  SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: _logo())),
                  HomePanel(onOpenServers: () => setState(() => tab = 1)),
                  const SizedBox(height: 24),
                ])
              : const ServersPanel(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: K.surface,
        indicatorColor: K.chip,
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.power_settings_new_rounded), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Серверы'),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(28, 32, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFE7E5E1),
            border: Border(right: BorderSide(color: Color(0xFFDCD9D4))),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _logo(),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 32, 36, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            ]),
          ),
        ),
      ]),
    );
  }
}
