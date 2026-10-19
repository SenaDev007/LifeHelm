# LifeHelm — Votre vie, un seul gouvernail.

**Life Management System** complet pour le marché africain francophone : tâches, agenda, finances XOF (espèces, banque, Mobile Money), notes, projets, habitudes, bien-être, carrière, contacts et messagerie — avec **authentification** et **synchronisation multi-appareils hors ligne d'abord**.

Application **Flutter** (Android · iOS · Web) + API **NestJS** + **PostgreSQL** (Neon), conçue pour des connexions intermittentes et des revenus irréguliers.

---

## Vue d'ensemble du monorepo

```
LifeHelm/
├── app/                  # Application Flutter (offline-first, 14 modules)
│   ├── lib/
│   │   ├── core/         # db (Drift ~60 tables), net (API + sync), theme, widgets
│   │   ├── features/     # 15 modules : onboarding, cockpit, tasks, agenda,
│   │   │                 # finance, notes, projects, habits, wellbeing, career,
│   │   │                 # contacts, messaging, notifications, search, more/auth
│   │   ├── shell/        # Navigation 5 onglets (Accueil, Activités, Agenda, Finances, Plus)
│   │   ├── router.dart   # ~45 routes (go_router)
│   │   └── main.dart
│   ├── assets/           # Polices Manrope/Inter, SQLite WASM (web)
│   ├── android/ ios/ web/
│   └── pubspec.yaml
├── backend/              # API NestJS (auth JWT + 2FA + synchronisation)
│   ├── prisma/schema.prisma   # User, Session, Resource, SyncChange, AppliedOp
│   ├── src/
│   │   ├── auth/         # register/login/refresh/logout, sessions, 2FA TOTP,
│   │   │                 # mot de passe (changement, oubli, réinitialisation)
│   │   ├── sync/         # push idempotent + pull par curseur + conflits explicites
│   │   ├── common/       # guards (JWT + throttle), filtres d'erreurs
│   │   └── prisma/       # PrismaService
│   ├── scripts/          # smoke.js (48 tests E2E), verify_e2e.js, neon_reset.js
│   └── .env.example      # configuration (jamais le vrai .env dans git)
└── README.md
```

---

## Démarrage rapide

### 1. Backend (NestJS + Prisma + PostgreSQL)

```bash
cd backend
npm install

# Configuration
cp .env.example .env
# Éditer .env : DATABASE_URL + DIRECT_URL (Neon), JWT_ACCESS_SECRET
# (secret fort : node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")

npx prisma generate
npx prisma db push          # crée les tables (User, Session, Resource, SyncChange, AppliedOp)

npm run build
npm start                    # API sur http://localhost:3001/api/v1
```

**Vérifier** : `curl http://localhost:3001/api/v1/health` → `{"status":"ok","database":"up"}`

**Tests E2E complets (48 assertions)** : `node scripts/smoke.js`

### 2. Application Flutter

```bash
cd app
flutter pub get
flutter run                  # Android / iOS / desktop
# ou
flutter run -d chrome        # web
flutter build web --release  # build de production
```

L'application fonctionne **100 % hors ligne sans compte**. Pour activer la synchronisation :
- à la fin de l'onboarding → *« Créer un compte »* ; ou
- onglet **Plus → Compte & synchronisation → Activer la synchronisation**.

L'URL du serveur se règle dans **Plus → Paramètres → URL du serveur** (défaut `/api/v1` — même origine que le build web ; sur mobile, mettre l'URL complète, ex. `https://api.example.com/api/v1`).

### 3. Preview web avec API (même origine)

Depuis la racine du repo (build web préalable : `cd app && flutter build web --release`) :

```bash
node scripts/preview_server.js app/build/web 3000   # sert l'app + proxy /api → :3001
```

---

## Authentification (D01.3)

