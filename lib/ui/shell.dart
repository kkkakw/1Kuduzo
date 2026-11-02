import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/platform.dart';
import '../theme.dart';
import 'home_panel.dart';
import 'servers_panel.dart';
import 'settings/pages.dart';
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
    AppScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) return _wide(context);
      return _narrow(context);
    });
  }

  Widget _logo() =>
      const Text('Kuduzo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8));

  /// Плавная смена вкладок: лёгкое затухание и сдвиг.
  Widget _switcher(Widget child, Object key) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(key), child: child),
      );

  Widget _narrow(BuildContext context) {
    final Widget body = switch (tab) {
      0 => ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom), children: [
          SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: _logo())),
          HomePanel(onOpenServers: () => setState(() => tab = 1)),
          const SizedBox(height: 24),
        ]),
      1 => const ServersPanel(),
      _ => const SettingsRoot(),
    };
    return Scaffold(
      backgroundColor: K.bg,
      // Содержимое прокручивается под плавающей панелью вкладок.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (Plat.web)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(14)),
              child: Text(
                'Демо-версия: интерфейс как на телефоне, но VPN внутри чата не подключается',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: K.text2, fontWeight: FontWeight.w500),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _switcher(body, tab),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: _FloatingTabs(
        index: tab,
        onTap: (i) {
          if (i != tab) haptic(context);
          setState(() => tab = i);
        },
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final s = AppScope.of(context);

    final Widget content = switch (page) {
      0 => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      1 => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: const SettingsRoot()),
        ),
      _ => const LogViewPage(core: true),
    };

    return Scaffold(
      backgroundColor: K.bg,
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          decoration: BoxDecoration(
            color: K.sidebar,
            border: Border(right: BorderSide(color: K.line)),
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
                decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sub.displayTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${sub.links.length} серверов', style: TextStyle(fontSize: 12, color: K.muted)),
                ]),
              ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(page == 2 ? 0 : 36, page == 2 ? 0 : 32, page == 2 ? 0 : 36, 0),
            child: _switcher(content, page),
          ),
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
        child: Pressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: kFast,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? K.ink : K.sidebar.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(icon, size: 20, color: selected ? K.onInk : K.navText),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? K.onInk : K.navText,
                  )),
            ]),
          ),
        ),
      );
}

/// Плавающая панель вкладок-капсула: размытие под ней, выбранная вкладка — «пилюля», которая перетекает.
class _FloatingTabs extends StatelessWidget {
  const _FloatingTabs({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.power_settings_new_rounded, 'Главная'),
    (Icons.public_rounded, 'Серверы'),
    (Icons.settings_rounded, 'Настройки'),
  ];
  static const _h = 66.0;
  static const _gap = 5.0;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(_h / 2);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, safe > 0 ? safe - 6 : 14),
      child: Container(
        height: _h,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: K.isDark ? 0.45 : 0.10), blurRadius: 30, offset: const Offset(0, 10)),
            BoxShadow(color: Colors.black.withValues(alpha: K.isDark ? 0.25 : 0.05), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: K.surface.withValues(alpha: K.isDark ? 0.80 : 0.84),
                borderRadius: radius,
                border: Border.all(
                  color: K.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.75),
                ),
              ),
              child: LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - _gap * 2) / _items.length;
                return Stack(children: [
                  // «Пилюля» выбранной вкладки плавно переезжает с лёгким пружинящим доводом.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeOutBack,
                    left: _gap + w * index,
                    top: _gap,
                    bottom: _gap,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: K.isDark ? Colors.white.withValues(alpha: 0.10) : K.chip,
                        borderRadius: BorderRadius.circular(_h / 2 - _gap),
                      ),
                    ),
                  ),
                  Row(children: [
                    const SizedBox(width: _gap),
                    for (var i = 0; i < _items.length; i++)
                      SizedBox(
                        width: w,
                        child: _TabButton(
                          icon: _items[i].$1,
                          label: _items[i].$2,
                          selected: i == index,
                          onTap: () => onTap(i),
                        ),
                      ),
                    const SizedBox(width: _gap),
                  ]),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final color = Color.lerp(K.ink, K.accent, t)!;
              return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Transform.scale(scale: 1 + 0.08 * t, child: Icon(icon, size: 25, color: color)),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1),
                ),
              ]);
            },
          ),
        ),
      );
}
