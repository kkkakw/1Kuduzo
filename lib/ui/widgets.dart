import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/settings.dart';
import '../core/vpn_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Доступ к AppState из любого виджета.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Без подписки на изменения (для обработчиков нажатий).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Лёгкая вибрация при нажатии (если включена в настройках).
void haptic(BuildContext context, {bool strong = false}) {
  final s = AppScope.read(context);
  if (!s.settings.haptics) return;
  if (strong) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.selectionClick();
  }
}

const kFast = Duration(milliseconds: 220);
const kMedium = Duration(milliseconds: 380);

// ============================================================================
// Тумблер
// ============================================================================

/// Большой объёмный тумблер, как на сайте: плавный ход, «пружина», пульс при подключении.
class KToggle extends StatefulWidget {
  const KToggle({super.key, required this.on, required this.busy, required this.onTap, this.width = 320});

  final bool on;
  final bool busy;
  final VoidCallback onTap;
  final double width;

  @override
  State<KToggle> createState() => _KToggleState();
}

class _KToggleState extends State<KToggle> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant KToggle old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.busy && _pulse.isAnimating) {
      _pulse.animateTo(0, duration: kFast);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final on = widget.on;
    final h = width * 0.425;
    final inset = h * 0.118;
    final knob = h * 0.62;
    final knobTop = (h - knob) / 2;
    final knobLeftOff = inset + h * 0.06;
    final knobLeftOn = width - knobLeftOff - knob;
    final dark = K.isDark;

    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Выключить VPN' : 'Включить VPN',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          haptic(context, strong: true);
          widget.onTap();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.965 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: Container(
              width: width,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h / 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [Color(0xFF38383B), Color(0xFF1E1E20)]
                      : const [Color(0xFF3B3B3B), Color(0xFF1D1D1D)],
                ),
                border: dark ? Border.all(color: const Color(0x14FFFFFF)) : null,
                boxShadow: dark
                    ? const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))]
                    : const [
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
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final glow = on ? (widget.busy ? 0.14 + 0.22 * _pulse.value : 0.40) : 0.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(h),
                          color: const Color(0xFF151515),
                          gradient: RadialGradient(
                            center: const Alignment(0.45, 0),
                            radius: 1.1,
                            colors: [K.accent.withValues(alpha: glow), const Color(0xFF151515)],
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0xBF000000), blurRadius: 16, offset: Offset(0, 8), spreadRadius: -4),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  top: knobTop,
                  left: on ? knobLeftOn : knobLeftOff,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => Transform.scale(
                      scale: widget.busy ? 1 - 0.05 * _pulse.value : 1,
                      child: child,
                    ),
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
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Кнопки, карточки, переключатели
// ============================================================================

/// Уменьшается при нажатии — ощущение «живой» кнопки.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Кнопка цвета ink с радужной обводкой.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon = Icons.add});

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        haptic(context);
        onPressed();
      },
      child: Container(
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
        child: Container(
          decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(28)),
          padding: const EdgeInsets.only(left: 24, right: 6),
          child: Row(children: [
            Expanded(
              child: Text(label, style: TextStyle(color: K.onInk, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: K.isDark ? const Color(0xFFD9D7D2) : const Color(0xFF2D2D2D),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: K.onInk, size: 22),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Сегментированный переключатель с плавно скользящей «таблеткой».
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChanged});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((e) => e.$1 == value).clamp(0, items.length - 1);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(22)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return SizedBox(
          height: 44,
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  color: K.ink,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
                ),
              ),
            ),
            Row(children: [
              for (final (v, label) in items)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (v == value) return;
                      haptic(context);
                      onChanged(v);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: kFast,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: v == value ? K.onInk : K.text2,
                        ),
                        child: Text(label, textAlign: TextAlign.center, maxLines: 2),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        );
      }),
    );
  }
}

/// Карточка на светлой (или тёмной) подложке.
class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(6), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: K.surface,
        borderRadius: BorderRadius.circular(24),
        border: K.isDark ? Border.all(color: K.line) : null,
        boxShadow: K.isDark ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return Pressable(
      onTap: () {
        haptic(context);
        onTap!();
      },
      scale: 0.98,
      child: card,
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
  Widget build(BuildContext context) => AnimatedContainer(
        duration: kFast,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? K.ink : K.chip,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? K.onInk : K.ink)),
      );
}

/// Пинг: числом, шкалой или обоими способами (настройка «Способ отображения»).
class PingIndicator extends StatelessWidget {
  const PingIndicator({super.key, required this.ms, required this.view});
  final int? ms;
  final PingView view;

  int get _bars {
    final m = ms;
    if (m == null || m < 0) return 0;
    if (m < 120) return 4;
    if (m < 250) return 3;
    if (m < 500) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final color = ms == -2 ? K.muted : K.pingColor(ms);
    final text = Text(
      pingLabel(ms),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final bars = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: kMedium,
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(left: 2),
            width: 4,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              color: i < _bars ? color : K.radioOff.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
    final child = switch (view) {
      PingView.time => text,
      PingView.bars => ms == null || ms == -2 ? text : bars,
      PingView.both => Row(mainAxisSize: MainAxisSize.min, children: [bars, const SizedBox(width: 6), text]),
    };
    return AnimatedSwitcher(
      duration: kFast,
      child: KeyedSubtree(key: ValueKey('${ms}_${view.name}'), child: child),
    );
  }
}

/// Плавное появление со сдвигом (для элементов списков).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 14});
  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 35 * widget.index.clamp(0, 10));
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, widget.offset * (1 - _a.value)), child: child),
        ),
        child: widget.child,
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
      return 'VPN включён';
    case VpnState.connecting:
      return 'Подключаемся…';
    case VpnState.error:
      return s.message.isEmpty ? 'Ошибка подключения' : s.message;
    case VpnState.disconnected:
      return 'VPN выключен';
  }
}

/// 1536 → «1,5 КБ».
String fmtBytes(int b) {
  if (b < 1024) return '$b Б';
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${units[i]}';
}

String fmtSpeed(int bytesPerSec) => '${fmtBytes(bytesPerSec)}/с';

Future<void> openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Плашка-уведомление (обновление, срок подписки).
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.text, this.action, this.onAction, this.warn = false});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final bg = warn ? (K.isDark ? const Color(0xFF3A2219) : const Color(0xFFF6E3DA)) : K.chip;
    final fg = warn ? (K.isDark ? const Color(0xFFF0B9A0) : const Color(0xFF7A3A1E)) : K.text2;
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: K.ink),
              child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}

/// Круглая кнопка с иконкой (обновить, назад, меню).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.spinning = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: spinning || onTap == null
          ? null
          : () {
              haptic(context);
              onTap!();
            },
      scale: 0.9,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: K.chip, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: kFast,
          child: spinning
              ? Padding(
                  key: const ValueKey('spin'),
                  padding: const EdgeInsets.all(13),
                  child: CircularProgressIndicator(strokeWidth: 2, color: K.ink),
                )
              : Icon(icon, key: const ValueKey('icon'), size: 20, color: K.ink),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
