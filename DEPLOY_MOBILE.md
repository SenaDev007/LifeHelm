# 📱 Guide de Déploiement Mobile — LifeHelm

> Comment générer les APK / IPA et publier sur les stores Android (Play Store) et iOS (App Store).

---

## 📋 Prérequis

- Flutter SDK 3.24+ installé (`flutter --version`)
- Le backend doit être déployé et accessible en HTTPS (voir `DEPLOY_BACKEND.md`)
- Android Studio (pour Android) ou Xcode 15+ sur macOS (pour iOS)
- Comptes développeur :
  - **Google Play Console** ($25 unique) — https://play.google.com/console
  - **Apple Developer Program** ($99/an) — https://developer.apple.com

---

## 🔧 Configuration pré-déploiement

### 1. Mettre à jour l'URL de l'API

Modifie `mobile/lib/config/app_config.dart` :

```dart
static const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.lifehelm.app/api',  // ton URL de prod
);
```

Ou via `--dart-define` à la compilation (recommandé) :

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.lifehelm.app/api
```

### 2. Mettre à jour la version

Dans `mobile/pubspec.yaml` :

```yaml
version: 1.0.0+1  # format: versionMajor.versionMinor.versionPatch+buildNumber
```

Incrémente le `+buildNumber` à chaque release.

### 3. Configurer l'icône et le splash

Installe `flutter_launcher_icons` :
```bash
flutter pub add --dev flutter_launcher_icons
```

Crée `mobile/flutter_launcher_icons.yaml` :
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon.png"  # 1024x1024 PNG
  adaptive_icon_background: "#1E3A5F"
  adaptive_icon_foreground: "assets/icon_foreground.png"
```

Génère :
```bash
dart run flutter_launcher_icons
```

---

## 🤖 DÉPLOIEMENT ANDROID (APK + Play Store)

### Étape 1 — Générer le keystore de signature

**⚠️ CRITIQUE** : Ce keystore identifie ton app. Si tu le perds, tu ne pourras plus publier de mise à jour. Garde-le en sécurité (backup chiffré).

```bash
keytool -genkey -v -keystore ~/lifehelm-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias lifehelm
```

Réponds aux questions (mot de passe, nom, organisation, etc.).

### Étape 2 — Configurer Flutter pour utiliser le keystore

Crée `mobile/android/key.properties` :

```properties
storePassword=*****      # mot de passe du keystore
keyPassword=*****        # mot de passe de la clé
keyAlias=lifehelm
storeFile=/Users/ton-nom/lifehelm-upload.jks  # chemin absolu
```

**⚠️ AJOUTE `mobile/android/key.properties` AU `.gitignore` (déjà fait).**

### Étape 3 — Modifier `android/app/build.gradle.kts`

Ajoute avant `android {` :

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Dans `android { ... }`, ajoute :

```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
```

Crée `mobile/android/app/proguard-rules.pro` :

```
# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prisma / Drift (pas nécessaire pour sqflite)
-keep class org.sqlite.** { *; }

# Gson / JSON
-keepattributes Signature
-keepattributes *Annotation*
```

### Étape 4 — Build APK de release

```bash
cd mobile
flutter clean
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.lifehelm.app/api
```

**Résultat** : `mobile/build/app/outputs/flutter-apk/app-release.apk`

Pour tester l'APK sur un device :
```bash
flutter install
```

### Étape 5 — Build App Bundle (AAB) pour Play Store

