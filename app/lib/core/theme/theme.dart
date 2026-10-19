import 'package:flutter/material.dart';

import 'tokens.dart';

/// Thèmes LifeHelm — clair (ivoire), sombre (noir premium) et système (CDC §4.3).
/// La palette de marque est commune ; sa distribution varie pour la lisibilité :
/// — sombre : or pur (#FFD700) en accents principaux ;
/// — clair : or profond (#C9A227) + émeraude profonde pour garantir le contraste.
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
      primary: LHColors.or,
      onPrimary: LHColors.noir,
      secondary: LHColors.emeraudeClair,
      onSecondary: LHColors.noir,
      tertiary: LHColors.emeraude,
      onTertiary: Colors.white,
      surface: LHColors.noirSurface,
      onSurface: LHColors.texteClair,
      surfaceContainerHighest: LHColors.noirElevated,
      onSurfaceVariant: LHColors.texteSecondaire,
      error: LHColors.erreur,
      onError: Colors.white,
      outline: LHColors.bordureSombre,
      outlineVariant: const Color(0xFF262626),
    );
    return _base(Brightness.dark, scheme, LHColors.noir);
  }

  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: LHColors.orDeep,
      onPrimary: LHColors.texteSombre,
      secondary: LHColors.emeraude,
      onSecondary: Colors.white,
      tertiary: LHColors.orDeep,
      onTertiary: LHColors.texteSombre,
      surface: LHColors.ivoireCard,
      onSurface: LHColors.texteSombre,
      surfaceContainerHighest: LHColors.ivoireElevated,
      onSurfaceVariant: LHColors.texteSecondaireClair,
      error: const Color(0xFFC0392B),
      onError: Colors.white,
      outline: LHColors.bordureClaire,
      outlineVariant: const Color(0xFFEDEAE0),
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
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: _textTheme(b).titleLarge,
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
        backgroundColor: isDark ? LHColors.noir : LHColors.ivoire,
        indicatorColor: isDark ? LHColors.orSurface : const Color(0xFFFBF2CE),
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: LHFonts.texte, fontSize: 11.5, fontWeight: FontWeight.w600,
              color: scheme.onSurface),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 26,
              color: s.contains(WidgetState.selected)
                  ? (isDark ? LHColors.or : LHColors.orDeep)
                  : scheme.onSurfaceVariant,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
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
          foregroundColor: isDark ? LHColors.or : LHColors.orDeep,
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
          borderSide: BorderSide(color: isDark ? LHColors.or : LHColors.orDeep, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? LHColors.noirElevated : LHColors.ivoireElevated,
        selectedColor: isDark ? LHColors.orSurface : const Color(0xFFFBF2CE),
        labelStyle: TextStyle(fontFamily: LHFonts.texte, fontSize: 13, color: scheme.onSurface),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.full)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? LHColors.or : LHColors.emeraude,
        foregroundColor: isDark ? LHColors.noir : Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LHRadius.lg)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? LHColors.noirElevated : LHColors.texteSombre,
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
        labelColor: isDark ? LHColors.or : LHColors.orDeep,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: isDark ? LHColors.or : LHColors.orDeep,
        labelStyle: TextStyle(fontFamily: LHFonts.titres, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: LHFonts.titres, fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? (isDark ? LHColors.noir : Colors.white)
            : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? (isDark ? LHColors.or : LHColors.emeraude)
            : scheme.outline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? LHColors.or : LHColors.orDeep,
        linearTrackColor: isDark ? LHColors.noirElevated : LHColors.ivoireElevated,
      ),
    );
  }
}
