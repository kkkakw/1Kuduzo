import 'package:flutter/material.dart';

/// Цвета в стиле сайта vpnkuduzo.ru.
class K {
  static const bg = Color(0xFFEFEEEB);
  static const surface = Color(0xFFF7F6F4);
  static const chip = Color(0xFFE4E2DE);
  static const line = Color(0xFFE0DDD8);
  static const ink = Color(0xFF141414);
  static const text2 = Color(0xFF55514D);
  static const muted = Color(0xFF6B6762);
  static const headlineGray = Color(0xFF85817C);
  static const accent = Color(0xFFC4734F);
  static const good = Color(0xFF2A7A52);
  static const warn = Color(0xFF8A5A12);
  static const bad = Color(0xFFA23B2A);

  static const borderGradient = LinearGradient(colors: [
    Color(0xFF6F8DFF),
    Color(0xFFB27CFF),
    Color(0xFFFF7B5C),
    Color(0xFFFFB46A),
  ]);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        surface: surface,
        primary: ink,
        onPrimary: Colors.white,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
      ),
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
