# LifeHelm

> **Prends le gouvernail de ta vie.**
> Le système d'exploitation de vie pour l'Afrique francophone.

LifeHelm est une application mobile (Flutter, Android + iOS) qui unifie les **6 piliers de la vie** — Finance, Objectifs, Routines, Santé, Carrière, Relations — dans un seul espace intelligent, pensé pour la réalité africaine francophone.

---

## 🎯 Fonctionnalités V1

### Module Finance (complet)
- Transactions (revenus / dépenses / transferts) avec catégories africaines
- Comptes multi-source : Cash, MTN MoMo, Moov Money, Wave, Banque, Épargne, Tontine
- Tableau de bord financier avec score de santé (0-100)
- Budget méthode 50/30/20 (ou personnalisée)
- Objectifs d'épargne avec progression visuelle
- **Tontines** (exclusivité africaine) : suivi des membres, rangs, paiements
- Dettes & créances (avec stratégie Boule de neige / Avalanche)
- Factures récurrentes avec rappels

### Module Objectifs
- Objectifs SMART (binaire, numérique, jalon)
- Vision long terme (1, 3, 5, 10 ans) par domaine de vie
- Décomposition en projets et tâches
- Journal de progression par objectif

### Module Routines
- Habit tracker avec streaks et heatmap 30 jours
- Rituel du matin personnalisable
- Revue de soirée (gratitude, priorités du lendemain)
- Rappels configurables par habitude

### Module Santé
- Suivi du sommeil (durée, qualité, tendance)
- Humeur quotidienne (5 niveaux) + énergie (1-10)
- Activité physique (séances, intensité, fréquence hebdo)
- Hydratation (jauge quotidienne, boutons rapides +250/+500ml)
- Score bien-être global + corrélations

### HELM AI (conseiller de vie holistique)
- Insights hebdomadaires automatiques basés sur les vraies données
- Détection de corrélations (sommeil ↔ dépenses alimentaires, sport ↔ productivité)
- Chat libre avec contexte utilisateur
- Alertes intelligentes proactives

### Mode Accessible (exclusivité — économie informelle)
- 3 boutons géants : VENTE / DÉPENSE / BILAN
- Logique boutiquier : Mise du matin → Recettes → Réappro → Bénéfice net
- Interface adaptée aux téléphones entry-level (Tecno Pop, Itel)
- Polices géantes, contrastes élevés
- Ardoise clients & crédit fournisseur
- Onboarding en 30 secondes

### Tableau de bord 360°
- Score de vie global (0-100) — moyenne pondérée des 6 piliers
- 6 jauges colorées (une par pilier)
- Top 3 priorités du jour
- Alertes intelligentes
- Résumé financier, habitudes du jour, derniers insights

### Autres
- Authentification JWT (access 15min + refresh 7j)
- Multi-langues : Français, Fon, Bariba, Yoruba (i18n)
- Offline-first (architecture prévue)
- Thème clair & sombre
- Design Material 3 avec palette africaine moderne

---

## 🏗️ Architecture

```
lifehelm/
├── backend/                  # API Node.js/Express + Prisma + PostgreSQL
│   ├── src/
│   │   ├── routes/           # auth, finance, goals, routines, health, ai, accessible, user
│   │   ├── middleware/       # auth, error
│   │   ├── utils/            # JWT, tokens
│   │   ├── config.ts
│   │   ├── db.ts             # Prisma client
│   │   ├── seed.ts           # Données de démo
│   │   └── index.ts
│   ├── prisma/
│   │   └── schema.prisma     # 25 modèles, 21 enums
│   └── package.json
│
├── mobile/                   # App Flutter (Android + iOS)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/           # AppConfig, catégories
│   │   ├── theme/            # Couleurs, thème africain moderne
│   │   ├── router/           # go_router
│   │   ├── models/           # Modèles Dart
│   │   ├── services/         # Dio API service
│   │   ├── utils/            # Formatage FCFA, dates
│   │   ├── widgets/          # Boutons, champs, gauges
│   │   └── features/
│   │       ├── auth/         # login, signup
│   │       ├── onboarding/   # Configuration initiale
│   │       ├── home/         # Dashboard 360° + main shell
│   │       ├── finance/      # Comptes, transactions, épargne, tontines, dettes, factures
│   │       ├── goals/        # Objectifs SMART
│   │       ├── routines/     # Habitudes, rituels
│   │       ├── health/       # Sommeil, humeur, sport, hydratation
│   │       ├── ai/           # HELM AI chat + insights
│   │       ├── accessible/   # Mode Accessible (3 boutons géants)
│   │       ├── profile/      # Profil utilisateur
│   │       └── settings/     # Paramètres
│   └── pubspec.yaml
│
└── README.md
```

---

## 🚀 Démarrage rapide

### Prérequis
- Node.js 20+
- PostgreSQL (Neon serverless fourni)
- Flutter 3.24+ / Dart 3.5+
- Android Studio ou Xcode

### 1. Backend