| Fonction | Détail |
|---|---|
| Inscription | courriel **ou** téléphone (au moins un), prénom requis |
| Connexion | identifiant courriel **ou** téléphone + mot de passe |
| Mots de passe | bcrypt (10 tours), min. 8 caractères |
| Jeton d'accès | JWT HS256, **15 min** |
| Session | refresh token opaque (48 octets, hashé sha256 en base), **30 j glissants** |
| Rotation | à chaque renouvellement, l'ancien jeton est révoqué |
| **Détection de rejeu** | réutiliser un refresh token tourné ⇒ **toute la famille de sessions est révoquée** |
| Révocation effective | chaque requête vérifie l'état de la session en base (logout / logout-all / changement de mot de passe immédiats) |
| **2FA TOTP** | RFC 6238 (30 s, 6 chiffres, fenêtre ±1), compatible Google Authenticator — activation : Plus → Sécurité & 2FA |
| Sessions | liste des appareils (nom, IP, dernière utilisation), révocation individuelle ou globale |
| Mot de passe oublié | jeton 30 min hashé, réponse 202 anti-énumération ; en dev le jeton est renvoyé dans la réponse (`devResetToken`) |
| Vérification courriel/téléphone | code 6 chiffres hashé, 24 h ; en dev le code est renvoyé (`devVerificationCode`) |
| Anti-bruteforce | garde en mémoire (15 login/min, 10 register/min, 5 forgot/min) |

### Endpoints `/api/v1/auth`

```
POST /auth/register            { email?|phone?, password, firstName, lastName?, deviceName? }
POST /auth/login               { identifier, password, totpCode?, deviceName? }
POST /auth/refresh             { refreshToken }              — rotation + anti-rejeu
POST /auth/logout              { refreshToken }
POST /auth/logout-all          [Bearer]
GET  /auth/me                  [Bearer]
GET  /auth/sessions            [Bearer] — appareils connectés
DELETE /auth/sessions/:id      [Bearer]
POST /auth/password            { currentPassword, newPassword }   [Bearer]
POST /auth/password/forgot     { identifier } → 202
POST /auth/password/reset      { resetToken, newPassword }
POST /auth/2fa/setup|enable|disable   { totpCode }  [Bearer]
POST /auth/verify-email|phone  { code }             [Bearer]
```

Codes d'erreur métier : `EMAIL_TAKEN`, `PHONE_TAKEN`, `CONTACT_REQUIRED`, `INVALID_CREDENTIALS`, `TOTP_REQUIRED` (HTTP 428), `TOTP_INVALID`, `TOKEN_REUSED`, `RATE_LIMITED`…

---

## Synchronisation (D01.4) — hors ligne d'abord

### Principe

1. **Toute mutation locale** est écrite dans SQLite (Drift) **et** journalisée dans la queue persistante `SyncOperations` (`logOp`).
2. Le **SyncService** pousse les opérations par lots de 100 (dédupliquées par ressource, snapshot complet relu de la base).
3. Le serveur applique chaque opération de façon **idempotente** (clé `opId`), journalise dans `SyncChange` (curseur séquentiel) et versionne la ressource.
4. Le **pull** ramène les changements d'autres appareils depuis le curseur du device (upsert local Drift, sans écraser les ressources ayant des opérations locales en attente).
5. Déclencheurs : après mutation (debounce 5 s), timer 5 min, ouverture d'app, bouton manuel.

### Endpoints `/api/v1/sync` (Bearer)

```
POST /sync/operations   { deviceId, operations: [ { opId, resourceType, resourceId,
                         op: CREATE|UPDATE|DELETE, occurredAt, data? } ] }
→  { results: [ { opId, status: APPLIED|DUPLICATE|CONFLICT|REJECTED, serverVersion?, reason? } ], serverSeq }

GET /sync/changes?cursor=0&limit=200
→  { changes: [ { seq, resourceType, resourceId, op, data, deleted, version, updatedAt } ],
     nextCursor, hasMore }

GET /sync/status   →  { serverSeq, resourceCount, lastChangeAt }
```

### Conflits explicites — pas de « dernière écriture gagnante » universelle

- **Types sensibles** (transactions financières, transferts, allocations, ajustements, rapprochements, échéances, notes, versions de notes) : si un **autre appareil** a modifié la ressource **plus récemment** avec des **données divergentes**, l'opération revient `CONFLICT` — résolution **explicite** dans l'écran Synchronisation : *« Garder ma version »* (re-push forcé) ou *« Prendre la version serveur »*.
- **Autres types** : last-arrival-wins documenté (ordre de la queue = chronologie des mutations).
- Les suppressions sont des tombstones serveur (récupérables), jamais un écrasement silencieux.