Le Play Store requiert le format `.aab` (Android App Bundle) qui optimise la taille par device :

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.lifehelm.app/api
```

**Résultat** : `mobile/build/app/outputs/bundle/release/app-release.aab`

### Étape 6 — Publication sur Google Play Store

1. Va sur https://play.google.com/console
2. Crée une application : **LifeHelm**, catégorie **Finance** ou **Lifestyle**
3. Configure la fiche Store :
   - **Nom** : LifeHelm — Take the helm of your life
   - **Description courte** : Système d'exploitation de vie pour l'Afrique francophone
   - **Description longue** : voir `STORE_LISTING.md`
   - **Icône** : 512x512 PNG
   - **Feature graphic** : 1024x500 PNG
   - **Screenshots** : minimum 2, format 16:9 ou 9:16
4. Section **Versions de production** → **Créer une version**
5. Importe `app-release.aab`
6. Remplis les notes de version (ex: "Version initiale 1.0.0")
7. Configure la **trace des confidentialités** (data collected : achats, informations financières, photos)
8. Soumettre pour révision (compte en test fermé d'abord recommandé)

### Étape 7 — Test avant production (recommandé)

Avant de publier en prod, teste via **Internal Testing** :

1. Play Console → **Tests internes** → créer une trace
2. Importe l'AAB
3. Ajoute les emails des testeurs (jusqu'à 100)
4. Partage le lien d'inscription aux testeurs
5. Ils peuvent installer l'app depuis le Play Store en version test

---

## 🍎 DÉPLOIEMENT iOS (IPA + App Store)

### Prérequis macOS

```bash
# Vérifier Xcode
xcodebuild -version  # doit être 15+

# Installer CocoaPods si pas déjà
sudo gem install cocoapods
```

### Étape 1 — Configurer le Bundle ID

Dans `mobile/ios/Runner.xcworkspace` (ouvre avec Xcode) :
1. Clique sur **Runner** dans le panneau gauche
2. Onglet **Signing & Capabilities**
3. **Bundle Identifier** : `com.yehiortech.lifehelm` (doit être unique)
4. **Team** : sélectionne ton Apple Developer account
5. Coche **Automatically manage signing**

### Étape 2 — Configurer App Store Connect

1. Va sur https://appstoreconnect.apple.com
2. **Mes apps** → **+** → **Nouvelle app**
3. Nom : **LifeHelm**, langue : **Français**, Bundle ID : **com.yehiortech.lifehelm**
4. SKU : `lifehelm` (identifiant interne)

### Étape 3 — Build IPA

```bash
cd mobile
flutter clean
flutter pub get

# Build pour iOS (nécessite macOS + Xcode)
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.lifehelm.app/api \
  --export-options-plist=ios/ExportOptions.plist
```

Crée `mobile/ios/ExportOptions.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>TON_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

**Résultat** : `mobile/build/ios/ipa/LifeHelm.ipa`

### Étape 4 — Uploader sur App Store Connect

**Option A — Xcode (recommandé pour débuter)** :
1. Ouvre Xcode → **Window** → **Organizer**
2. Sélectionne l'archive créée
3. Clique **Distribute App** → **App Store Connect** → **Upload**
4. Suis les étapes

**Option B — CLI (altool)** :
```bash
xcrun altool --upload-app \
  -f build/ios/ipa/LifeHelm.ipa \
  -t ios \
  -u ton-email@apple.id \
  -p motdepasse_app_specifique
```

### Étape 5 — Configurer la fiche App Store

Dans App Store Connect → **LifeHelm** :

1. **App Information** :
   - Catégorie primaire : **Finance**
   - Catégorie secondaire : **Lifestyle**
   - Classification : **4+**

2. **Pricing and Availability** :
   - Gratuit avec achats intégrés (abonnements Pro/Family)
   - Disponibilité : Bénin, Côte d'Ivoire, Sénégal, Togo, France (à étendre)

3. **App Privacy** ("Trace de confidentialité") :
   - Données collectées : Identifiants (email), Achats, Données financières (transactions), Photos (reçus)
   - Finalités : Fonctionnement de l'app, Personnalisation

4. **Screenshots** :
   - 6.7" (iPhone 14 Pro Max) : 1290x2796
   - 5.5" (iPhone 8 Plus) : 1242x2208
   - iPad 12.9" si supporté : 2048x2732
   - Minimum 3 screenshots par taille

5. **App Review Information** :
   - Détails de connexion démo : `demo@lifehelm.app` / `lifehelm123`
   - Notes pour le reviewer : "App de gestion de vie holistique en français"

6. **Version Release** :
   - Crée une version 1.0.0
   - Importe l'IPA
   - Remplis les notes de version
   - Soumettre pour révision

### Étape 6 — Test avant production

