import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Палитра одной темы.
class KPalette {
  const KPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.chip,
    required this.line,
    required this.ink,
    required this.onInk,
    required this.text2,
    required this.muted,
    required this.headlineGray,
    required this.sidebar,
    required this.selectedRow,
    required this.radioOff,
    required this.dotOff,
    required this.navText,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color chip;
  final Color line;
  final Color ink; // основной текст и «чёрные» кнопки
  final Color onInk; // текст на кнопках цвета ink
  final Color text2;
  final Color muted;
  final Color headlineGray;
  final Color sidebar;
  final Color selectedRow;
  final Color radioOff;
  final Color dotOff;
  final Color navText;
}

/// Цвета в стиле сайта vpnkuduzo.ru. Значения зависят от текущей темы.
class K {
  static const light = KPalette(
    brightness: Brightness.light,
    bg: Color(0xFFEFEEEB),
    surface: Color(0xFFF7F6F4),
    chip: Color(0xFFE4E2DE),
    line: Color(0xFFE0DDD8),
    ink: Color(0xFF141414),
    onInk: Color(0xFFFFFFFF),
    text2: Color(0xFF55514D),
    muted: Color(0xFF6B6762),
    headlineGray: Color(0xFF85817C),
    sidebar: Color(0xFFE7E5E1),
    selectedRow: Color(0xFFEBE9E5),
    radioOff: Color(0xFFB9B4AE),
    dotOff: Color(0xFFA8A39D),
    navText: Color(0xFF3D3A37),
  );

  static const dark = KPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0E0E0F),
    surface: Color(0xFF1A1A1C),
    chip: Color(0xFF2A2A2D),
    line: Color(0xFF2E2E31),
    ink: Color(0xFFF2F1EE),
    onInk: Color(0xFF141414),
    text2: Color(0xFFBDB9B3),
    muted: Color(0xFF8F8B86),
    headlineGray: Color(0xFF77736E),
    sidebar: Color(0xFF151517),
    selectedRow: Color(0xFF242427),
    radioOff: Color(0xFF55524F),
    dotOff: Color(0xFF5C5955),
    navText: Color(0xFFCFCBC5),
  );

  /// Текущая палитра (переключается в KuduzoApp при смене темы).
  static KPalette p = light;

  static bool get isDark => p.brightness == Brightness.dark;

  static Color get bg => p.bg;
  static Color get surface => p.surface;
  static Color get chip => p.chip;
  static Color get line => p.line;
  static Color get ink => p.ink;
  static Color get onInk => p.onInk;
  static Color get text2 => p.text2;
  static Color get muted => p.muted;
  static Color get headlineGray => p.headlineGray;
  static Color get sidebar => p.sidebar;
  static Color get selectedRow => p.selectedRow;
  static Color get radioOff => p.radioOff;
  static Color get dotOff => p.dotOff;
  static Color get navText => p.navText;

  static const accent = Color(0xFFC4734F);
  static const good = Color(0xFF2A9A62);
  static const warn = Color(0xFFB07A1E);
  static const bad = Color(0xFFC0442F);

  static const borderGradient = LinearGradient(colors: [
    Color(0xFF6F8DFF),
    Color(0xFFB27CFF),
    Color(0xFFFF7B5C),
    Color(0xFFFFB46A),
  ]);

  static ThemeData theme(KPalette c) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.ink,
        brightness: c.brightness,
        surface: c.surface,
        primary: c.ink,
        onPrimary: c.onInk,
      ),
      // Плавные переходы между экранами: на iPhone — как в системе (со свайпом назад).
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      }),
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(color: c.onInk, fontFamily: 'Inter'),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: c.line,
    );
  }

  static Color pingColor(int? ms) {
    if (ms == null) return muted;
    if (ms < 0) return bad;
    if (ms < 150) return good;
    if (ms < 300) return warn;
    return bad;
  }
}
