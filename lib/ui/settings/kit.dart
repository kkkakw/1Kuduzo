import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

// Строительные блоки раздела «Настройки» — сгруппированные списки как в iOS.

/// Открыть подстраницу настроек (на iPhone — системный переход со свайпом назад).
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  haptic(context);
  return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
}

/// Обёртка: изменить настройку и при необходимости переподключиться.
Future<void> setS(BuildContext context, void Function(AppSettings s) f, {bool reconnect = false}) =>
    AppScope.read(context).updateSettings(f, reconnect: reconnect);

/// Страница настроек: круглая кнопка «назад», заголовок по центру, прокручиваемый список.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    AppScope.of(context); // перерисовка при изменениях
    return Scaffold(
      backgroundColor: K.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 64,
            child: Row(children: [
              const SizedBox(width: 16),
              RoundIconButton(icon: Icons.chevron_left_rounded, onTap: () => Navigator.of(context).maybePop()),
              Expanded(
                child: Text(title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
              SizedBox(width: 60, child: Center(child: action ?? const SizedBox())),
            ]),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, child: children[i]),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Группа строк с подписью сверху и пояснением снизу.
class SGroup extends StatelessWidget {
  const SGroup({super.key, this.title, required this.children, this.footer});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, indent: 18, endIndent: 18, color: K.line));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(title!.toUpperCase(),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: K.muted, letterSpacing: 0.6)),
          ),
        Container(
          decoration: BoxDecoration(
            color: K.surface,
            borderRadius: BorderRadius.circular(22),
            border: K.isDark ? Border.all(color: K.line) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: Column(children: rows)),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Text(footer!, style: TextStyle(fontSize: 12.5, color: K.muted, height: 1.35)),
          ),
      ]),
    );
  }
}

class _Texts extends StatelessWidget {
  const _Texts({required this.title, this.subtitle, this.danger = false});
  final String title;
  final String? subtitle;
  final bool danger;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: danger ? K.bad : K.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(fontSize: 12.5, color: K.muted, height: 1.3)),
        ],
      ]);
}

/// Строка-переход на подстраницу.
class SNav extends StatelessWidget {
  const SNav({super.key, required this.title, this.subtitle, this.value, this.icon, required this.onTap, this.danger = false});
  final String title;
  final String? subtitle;
  final String? value;
  final IconData? icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          haptic(context);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: danger ? K.bad : K.ink),
              const SizedBox(width: 12),
            ],
            Expanded(child: _Texts(title: title, subtitle: subtitle, danger: danger)),
            if (value != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 15, color: K.muted)),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: K.radioOff),
          ]),
        ),
      );
}

/// Переключатель (на iPhone — системный вид).
class SSwitch extends StatelessWidget {
  const SSwitch({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          haptic(context);
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Expanded(child: _Texts(title: title, subtitle: subtitle)),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              onChanged: (v) {
                haptic(context);
                onChanged(v);
              },
              activeTrackColor: K.accent,
              inactiveTrackColor: K.chip,
              thumbColor: WidgetStateProperty.all(Colors.white),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ]),
        ),
      );
}

/// Выбор одного варианта: текущее значение справа, по нажатию — меню.
class SChoice<T> extends StatelessWidget {
  const SChoice({super.key, required this.title, required this.value, required this.options, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;
    return PopupMenuButton<T>(
      tooltip: title,
      color: K.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.under,
      offset: const Offset(0, -8),
      onOpened: () => haptic(context),
      onSelected: (v) {
        haptic(context);
        onChanged(v);
      },
      itemBuilder: (_) => [
        for (final (v, label) in options)
          PopupMenuItem<T>(
            value: v,
            child: Row(children: [
              SizedBox(width: 26, child: v == value ? const Icon(Icons.check_rounded, color: K.accent, size: 20) : null),
              Text(label, style: TextStyle(color: K.ink)),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(children: [
          Expanded(child: _Texts(title: title, subtitle: subtitle)),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: kFast,
            child: Text(current,
                key: ValueKey(current),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: K.accent)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.unfold_more_rounded, color: K.accent, size: 20),
        ]),
      ),
    );
  }
}

/// Строка-вариант с галочкой (список способов).
class SRadio extends StatelessWidget {
  const SRadio({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          haptic(context);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(children: [
            Expanded(child: _Texts(title: title, subtitle: subtitle)),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: kFast,
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check_rounded, color: K.accent, size: 24),
            ),
          ]),
        ),
      );
}

/// Число с кнопками «−» и «+».
class SStepper extends StatelessWidget {
  const SStepper({
    super.key,
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(children: [
          Expanded(child: _Texts(title: title, subtitle: subtitle)),
          AnimatedSwitcher(
            duration: kFast,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text(unit.isEmpty ? '$value' : '$value $unit',
                key: ValueKey(value), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: K.accent)),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(color: K.chip, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Меньше',
                onPressed: value - step >= min
                    ? () {
                        haptic(context);
                        onChanged(value - step);
                      }
                    : null,
                icon: Icon(Icons.remove_rounded, color: K.ink),
              ),
              Container(width: 1, height: 22, color: K.radioOff),
              IconButton(
                tooltip: 'Больше',
                onPressed: value + step <= max
                    ? () {
                        haptic(context);
                        onChanged(value + step);
                      }
                    : null,
                icon: Icon(Icons.add_rounded, color: K.ink),
              ),
            ]),
          ),
        ]),
      );
}

/// Ползунок со значением.
class SSlider extends StatefulWidget {
  const SSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  State<SSlider> createState() => _SSliderState();
}