1. App Store Connect → **TestFlight**
2. Importe ton premier build
3. Ajoute des testeurs internes (équipe Apple Developer)
4. Ajoute des testeurs externes (jusqu'à 10 000, nécessite révision Apple)
5. Récupère les retours, corrige, re-uploade

---

## 🚀 Déploiement Backend (préalable au mobile)

Le backend doit être en HTTPS pour que l'app mobile puisse communiquer avec.

### Option A — Railway (le plus simple)

```bash
# Installe Railway CLI
npm install -g @railwayapp/cli

# Depuis le dossier backend/
cd backend
railway login
railway init  # créer un nouveau projet
railway up    # déployer
railway domain  # obtenir l'URL publique
```

Variables d'environnement à configurer dans Railway :
- `DATABASE_URL` (Neon)
- `DIRECT_URL` (Neon)
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (générer avec `openssl rand -hex 32`)
- `NODE_ENV=production`
- `CORS_ORIGIN=*`
- `FEDAPAY_SECRET_KEY` (quand tu l'auras)

### Option B — Render

1. https://render.com → **New +** → **Web Service**
2. Connecte ton repo GitHub `SenaDev007/LifeHelm`
3. **Root Directory** : `backend`
4. **Build Command** : `npm install && npx prisma generate && npm run build`
5. **Start Command** : `npx prisma db push --accept-data-loss && node dist/index.js`
6. Ajoute les variables d'environnement
7. **Deploy**

### Option C — VPS avec Docker

```bash
# Sur le VPS
git clone https://github.com/SenaDev007/LifeHelm.git
cd LifeHelm
cp backend/.env.production.example backend/.env
# Édite backend/.env avec tes vraies valeurs
docker compose up -d --build
```

Avec Nginx + Let's Encrypt pour HTTPS :

```nginx
server {
    listen 80;
    server_name api.lifehelm.app;
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
sudo certbot --nginx -d api.lifehelm.app
```

---

## ✅ Checklist de production

Avant de soumettre aux stores, vérifie :

- [ ] Backend déployé en HTTPS (URL `https://api.lifehelm.app/api`)
- [ ] `mobile/lib/config/app_config.dart` pointe vers la bonne URL
- [ ] `flutter analyze` : 0 erreur
- [ ] `flutter test` : tous les tests passent
- [ ] Version incrémentée dans `pubspec.yaml` (`1.0.0+1`)
- [ ] Icônes générées (`flutter_launcher_icons`)
- [ ] Splash screen configuré
- [ ] Testé sur émulateur Android ET simulateur iOS
- [ ] Testé sur device physique Android (Tecno Pop si possible pour Mode Accessible)
- [ ] Compte démo fonctionne (`demo@lifehelm.app` / `lifehelm123`)
- [ ] Notifications push testées
- [ ] Connexion offline testée (mode avion)
- [ ] Fiche store prête (description, screenshots, icône, classification)
- [ ] Politique de confidentialité rédigée (URL publique)
- [ ] CGU rédigées (URL publique)

---

## 🆘 Dépannage

### Build Android échoue : "Keystore file not found"
→ Vérifie le chemin absolu dans `key.properties`

### Build iOS échoue : "No profiles for 'com.yehiortech.lifehelm' were found"
→ Ouvre Xcode → Signing & Capabilities → sélectionne ta Team → coche Automatically manage signing

### App ne se connecte pas au backend
→ Vérifie l'URL dans `app_config.dart`
→ Test avec `curl https://api.lifehelm.app/health`
→ Vérifie que CORS est `*` ou inclut ton origine

### Notifications ne s'affichent pas (Android 13+)
→ L'utilisateur doit accorder la permission POST_NOTIFICATIONS
→ L'app la demande automatiquement au premier lancement via `requestPermissions()`

### HELM AI ne répond pas
→ Le backend utilise `z-ai-web-dev-sdk` qui ne nécessite pas de clé API
→ Vérifie que le backend tourne et que l'endpoint `/api/ai/conversations/:id/messages` répond

---

## 📚 Ressources

- [Flutter deployment docs](https://docs.flutter.dev/deployment)
- [Play Console Help](https://support.google.com/googleplay/android-developer/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [FedaPay docs](https://fedapay.com/docs)
- [Apple Sign In requirement](https://developer.apple.com/sign-in-with-apple/) (si tu utilises Google OAuth, tu DOIS ajouter Apple Sign In sur iOS)
