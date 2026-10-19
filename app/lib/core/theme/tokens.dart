import 'package:flutter/material.dart';

/// Design tokens LifeHelm — direction noir / or / émeraude (CDC §4).
/// Les couleurs d'état sont distinctes de la palette de marque (CDC §4.4).
abstract final class LHColors {
  // —— Marque ——
  static const Color noir = Color(0xFF101010);
  static const Color noirSurface = Color(0xFF1A1A1A);
  static const Color noirElevated = Color(0xFF232323);
  static const Color or = Color(0xFFFFD700); // or pur
  static const Color orDeep = Color(0xFFC9A227); // or profond — thème clair (contraste sur ivoire)
  static const Color orSurface = Color(0xFF2A2508);
  static const Color emeraude = Color(0xFF087F5B);
  static const Color emeraudeClair = Color(0xFF10A878);
  static const Color emeraudeSurface = Color(0xFF12291F);
  static const Color ivoire = Color(0xFFF7F5EF);
  static const Color ivoireCard = Color(0xFFFFFFFF);
  static const Color ivoireElevated = Color(0xFFF1EEE4);
  static const Color texteClair = Color(0xFFF5F1E8);
  static const Color texteSombre = Color(0xFF1C1B16);
  static const Color texteSecondaire = Color(0xFFA7A7A7);
  static const Color texteSecondaireClair = Color(0xFF6E6A5E);
  static const Color bordureSombre = Color(0xFF303030);
  static const Color bordureClaire = Color(0xFFE5E1D8);

  // —— États (distincts de la marque) ——
  static const Color succes = Color(0xFF10A878);
  static const Color alerte = Color(0xFFE8A13D);
  static const Color erreur = Color(0xFFE05B5B);
  static const Color erreurSurface = Color(0xFF2E1A1A);
  static const Color info = Color(0xFF5B8DD9);
  static const Color neutre = Color(0xFF8A8A8A);

  // —— Statuts tâches (D03) ——
  static const Color tacheTodo = Color(0xFF8A8A8A);
  static const Color tacheEnCours = Color(0xFF5B8DD9);
  static const Color tacheAttente = Color(0xFFE8A13D);
  static const Color tacheTerminee = Color(0xFF10A878);
  static const Color tacheAnnulee = Color(0xFFE05B5B);

  // —— Priorités (D03) : LOW, NORMAL, HIGH, URGENT ——
  static const Color prioBasse = Color(0xFF8A8A8A);
  static const Color prioNormale = Color(0xFF5B8DD9);
  static const Color prioHaute = Color(0xFFE8A13D);
  static const Color prioUrgente = Color(0xFFE05B5B);

  // —— Notifications (D13) : 4 niveaux ——
  static const Color notifInfo = Color(0xFF5B8DD9);
  static const Color notifNormale = Color(0xFF8A8A8A);
  static const Color notifImportante = Color(0xFFE8A13D);
  static const Color notifCritique = Color(0xFFE05B5B);

  // —— Finance ——
  static const Color financePositif = Color(0xFF10A878);
  static const Color financeNegatif = Color(0xFFE05B5B);
  static const Color financeAttente = Color(0xFFE8A13D);

  // —— Espaces ——
  static const Color espacePerso = Color(0xFFFFD700);
  static const Color espaceFamille = Color(0xFF10A878);
  static const Color espacePro = Color(0xFF5B8DD9);
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
