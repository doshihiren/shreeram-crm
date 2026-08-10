import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ShreeRam Groups brand (logo gold + site green)
  static const brandGreen = Color(0xFF1FA03A);
  static const brandGreenDark = Color(0xFF0E7A2F);
  static const brandGold = Color(0xFFC9A227);
  static const brandGoldDeep = Color(0xFFB08020);
  static const brandBlue = Color(0xFF2391CB);
  static const brandRed = Color(0xFFD62D27);
  static const ink = Color(0xFF1C2430);
  static const muted = Color(0xFF667085);
  static const boardBg = Color(0xFFF4F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const rowHover = Color(0xFFF8FAFC);
  static const line = Color(0xFFE6EAF0);

  // Back-compat aliases used across older screens
  static const forest = brandGreenDark;
  static const forestMid = brandGreen;
  static const brass = brandGold;
  static const limestone = boardBg;
  static const mist = Color(0xFFEEF5EF);
  static const danger = brandRed;

  static ThemeData light() {
    final textTheme = GoogleFonts.manropeTextTheme().copyWith(
      displayLarge: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: ink, fontSize: 40),
      displayMedium: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: ink, fontSize: 32),
      headlineLarge: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: ink, fontSize: 28),
      headlineMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink, fontSize: 22),
      headlineSmall: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink, fontSize: 18),
      titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink, fontSize: 16),
      titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: ink, fontSize: 15),
      bodyLarge: GoogleFonts.manrope(color: ink, fontSize: 15, height: 1.4),
      bodyMedium: GoogleFonts.manrope(color: muted, fontSize: 13, height: 1.4),
      labelLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: boardBg,
      colorScheme: const ColorScheme.light(
        primary: brandGreenDark,
        secondary: brandGold,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: ink,
        onSurface: ink,
        error: brandRed,
      ),
      textTheme: textTheme,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: GoogleFonts.manrope(color: muted, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.manrope(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: brandGreen, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreenDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandGreenDark,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mist,
        selectedColor: brandGreen.withValues(alpha: 0.14),
        labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static Color stageColor(String code) {
    switch (code) {
      case 'NEW_LEAD':
        return brandBlue;
      case 'CONTACTED':
        return const Color(0xFF7C5CFC);
      case 'INTERESTED':
        return brandGreen;
      case 'SITE_VISIT_PLANNED':
        return brandGoldDeep;
      case 'SITE_VISIT_DONE':
        return const Color(0xFF0F9F8A);
      case 'FOLLOW_UP':
        return const Color(0xFFEF7D3B);
      case 'NEGOTIATION':
        return const Color(0xFF2F6FED);
      case 'BOOKED':
        return brandGreenDark;
      case 'CLOSED':
        return const Color(0xFF475467);
      case 'LOST':
        return brandRed;
      default:
        return muted;
    }
  }
}