```bash
cd backend

# Copier et configurer l'environnement
cp .env.example .env
# Éditer .env avec tes variables (DATABASE_URL Neon, JWT secrets, etc.)

# Installer les dépendances
npm install

# Générer le client Prisma
npx prisma generate

# Appliquer le schéma à la BDD
npx prisma db push

# (Optionnel) Seeder des données de démo
npm run db:seed

# Démarrer le serveur (port 3001)
npm run dev
```

**Compte démo :** `demo@lifehelm.app` / `lifehelm123`

### 2. Mobile (Flutter)

```bash
cd mobile

# Installer les dépendances
flutter pub get

# Générer les fichiers générés (freezed, retrofit, drift, riverpod)
dart run build_runner build --delete-conflicting-outputs

# Lancer sur émulateur Android (le backend doit tourner sur localhost:3001)
flutter run

# Pour iOS
flutter run -d ios
```

**Configuration API :**
- Émulateur Android : `http://10.0.2.2:3001/api` (défaut)
- Simulateur iOS : `http://127.0.0.1:3001/api`
- Device physique : `http://<IP-LAN>:3001/api`

Pour changer l'URL : `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3001/api`

---

## 🗄️ Base de données

**PostgreSQL sur Neon** (serverless, EU-Central)

- 25 tables : users, accounts, transactions, budgets, savings_goals, tontines, tontine_members, debts, debt_payments, bills, bill_history, life_goals, goal_projects, goal_tasks, goal_journal, habits, habit_logs, morning_rituals, evening_reviews, sleep_logs, mood_logs, workout_logs, hydration_logs, ai_conversations, ai_messages, ai_insights, daily_boutique_logs, client_ardoises, ardoise_entries, supplier_credits, career_profiles, contacts, sessions, refresh_tokens, user_settings
- 21 enums : Plan, AccountType, TransactionType, BudgetMethod, DebtStrategy, DebtDirection, BillStatus, LifeDomain, GoalType, GoalStatus, GoalPriority, TaskStatus, HabitFrequency, HabitType, Mood, ContactCircle, AiRole, InsightType, InsightSeverity, AppLanguage, AppMode

Le schéma est dans `backend/prisma/schema.prisma`. Pour le modifier :
```bash
cd backend
npx prisma db push   # Applique les changements
npx prisma generate  # Régénère le client
```

---

## 🔐 Sécurité

- Mots de passe hachés (bcrypt, cost 12)
- JWT access tokens (15 min) + refresh tokens (7 jours, rotation)
- Rate limiting global (100 req/min) et auth (5 tentatives/15min)
- Helmet pour les headers HTTP sécurisés
- CORS configurable
- Validation Zod sur toutes les entrées

---

## 🌍 i18n — Langues supportées

| Code | Langue | Statut V1 |
|------|--------|-----------|
| `FR` | Français | ✅ Complet |
| `FON` | Fon (Fongbé) | 🚧 Partiel |
| `BARIBA` | Bariba (Baatonum) | 🚧 Partiel |
| `YORUBA` | Yoruba | 🚧 Partiel |

Les traductions sont dans `mobile/assets/translations/`.

---

## 🎨 Design

**Palette africaine moderne :**
- Indigo profond (gouvernail) — primaire
- Orange FCFA / coucher de soleil — accent
- Terre, sable, kente (jaune, vert, rouge) — touches culturelles
- Sable clair — fond
- Material 3 + Google Fonts (Inter)

Chaque pilier a sa couleur :
- 💚 Finance — vert émeraude
- 💜 Objectifs — violet
- 💙 Routines — bleu
- ❤️ Santé — corail
- 🧡 Carrière — ambre
- 💗 Relations — rose

---

## 📚 Documentation

- **Cahier des charges complet** : `LifeHelm-CDC-v1.0.docx` (fourni par l'auteur)
- **API endpoints** : voir `backend/src/routes/` (toutes les routes sont documentées dans le code)
- **Schéma BDD** : `backend/prisma/schema.prisma`

---

## 🛣️ Roadmap V2

- [ ] Sync offline-first complète (SQLite + Dio interceptors)
- [ ] Notifications push (Firebase FCM)
- [ ] Intégration Claude API pour HELM AI (insights avancés)
- [ ] Import SMS Mobile Money (Africa's Talking)
- [ ] Paiement FedaPay (Mobile Money + carte) pour plan Pro/Family
- [ ] Mode Famille (jusqu'à 5 membres)
- [ ] Google Calendar sync
- [ ] Export PDF (rapports mensuels/annuels)
- [ ] Saisie vocale (STT) en Mode Accessible
- [ ] Guidage audio TTS en langues locales
- [ ] Traductions complètes Dendi, Goun, Adja, Ewé, Tem

---

## 👤 Auteur

**Sènakpon · YEHI OR Tech**

LifeHelm v1.0 · 2025

Confidentiel — Ne pas diffuser sans autorisation.

---

## 📄 Licence

Propriétaire — Tous droits réservés.
