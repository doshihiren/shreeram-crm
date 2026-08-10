import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Real-estate editorial: deep forest + limestone + brass (not purple / not terracotta cream)
  static const forest = Color(0xFF0F3D2E);
  static const forestMid = Color(0xFF1B5C44);
  static const limestone = Color(0xFFF6F3EC);
  static const mist = Color(0xFFE4EBE6);
  static const brass = Color(0xFFB08D57);
  static const ink = Color(0xFF14201B);
  static const muted = Color(0xFF5E6F67);
  static const danger = Color(0xFF9B2C2C);
  static const surface = Color(0xFFFFFCF7);

  static ThemeData light() {
    final textTheme = GoogleFonts.manropeTextTheme().copyWith(
      displayLarge: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: ink, fontSize: 44),
      displayMedium: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: ink, fontSize: 36),
      headlineLarge: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: ink, fontSize: 30),
      headlineMedium: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: ink, fontSize: 24),
      headlineSmall: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: ink, fontSize: 20),
      titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink, fontSize: 18),
      titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: ink, fontSize: 16),
      bodyLarge: GoogleFonts.manrope(color: ink, fontSize: 16, height: 1.45),
      bodyMedium: GoogleFonts.manrope(color: muted, fontSize: 14, height: 1.45),
      labelLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: limestone,
      colorScheme: const ColorScheme.light(
        primary: forest,
        secondary: brass,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: ink,
        onSurface: ink,
        error: danger,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.88),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: forest.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: forest.withValues(alpha: 0.12)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: forestMid, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: forest,
          side: BorderSide(color: forest.withValues(alpha: 0.25)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mist,
        selectedColor: forest.withValues(alpha: 0.12),
        labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: ink),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
