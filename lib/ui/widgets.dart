import 'dart:async';

import 'package:flutter/material.dart';

import '../core/vpn_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Доступ к AppState из любого виджета.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Большой объёмный тумблер, как на сайте.
class KToggle extends StatelessWidget {
  const KToggle({super.key, required this.on, required this.busy, required this.onTap, this.width = 320});

  final bool on;
  final bool busy;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.425;
    final inset = h * 0.118;
    final knob = h * 0.62;
    final knobTop = (h - knob) / 2;
    final knobLeftOff = inset + h * 0.06;
    final knobLeftOn = width - knobLeftOff - knob;

    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Выключить VPN' : 'Включить VPN',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: width,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3B3B3B), Color(0xFF1D1D1D)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x38000000), blurRadius: 44, offset: Offset(0, 22)),
                BoxShadow(color: Color(0x2E000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Stack(children: [
              Positioned.fill(
                left: inset,
                right: inset,
                top: inset,
                bottom: inset,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h),
                    color: const Color(0xFF151515),
                    gradient: on
                        ? RadialGradient(
                            center: const Alignment(0.45, 0),
                            radius: 1.1,
                            colors: [K.accent.withValues(alpha: busy ? 0.18 : 0.38), const Color(0xFF151515)],
                          )
                        : null,
                    boxShadow: const [
                      BoxShadow(color: Color(0xBF000000), blurRadius: 16, offset: Offset(0, 8), spreadRadius: -4),
                    ],
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                top: knobTop,
                left: on ? knobLeftOn : knobLeftOff,
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.32, -0.44),
                      colors: [Color(0xFF6A6A6A), Color(0xFF2B2B2B), Color(0xFF121212)],
                      stops: [0, 0.45, 1],
                    ),
                    boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 10))],
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFBDBDBD)),
                        )
                      : null,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Чёрная кнопка с радужной обводкой.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon = Icons.add});

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: K.borderGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Color(0x2EB27CFF), blurRadius: 26, offset: Offset(-6, 10)),
          BoxShadow(color: Color(0x24FF7B5C), blurRadius: 26, offset: Offset(6, 10)),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: K.ink,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 6),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: Color(0xFF2D2D2D), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Сегментированный переключатель (чёрная «таблетка» на сером фоне).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChanged});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          for (final (v, label) in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: v == value ? K.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => onChanged(v),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: v == value ? Colors.white : K.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Карточка на светлой подложке.
class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(6), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: K.surface,
      borderRadius: BorderRadius.circular(24),
      shadowColor: const Color(0x14000000),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Квадратик с кодом страны.
class Badge2 extends StatelessWidget {
  const Badge2({super.key, required this.text, this.dark = false, this.size = 40});
  final String text;
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? K.ink : K.chip,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? Colors.white : K.ink)),
      );
}

/// Таймер «сколько уже подключены».
class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, required this.since, this.style});
  final DateTime since;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Text(text, style: widget.style);
  }
}

String pingLabel(int? ms) {
  if (ms == null) return '…';
  if (ms == -2) return 'UDP';
  if (ms < 0) return 'нет связи';
  return '$ms мс';
}

/// Подсказка-снэкбар.
void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String statusText(AppState s) {
  switch (s.state) {
    case VpnState.connected:
      return 'VPN включён. Всё открывается.';
    case VpnState.connecting:
      return 'Подключаемся…';
    case VpnState.error:
      return s.message.isEmpty ? 'Ошибка подключения' : s.message;
    case VpnState.disconnected:
      return 'VPN выключен';
  }
}
