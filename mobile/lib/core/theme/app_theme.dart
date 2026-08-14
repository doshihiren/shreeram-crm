import 'package:flutter/material.dart';

class AppTheme {
  // ShreeRam Developer logo: deep forest/teal green + metallic gold
  static const brandGreen = Color(0xFF1A6B4A);
  static const brandGreenDark = Color(0xFF0C3D32);
  static const brandGreenDeep = Color(0xFF072821);
  static const brandGold = Color(0xFFD4AF37);
  static const brandGoldDeep = Color(0xFFB0891E);
  static const brandGoldSoft = Color(0xFFF3E4B2);
  static const brandBlue = Color(0xFF2391CB);
  static const brandRed = Color(0xFFC62828);
  static const ink = Color(0xFF122018);
  static const muted = Color(0xFF5C6B62);
  static const boardBg = Color(0xFFF3F7F4);
  static const surface = Color(0xFFFFFFFF);
  static const rowHover = Color(0xFFF7FBF8);
  static const line = Color(0xFFD9E5DC);

  static const forest = brandGreenDark;
  static const forestMid = brandGreen;
  static const brass = brandGold;
  static const limestone = boardBg;
  static const mist = Color(0xFFE7F3EA);
  static const danger = brandRed;

  static const String fontFamily = 'Manrope';

  static TextStyle _text({
    FontWeight fontWeight = FontWeight.w400,
    double? fontSize,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
    );
    final textTheme = base.textTheme.copyWith(
      displayLarge: _text(fontWeight: FontWeight.w800, color: ink, fontSize: 40),
      displayMedium: _text(fontWeight: FontWeight.w800, color: ink, fontSize: 32),
      headlineLarge: _text(fontWeight: FontWeight.w800, color: ink, fontSize: 28),
      headlineMedium: _text(fontWeight: FontWeight.w700, color: ink, fontSize: 22),
      headlineSmall: _text(fontWeight: FontWeight.w700, color: ink, fontSize: 18),
      titleLarge: _text(fontWeight: FontWeight.w700, color: ink, fontSize: 16),
      titleMedium: _text(fontWeight: FontWeight.w600, color: ink, fontSize: 15),
      bodyLarge: _text(color: ink, fontSize: 15, height: 1.45),
      bodyMedium: _text(color: muted, fontSize: 13, height: 1.45),
      labelLarge: _text(fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );

    return base.copyWith(
      scaffoldBackgroundColor: boardBg,
      colorScheme: const ColorScheme.light(
        primary: brandGreenDark,
        secondary: brandGoldDeep,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: ink,
        onSurface: ink,
        error: brandRed,
      ),
      textTheme: textTheme,
      dividerColor: line,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: _text(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: _text(color: muted, fontWeight: FontWeight.w600),
        hintStyle: _text(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: brandGreenDark, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreenDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _text(fontWeight: FontWeight.w800),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandGreenDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _text(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandGreenDark,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mist,
        selectedColor: brandGold.withValues(alpha: 0.22),
        labelStyle: _text(fontWeight: FontWeight.w700, color: ink, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brandGreenDeep,
        indicatorColor: brandGold.withValues(alpha: 0.28),
        labelTextStyle: WidgetStatePropertyAll(
          _text(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white),
        ),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
      ),
    );
  }

  static Color stageColor(String code) {
    switch (code) {
      case 'NEW_LEAD':
        return brandBlue;
      case 'CALL_NOT_RECEIVED':
        return const Color(0xFF6B7C86);
      case 'CALL_DONE':
      case 'CALL_NOTE_RECEIVED':
      case 'CONTACTED':
      case 'INTERESTED':
      case 'FOLLOW_UP':
        return const Color(0xFF7C5CFC);
      case 'SITE_VISIT_BOOKED':
      case 'SITE_VISIT_PLANNED':
      case 'NEGOTIATION':
        return brandGoldDeep;
      case 'SITE_VISIT_DONE':
        return const Color(0xFF0F9F8A);
      case 'UNIT_BOOKED':
      case 'BOOKED':
      case 'CLOSED':
        return brandGreenDark;
      case 'LOST':
        return brandRed;
      default:
        return muted;
    }
  }

  static String platformLabel(String? platform) {
    switch ((platform ?? '').toLowerCase()) {
      case 'ig':
      case 'instagram':
        return 'Instagram';
      case 'fb':
      case 'facebook':
        return 'Facebook';
      default:
        return platform == null || platform.isEmpty ? '—' : platform.toUpperCase();
    }
  }
}