### Couverture

~50 types de ressources synchronisés : espaces, membres, règles de récurrence, listes/tâches/dépendances, calendriers/événements/exceptions, comptes/catégories/transactions/transferts/allocations/budgets (ajustements, reports, échéances, rapprochements), dossiers/notes/versions, projets (membres, étapes, jalons, liens)/objectifs (indicateurs, historique, liens), habitudes (planifications, occurrences)/routines (étapes, exécutions), bien-être (journal, bilans), carrière (profil, compétences, parcours, expériences, certifications, portfolio), contacts (coordonnées, interactions, liens), messagerie (conversations, membres, messages, réactions).

Sont **volontairement locaux** (par appareil) : notifications, préférences de notification, recherches récentes, réglages.

---

## Base de données (Neon PostgreSQL)

Schéma Prisma (`backend/prisma/schema.prisma`) :

| Table | Rôle |
|---|---|
| `User` | comptes (courriel/téléphone uniques, hash bcrypt, 2FA, codes de vérification) |
| `Session` | sessions par appareil — familles de rotation, hash du refresh token, révocation |
| `Resource` | source de vérité générique : une ligne par entité (id client stable, `type`, `data` JSONB, `version`, `deviceId`, tombstone `deletedAt`) |
| `SyncChange` | journal des modifications (séquence `BigInt` auto-incrémentée = curseur de pull) |
| `AppliedOp` | idempotence par `opId` (rétention 90 j, purge automatique possible) |

---

## Design

Noir profond `#101010` · or champagne `#C6A85B` · émeraude `#087F5B` · ivoire `#F7F5EF` — thème sombre et clair avec bascule, typographies **Manrope** (titres) et **Inter** (texte), montants en **FCFA (XOF)** avec gestion multi-devises, tout en français.

## Architecture applicative

- **Offline-first** : SQLite local (Drift) = source de vérité immédiate ; le serveur devient l'autorité pour les données partagées multi-appareils.
- **Riverpod 2** (état réactif) + **go_router** (~45 routes).
- Modules découplés (`features/<module>/`), un fichier autonome par domaine.
- Secrets de session mobiles dans **flutter_secure_storage** (web : `shared_preferences`, pas de stockage sécurisé natif).
- `SyncOperations`, `Settings`, `RecentSearches` : tables techniques locales jamais synchronisées.

## Limites connues & roadmap

1. **Second appareil avec seed local** : chaque installation crée ses espaces par défaut à l'onboarding ; se connecter ensuite sur un appareil déjà utilisé fusionne les espaces (doublons possibles). Amélioration prévue : choix *« Adopter les données du serveur / Conserver cet appareil »* au premier login.
2. **Vérification courriel/SMS** : les codes sont renvoyés dans la réponse en mode dev ; brancher un fournisseur (Resend/Twilio) pour la production.
3. **Messagerie** : les accusés/réponses restent simulés localement ; le temps réel (WebSocket) et les invitations d'espaces par code viendront avec le partage multi-comptes.
4. **Documents & pièces jointes** (D06) et **import/export** (D15) : tables présentes, UI à venir.
5. **Rate limiting** en mémoire (mono-instance) : passer à Redis en production.

## Tests

- **Backend** : `node scripts/smoke.js` — 48 assertions E2E (inscription, connexion, 2FA, rotation + rejeu, sessions, push idempotent, conflit explicite financier, tombstones, pagination curseur, mots de passe, déconnexions).
- **App** : `flutter test` — round-trip du registre de synchronisation (Drift `toJson` → `companionFromJson`), queue `logOp`, purge 7 jours, client API (erreurs typées, refresh + retry, session expirée), soldes/budgets financiers, widgets.

---

**Stack** : Flutter 3.x · Dart 3 · Riverpod 2 · go_router · Drift (SQLite) · NestJS 11 · Prisma 6 · PostgreSQL (Neon) · JWT · bcrypt · TOTP
