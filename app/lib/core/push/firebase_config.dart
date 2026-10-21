import 'package:firebase_core/firebase_core.dart';

// ═══════════════════ CONFIGURATION FIREBASE (FCM) — OPTIONNELLE ═══════════════════
//
// Le push serveur (FCM) n'est actif que si un projet Firebase est branché.
// Deux façons de l'activer — au choix :
//
//   1. ANDROID natif : déposer `android/app/google-services.json` (console
//      Firebase) et appliquer le plugin Gradle `com.google.gms.google-services`
//      dans android/build.gradle.kts — `Firebase.initializeApp()` par défaut
//      lira alors la configuration automatiquement.
//
//   2. Multi-plateforme : renseigner [kFirebaseOptions] ci-dessous (valeurs
//      PUBLIQUES de la console Firebase → Paramètres du projet → Vos apps ;
//      ce ne sont pas des secrets).
//
// Tant que rien n'est branché, `Firebase.initializeApp()` échoue proprement et
// l'application replie sur la notification LOCALE quotidienne : le briefing
// reste notifié chaque jour, honnêtement (jamais d'échec silencieux).
//
// Côté serveur : renseigner FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL et
// FIREBASE_PRIVATE_KEY (Railway → Variables d'environnement) pour que le cron
// du briefing pousse réellement vers les appareils enregistrés.

/// Options Firebase explicites — `null` tant que le projet n'est pas branché.
/// Exemple :
/// ```dart
/// const kFirebaseOptions = FirebaseOptions(
///   apiKey: 'AIza…',
///   appId: '1:1234567890:android:abcdef',
///   messagingSenderId: '1234567890',
///   projectId: 'lifehelm',
/// );
/// ```
const FirebaseOptions? kFirebaseOptions = null;
