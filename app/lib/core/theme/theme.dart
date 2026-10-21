import 'package:flutter/material.dart';

import 'tokens.dart';

/// Thèmes LifeHelm — palette officielle 2026 (Navy Royal + Or solaire).
/// Interface claire par défaut : fond ivoire #FAFBFF, cartes blanches,
/// titres Navy Royal, actions prioritaires Or solaire (texte bleu nuit),
/// interactions Bleu électrique, réussite Vert succès, rappels Orange énergie.
/// — clair : Navy Royal #0B3D91 en boutons principaux, or en accents ;
/// — sombre : Bleu nuit #0F172A en fond, or solaire en accents principaux.
class LHTheme {
  static TextTheme _textTheme(Brightness b) {
    final base = (b == Brightness.dark ? Typography.whiteCupertino : Typography.blackCupertino)
        .apply(bodyColor: b == Brightness.dark ? LHColors.texteClair : LHColors.texteSombre);
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w800),
      displayMedium: base.displayMedium?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w800),
      displaySmall: base.displaySmall?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
      headlineLarge: base.headlineLarge?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontFamily: LHFonts.titres, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontFamily: LHFonts.texte),
      bodyMedium: base.bodyMedium?.copyWith(fontFamily: LHFonts.texte),
      bodySmall: base.bodySmall?.copyWith(fontFamily: LHFonts.texte),
      labelLarge: base.labelLarge?.copyWith(fontFamily: LHFonts.texte, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontFamily: LHFonts.texte, fontWeight: FontWeight.w500),
      labelSmall: base.labelSmall?.copyWith(fontFamily: LHFonts.texte, fontWeight: FontWeight.w500),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: LHColors.or, // or solaire — accents principaux sur bleu nuit
      onPrimary: LHColors.navyInk, // texte bleu nuit sur or (contraste)
      secondary: LHColors.electriqueClair,
      onSecondary: LHColors.navyInk,
      tertiary: LHColors.vertSucces,
      onTertiary: LHColors.navyInk,
      surface: LHColors.noirSurface,
      onSurface: LHColors.texteClair,
      surfaceContainerHighest: LHColors.noirElevated,
      onSurfaceVariant: LHColors.texteSecondaire,
      error: const Color(0xFFF87171),
      onError: LHColors.navyInk,
      outline: LHColors.bordureSombre,
      outlineVariant: const Color(0xFF22304A),
    );
    return _base(Brightness.dark, scheme, LHColors.navyInk);
  }

  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: LHColors.navy, // Navy Royal — boutons principaux, titres
      onPrimary: Colors.white,
      secondary: LHColors.electrique, // interactions et informations
      onSecondary: Colors.white,
      tertiary: LHColors.or, // or solaire — action prioritaire
      onTertiary: LHColors.navyInk, // texte bleu nuit sur or (règle contraste)
      surface: LHColors.ivoireCard, // cartes blanc pur
      onSurface: LHColors.texteSombre,
      surfaceContainerHighest: LHColors.ivoireElevated,
      onSurfaceVariant: LHColors.texteSecondaireClair,
      error: const Color(0xFFDC2626),
      onError: Colors.white,
      outline: LHColors.nuage, // bordures gris nuage
      outlineVariant: const Color(0xFFEDF1F7),
    );
    return _base(Brightness.light, scheme, LHColors.ivoire);
  }

  static ThemeData _base(Brightness b, ColorScheme scheme, Color scaffold) {
    final isDark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: _textTheme(b),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: isDark ? LHColors.texteClair : LHColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: _textTheme(b).titleLarge?.copyWith(
            color: isDark ? LHColors.texteClair : LHColors.navy),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LHRadius.lg),
          side: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 0.7 : 1)),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? LHColors.navyInk : Colors.white,
        indicatorColor: isDark ? LHColors.orSurface : LHColors.orTint,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: LHFonts.texte, fontSize: 11.5, fontWeight: FontWeight.w600,
              color: scheme.onSurface),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 26,
              color: s.contains(WidgetState.selected)
                  ? LHColors.or // actif : or solaire
                  : (isDark ? LHColors.texteSecondaire : LHColors.ardoise), // inactif : gris ardoise
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary, // bouton principal : navy (clair) / or (sombre)
          foregroundColor: scheme.onPrimary,
          textStyle: TextStyle(fontFamily: LHFonts.texte, fontWeight: FontWeight.w700, fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? LHColors.or : LHColors.electrique, // liens et actions secondaires
          textStyle: TextStyle(fontFamily: LHFonts.texte, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? LHColors.noirElevated : Colors.white,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LHRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LHRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LHRadius.md),
          borderSide: BorderSide(color: isDark ? LHColors.or : LHColors.electrique, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? LHColors.noirElevated : LHColors.ivoireElevated,
        selectedColor: isDark ? LHColors.orSurface : LHColors.orTint,
        labelStyle: TextStyle(fontFamily: LHFonts.texte, fontSize: 13, color: scheme.onSurface),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.full)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: LHColors.or, // action prioritaire : or solaire
        foregroundColor: LHColors.navyInk, // texte/îcone bleu nuit sur or
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.lg)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? LHColors.noirElevated : LHColors.navy,
        contentTextStyle: TextStyle(color: isDark ? LHColors.texteClair : Colors.white,
            fontFamily: LHFonts.texte),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.md)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? LHColors.noirSurface : Colors.white,
        modalBackgroundColor: isDark ? LHColors.noirSurface : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(LHRadius.xl)),
        ),
        showDragHandle: true,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? LHColors.or : LHColors.navy,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: LHColors.or, // sélection active : or solaire
        labelStyle: TextStyle(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: LHFonts.titres, fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? (isDark ? LHColors.navyInk : Colors.white)
            : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? (isDark ? LHColors.or : LHColors.electrique) // interaction : bleu électrique
            : scheme.outline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? LHColors.or : LHColors.electrique, // barres de progression
        linearTrackColor: isDark ? LHColors.noirElevated : LHColors.nuage,
      ),
    );
  }
}
