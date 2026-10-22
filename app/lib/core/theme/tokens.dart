import 'package:flutter/material.dart';

/// Design tokens LifeHelm — palette officielle 2026 : Navy Royal + Or solaire.
/// Interface claire et lumineuse : ivoire clair en fond, blanc pur pour les
/// cartes, Navy Royal pour l'identité, Or solaire pour ce qui compte.
/// Règles intangible (direction artistique) :
/// 1. L'or signale l'importance — il ne colore ni tous les boutons ni tous
///    les textes.
/// 2. Chaque couleur fonctionnelle garde un sens constant : vert = réussite,
///    bleu électrique = interaction, orange = attention.
/// 3. Le contraste reste prioritaire : sur fond doré, texte bleu nuit.
abstract final class LHColors {
  // —— Marque ——
  static const Color navy = Color(0xFF0B3D91); // Navy Royal — identité, titres, boutons principaux
  static const Color navyInk = Color(0xFF0F172A); // Bleu nuit — texte principal, fond sombre
  static const Color or = Color(0xFFFFB400); // Or solaire — actions prioritaires, sélection active
  static const Color orDeep = Color(0xFFB45309); // or profond — texte doré lisible sur fond clair
  static const Color orSurface = Color(0xFF33290A); // surface dorée sur fond sombre
  static const Color orTint = Color(0xFFFFF4D6); // lavis doré sur fond clair
  static const Color electrique = Color(0xFF3B82F6); // Bleu électrique — interactions, infos
  static const Color electriqueClair = Color(0xFF60A5FA); // variante lisible sur fond sombre
  static const Color vertSucces = Color(0xFF22C55E); // Vert succès — réussite, progression +
  static const Color vertProfond = Color(0xFF16A34A); // vert lisible sur fond clair
  static const Color orange = Color(0xFFFF7A00); // Orange énergie — rappels, attention
  static const Color ivoire = Color(0xFFFAFBFF); // Ivoire clair — fond général
  static const Color ivoireCard = Color(0xFFFFFFFF); // Blanc pur — cartes et surfaces
  static const Color ivoireElevated = Color(0xFFF1F5F9); // surfaces élevées claires
  static const Color ardoise = Color(0xFF64748B); // Gris ardoise — texte secondaire, icônes inactives
  static const Color nuage = Color(0xFFE2E8F0); // Gris nuage — bordures, séparateurs

  // —— Alias historiques (conservés pour la compatibilité du code existant) ——
  static const Color noir = navyInk; // fond du mode sombre
  static const Color noirSurface = Color(0xFF1E293B); // cartes sur fond sombre
  static const Color noirElevated = Color(0xFF273449); // surfaces élevées sombres
  static const Color emeraude = vertProfond;
  static const Color emeraudeClair = vertSucces;
  static const Color emeraudeSurface = Color(0xFF0B2B1A);
  static const Color texteClair = Color(0xFFF1F5F9); // texte sur fond sombre
  static const Color texteSombre = navyInk; // texte principal (bleu nuit)
  static const Color texteSecondaire = Color(0xFF94A3B8); // texte secondaire sur sombre
  static const Color texteSecondaireClair = ardoise; // texte secondaire sur clair
  static const Color bordureSombre = Color(0xFF334155);
  static const Color bordureClaire = nuage;

  // —— États ——
  static const Color succes = vertSucces;
  static const Color alerte = orange;
  static const Color erreur = Color(0xFFDC2626);
  static const Color erreurSurface = Color(0xFF2E1A1A);
  static const Color info = electrique;
  static const Color neutre = ardoise;

  // —— Statuts tâches (D03) ——
  static const Color tacheTodo = ardoise;
  static const Color tacheEnCours = electrique;
  static const Color tacheAttente = orange;
  static const Color tacheTerminee = vertSucces;
  static const Color tacheAnnulee = Color(0xFFDC2626);

  // —— Priorités (D03) : LOW, NORMAL, HIGH, URGENT ——
  static const Color prioBasse = ardoise;
  static const Color prioNormale = electrique;
  static const Color prioHaute = orange;
  static const Color prioUrgente = Color(0xFFDC2626);

  // —— Notifications (D13) : 4 niveaux ——
  static const Color notifInfo = electrique;
  static const Color notifNormale = ardoise;
  static const Color notifImportante = orange;
  static const Color notifCritique = Color(0xFFDC2626);

  // —— Finance ——
  static const Color financePositif = vertSucces;
  static const Color financeNegatif = Color(0xFFDC2626);
  static const Color financeAttente = orange;

  // —— Espaces ——
  static const Color espacePerso = Color(0xFFFFB400);
  static const Color espaceFamille = vertSucces;
  static const Color espacePro = electrique;
}

abstract final class LHSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double screen = 20;
}

abstract final class LHRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

/// Noms de police bundlés (pubspec) — Manrope titres, Inter texte courant (CDC §4.4).
abstract final class LHFonts {
  static const String titres = 'Manrope';
  static const String texte = 'Inter';
}

/// Aides de lisibilité (règle n°3 : le contraste reste prioritaire).
///
/// Les chips sélectionnés et les tuiles de statistiques posent des accents
/// colorés sur des surfaces dorées claires (thème clair) — l'or solaire
/// brut (#FFB400) y est illisible. Ces fonctions traduisent un accent en
/// variante lisible selon la luminosité.
abstract final class LHContrast {
  /// Variante de texte lisible d'un accent posé sur un fond CLAIR :
  /// or solaire → or profond ; vert succès → vert profond.
  static Color accentOnLight(Color c) {
    if (c == LHColors.or) return LHColors.orDeep;
    if (c == LHColors.vertSucces) return LHColors.vertProfond;
    return c;
  }

  /// Couleur de libellé d'un chip sélectionné (fond orTint en clair,
  /// orSurface en sombre) : bleu nuit sur lavis doré, lavis doré sur
  /// surface sombre — jamais blanc ni or brut.
  static Color selectedChipLabel(Brightness b) =>
      b == Brightness.dark ? LHColors.orTint : LHColors.navyInk;
}

/// Codes d'icônes de secours pour les catégories financières.
abstract final class LHIcons {
  static const List<IconData> finance = [
    Icons.shopping_basket_outlined,
    Icons.restaurant_outlined,
    Icons.directions_bus_outlined,
    Icons.home_outlined,
    Icons.bolt_outlined,
    Icons.school_outlined,
    Icons.health_and_safety_outlined,
    Icons.receipt_long_outlined,
    Icons.celebration_outlined,
    Icons.savings_outlined,
    Icons.phone_android_outlined,
    Icons.work_outline,
  ];
}
