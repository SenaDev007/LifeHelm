// LifeHelm — Couleurs & thème
// Palette inspirée terre africaine + indigo + accents FCFA orange
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LifeHelmColors {
  LifeHelmColors._();

  // Primary — indigo profond (gouvernail)
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF3B5E8A);
  static const Color primaryDark = Color(0xFF0F2542);

  // Accent — orange FCFA / coucher de soleil
  static const Color accent = Color(0xFFE89B3C);
  static const Color accentLight = Color(0xFFF4BC6F);
  static const Color accentDark = Color(0xFFB47020);

  // Terre africaine
  static const Color earth = Color(0xFF8B5A2B);
  static const Color sand = Color(0xFFE8D9B8);
  static const Color kenteYellow = Color(0xFFF2C744);
  static const Color kenteGreen = Color(0xFF1E8449);
  static const Color kenteRed = Color(0xFFC0392B);

  // États
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Background
  static const Color bg = Color(0xFFF8F6F1); // sable clair
  static const Color bgCard = Colors.white;
  static const Color bgDark = Color(0xFF1A1F2E);
  static const Color bgDarkCard = Color(0xFF242B3D);

  // Texte
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnAccent = Color(0xFF1A1A1A);

  // Module colors (chaque pilier a sa couleur)
  static const Color finance = Color(0xFF10B981);    // vert émeraude
  static const Color goals = Color(0xFF8B5CF6);       // violet
  static const Color routines = Color(0xFF3B82F6);    // bleu
  static const Color health = Color(0xFFEF4444);      // rouge corail
  static const Color career = Color(0xFFF59E0B);      // ambre
  static const Color relations = Color(0xFFEC4899);   // rose

  // Mode Accessible — couleurs plus contrastées
  static const Color accessibleGreen = Color(0xFF059669);
  static const Color accessibleRed = Color(0xFFDC2626);
  static const Color accessibleBlue = Color(0xFF2563EB);
}

class LifeHelmTheme {
  LifeHelmTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: LifeHelmColors.primary,
        onPrimary: LifeHelmColors.textOnPrimary,
        secondary: LifeHelmColors.accent,
        onSecondary: LifeHelmColors.textOnAccent,
        surface: LifeHelmColors.bgCard,
        onSurface: LifeHelmColors.textPrimary,
        error: LifeHelmColors.danger,
      ),
      scaffoldBackgroundColor: LifeHelmColors.bg,
      cardColor: LifeHelmColors.bgCard,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: LifeHelmColors.textPrimary,
        displayColor: LifeHelmColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LifeHelmColors.bg,
        foregroundColor: LifeHelmColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: LifeHelmColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: LifeHelmColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LifeHelmColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LifeHelmColors.textTertiary, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LifeHelmColors.textTertiary, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LifeHelmColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LifeHelmColors.primary,
          foregroundColor: LifeHelmColors.textOnPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LifeHelmColors.primary,
          side: const BorderSide(color: LifeHelmColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: LifeHelmColors.bgCard,
        selectedItemColor: LifeHelmColors.primary,
        unselectedItemColor: LifeHelmColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E7EB),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: LifeHelmColors.accent,
        onPrimary: LifeHelmColors.textOnAccent,
        secondary: LifeHelmColors.accent,
        onSecondary: LifeHelmColors.textOnAccent,
        surface: LifeHelmColors.bgDarkCard,
        onSurface: Colors.white,
        error: LifeHelmColors.danger,
      ),
      scaffoldBackgroundColor: LifeHelmColors.bgDark,
      cardColor: LifeHelmColors.bgDarkCard,
    );
  }

  // Thème Mode Accessible — gros contrastes, grosses polices
  static ThemeData get accessible {
    final base = light;
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 20),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w800),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(fontSize: 36, fontWeight: FontWeight.w800),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LifeHelmColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          minimumSize: const Size(double.infinity, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
