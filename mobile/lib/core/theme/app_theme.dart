import 'package:flutter/material.dart';

class AppTheme {
  static const forest = Color(0xFF1F4D3A);
  static const sand = Color(0xFFF3EFE6);
  static const clay = Color(0xFFC45C26);
  static const ink = Color(0xFF1A1A1A);
  static const mist = Color(0xFFE7EDE8);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        secondary: clay,
        surface: sand,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: sand,
      fontFamily: 'Georgia',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