class _SSliderState extends State<SSlider> {
  late double _v = widget.value.toDouble();

  @override
  void didUpdateWidget(covariant SSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _Texts(title: widget.title, subtitle: widget.subtitle)),
            Text('${_v.round()}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: K.accent)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: K.accent,
              inactiveTrackColor: K.chip,
              thumbColor: Colors.white,
              overlayColor: K.accent.withValues(alpha: 0.12),
              trackHeight: 5,
            ),
            child: Slider.adaptive(
              value: _v.clamp(widget.min.toDouble(), widget.max.toDouble()),
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.max - widget.min,
              onChanged: (v) {
                if (v.round() != _v.round()) HapticFeedback.selectionClick();
                setState(() => _v = v);
              },
              onChangeEnd: (v) => widget.onChanged(v.round()),
            ),
          ),
          Row(children: [
            Text('${widget.min}', style: TextStyle(fontSize: 12, color: K.muted)),
            const Spacer(),
            Text('${widget.max}', style: TextStyle(fontSize: 12, color: K.muted)),
          ]),
        ]),
      );
}

/// Текстовое поле (сохраняется при уходе с поля или по Enter).
class SText extends StatefulWidget {
  const SText({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
    this.compact = false,
    this.number = false,
    this.obscure = false,
  });
  final String title;
  final String value;
  final String? hint;
  final bool compact;
  final bool number;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  State<SText> createState() => _STextState();
}

class _STextState extends State<SText> {
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
  void didUpdateWidget(covariant SText old) {
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
      obscureText: widget.obscure,
      keyboardType: widget.number ? TextInputType.number : TextInputType.text,
      inputFormatters: widget.number ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(fontSize: 14.5, color: K.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(color: K.muted),
        filled: true,
        fillColor: K.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: widget.compact
          ? Row(children: [
              Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              SizedBox(width: 150, child: field),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              field,
            ]),
    );
  }
}

/// Строка «название — значение» (с копированием по нажатию).
class SInfo extends StatelessWidget {
  const SInfo({super.key, required this.title, required this.value, this.copy = false});
  final String title;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: copy
            ? () async {
                haptic(context);
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) toast(context, 'Скопировано');
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: K.muted)),
            ),
            if (copy) ...[
              const SizedBox(width: 8),
              Icon(Icons.copy_rounded, size: 16, color: K.radioOff),
            ],
          ]),
        ),
      );
}

/// Кнопка-действие во всю ширину группы.
class SAction extends StatelessWidget {
  const SAction({super.key, required this.title, required this.onTap, this.icon, this.danger = false, this.busy = false});
  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: busy
            ? null
            : () {
                haptic(context);
                onTap();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: K.ink))
            else if (icon != null)
              Icon(icon, size: 19, color: danger ? K.bad : K.accent),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: danger ? K.bad : K.accent)),
          ]),
        ),
      );
}

/// Набор «чипсов» (готовые значения).
class SChips extends StatelessWidget {
  const SChips({super.key, required this.items, required this.selected, required this.onTap});
  final List<String> items;
  final bool Function(String) selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in items)
            Pressable(
              onTap: () {
                haptic(context);
                onTap(e);
              },
              child: AnimatedContainer(
                duration: kFast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected(e) ? K.ink : K.chip,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(e,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected(e) ? K.onInk : K.text2)),
              ),
            ),
        ]),
      );
}

/// Редактор списка: одна запись на строку. Сохраняет при выходе.
class ListEditPage extends StatefulWidget {
  const ListEditPage({
    super.key,
    required this.title,
    required this.items,
    required this.onSave,
    this.hint = '',
    this.footer,
    this.presets = const {},
  });
  final String title;
  final List<String> items;
  final ValueChanged<List<String>> onSave;
  final String hint;
  final String? footer;
  final Map<String, List<String>> presets;

  @override
  State<ListEditPage> createState() => _ListEditPageState();
}

class _ListEditPageState extends State<ListEditPage> {
  late final TextEditingController _c = TextEditingController(text: widget.items.join('\n'));

  List<String> get _items => AppSettings.splitList(_c.text);

  @override
  void dispose() {
    widget.onSave(_items);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: widget.title,
      action: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(foregroundColor: K.accent),
        child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      children: [
        if (widget.presets.isNotEmpty)
          SGroup(title: 'Добавить набор', children: [
            SChips(
              items: widget.presets.keys.toList(),
              selected: (k) => widget.presets[k]!.every(_items.contains),
              onTap: (k) {
                final cur = _items;
                final add = widget.presets[k]!.where((x) => !cur.contains(x));
                setState(() => _c.text = [...cur, ...add].join('\n'));
              },
            ),
          ]),
        SGroup(
          title: 'Одна запись на строку',
          footer: widget.footer,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _c,
                minLines: 6,
                maxLines: 16,
                style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: K.ink),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(color: K.muted),
                  filled: true,
                  fillColor: K.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        SGroup(children: [
          SAction(
            title: 'Очистить список',
            icon: Icons.delete_outline_rounded,
            danger: true,
            onTap: () => setState(() => _c.clear()),
          ),
        ]),
      ],
    );
  }
}

/// Подтверждение действия.
Future<bool> confirm(BuildContext context, String title, String text, {String ok = 'Да', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: danger ? K.bad : K.accent),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Название варианта для показа справа в строке.
String sizeLabel(UiSize s) => switch (s) {
      UiSize.small => 'Маленький',
      UiSize.normal => 'Нормальный',
      UiSize.large => 'Большой',
    };

AppState stateOf(BuildContext context) => AppScope.of(context);
