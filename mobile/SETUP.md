# LifeHelm Mobile — Setup Platform Files

> ⚠️ Ce dossier ne contient PAS les fichiers de plateforme Android/iOS natifs (ils sont trop volumineux pour le repo).
> Tu dois les générer en une seule commande après avoir cloné le repo.

## 📋 Étapes

### 1. Installer Flutter
```bash
# Si pas déjà fait
# https://docs.flutter.dev/get-started/install
flutter --version
```

### 2. Installer les dépendances
```bash
cd mobile
flutter pub get
```

### 3. Générer les fichiers de plateforme manquants
```bash
# Génère android/ et ios/ (sans écraser lib/ et pubspec.yaml)
flutter create --project-name lifehelm --org com.yehiortech .
```

### 4. Configuration post-génération

#### Android — `android/app/src/main/AndroidManifest.xml`
Ajouter ces permissions avant `<application>` :
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />  <!-- Mode Accessible: saisie vocale -->
<uses-permission android:name="android.permission.CAMERA" />  <!-- Photos de reçus -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

Dans `<application>`, ajouter :
```xml
android:usesCleartextTraffic="true"  <!-- Pour autoriser HTTP en dev (10.0.2.2) -->
android:name="${applicationName}"
```

#### iOS — `ios/Runner/Info.plist`
Ajouter avant `</dict>` :
```xml
<key>NSMicrophoneUsageDescription</key>
<string>LifeHelm utilise le micro pour la saisie vocale en Mode Accessible.</string>
<key>NSCameraUsageDescription</key>
<string>LifeHelm utilise la caméra pour photographier les reçus.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>LifeHelm accède à vos photos pour les reçus et avatars.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>  <!-- Pour autoriser HTTP en dev -->
</dict>
```

### 5. Lancer l'app

```bash
# S'assurer que le backend tourne sur localhost:3001 (cd ../backend && npm run dev)

# Émulateur Android (l'API utilise 10.0.2.2 par défaut)
flutter run

# Simulateur iOS
flutter run -d ios

# Device physique (changer l'URL API)
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3001/api
```

## 🔧 Configuration API

L'URL de base de l'API est configurable via `--dart-define` :

| Plateforme | URL |
|------------|-----|
| Émulateur Android | `http://10.0.2.2:3001/api` (défaut) |
| Simulateur iOS | `http://127.0.0.1:3001/api` |
| Device physique | `http://<IP-LAN>:3001/api` |

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3001/api
```

## 🎨 Génération de code

Certaines dépendances nécessitent `build_runner` :
```bash
dart run build_runner build --delete-conflicting-outputs
```

(Pour V1, le code a été écrit sans dépendre de codegen pour faciliter le démarrage — cette étape est optionnelle.)
