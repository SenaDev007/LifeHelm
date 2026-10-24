import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (FCM) : traite android/app/google-services.json (projet
    // « lifehelm ») et génère les ressources de configuration.
    id("com.google.gms.google-services")
}

// ── Signature release (Play Store) ─────────────────────────────────────────────
// Identifiants dans android/key.properties (non versionné — voir .gitignore).
// Sans ce fichier (build anonyme/CI), repli sur la clé debug.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null
if (!hasReleaseKeystore) {
    logger.warn(
        "⚠️  android/key.properties introuvable : le bundle release sera signé " +
        "avec la CLÉ DEBUG — refusé par la Play Console. Créez le keystore " +
        "(keytool -genkey) + android/key.properties avant le build release."
    )
}

android {
    namespace = "com.yehiortech.lifehelm"
    compileSdk = flutter.compileSdkVersion
    // NDK : aucun module de l'app ne compile en natif (AAR précompilés ;
    // overrides path_provider/shared_preferences pour éviter « jni »),
    // MAIS la tâche stripReleaseDebugSymbols a besoin d'un NDK résolu pour
    // lancer llvm-strip. Épinglé à 28.2.13676358 — version installée sur
    // le poste de build (flutter passe installedNdkVersions=27.0.12077973,
    // 28.2.13676358) — car si le NDK configuré est introuvable, AGP saute
    // le strip avec un simple avertissement : le build Gradle réussit mais
    // l'AAB contient des .so non striés, que flutter_tools rejette ensuite
    // (voir la note « strip » ci-dessous). Sur un autre poste sans ce NDK,
    // Android Studio le téléchargera au premier build.
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Desugaring — exigé par flutter_local_notifications (notifications
        // programmées du briefing, D17.6) pour les API Java 8+ anciennes.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identité officielle de l'app (YEHI OR Tech) — correspond au package
        // enregistré dans Firebase (google-services.json, projet « lifehelm »).
        applicationId = "com.yehiortech.lifehelm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Signature release (Play Store) — déclarée AVANT buildTypes (ordre
    // d'évaluation Kotlin DSL). Identifiants dans android/key.properties
    // (non versionné) ; keystore : android/app/upload-keystore.jks.
    // Sans ce fichier (build anonyme/CI), repli sur la clé debug.
    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Play App Signing : Google gère la clé applicative ; cette clé
            // (« upload ») signe les AAB téléversés. Repli debug si key.properties absent.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // Strip des symboles de débogage des .so : DOIT rester ACTIF.
    // flutter_tools (flutter build appbundle) valide l'AAB APRÈS le build
    // Gradle : il inspecte les tables de symboles ELF de chaque
    // lib/<abi>/*.so et fait échouer la commande avec « Release app bundle
    // failed to strip debug symbols from native libraries » si une seule
    // bibliothèque n'est pas striée — même quand le build Gradle a réussi.
    // C'est pourquoi jniLibs.keepDebugSymbols est INTERDIT ici : il
    // neutralise llvm-strip et garantit ce rejet (flutter/flutter#170004).
    // Correctif : plus aucun bloc packaging — le strip AGP/llvm-strip
    // s'exécute normalement, aidé par le ndkVersion épinglé ci-dessus.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
