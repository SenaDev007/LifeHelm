import 'package:firebase_core/firebase_core.dart';

// ═══════════════════ CONFIGURATION FIREBASE (FCM) — PROJET « lifehelm » ═══════════════════
//
// Brancheur : option 1 (natif Android) est ACTIVE depuis le 22/10/2026.
//
//   • `android/app/google-services.json` est déposé (console Firebase,
//     projet « lifehelm », package com.yehiortech.lifehelm) et le plugin
//     Gradle `com.google.gms.google-services` est appliqué :
//     `Firebase.initializeApp()` lit la configuration automatiquement —
//     [kFirebaseOptions] reste `null`.
//
//   • [kFirebaseOptions] (option 2) ne sert que si l'on veut piloter la
//     configuration depuis Dart (multi-plateforme). Valeurs publiques de la
//     console Firebase → Paramètres du projet → Vos apps, si besoin :
//     projectId `lifehelm`, messagingSenderId `154896556414`,
//     storageBucket `lifehelm.firebasestorage.app`.
//
// Repli LOCAL : tant que le serveur n'a pas ses credentials, la notification
// locale quotidienne continue de fonctionner (briefing notifié honnêtement).
//
// Côté serveur : renseigner FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL et
// FIREBASE_PRIVATE_KEY (Railway → Variables d'environnement) pour que le cron
// du briefing pousse réellement vers les appareils enregistrés.

/// Options Firebase explicites — `null` : la configuration native
/// (google-services.json) fait foi.
const FirebaseOptions? kFirebaseOptions = null;
