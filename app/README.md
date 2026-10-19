# LifeHelm — Application Flutter

> **Life Management System** unifié — implémentation Flutter offline-first des Dossiers 01 à 14 du cahier des charges.

**Version :** 0.1.0 (MVP local) · **Flutter :** 3.47.7 · **Dart :** 3.13.5

---

## 🚀 Lancer le projet

```bash
# Prérequis : Flutter SDK 3.47+ (https://docs.flutter.dev/get-started/install)
flutter pub get

# Générer le schéma Drift (déjà généré — seulement après modification de tables.dart)
dart run build_runner build --delete-conflicting-outputs

# Lancer sur un appareil/émulateur Android ou iOS
flutter run

# Build web (preview navigateur — vraie base SQLite via WASM)
flutter build web --release
```

> **Preview web :** le build embarque `sqlite3.wasm` + `drift_worker.js` (dossier `web/`) — l'application
> utilise la **même base SQLite** que sur mobile, persistée dans le navigateur (IndexedDB).

## 🏗️ Architecture

```
lib/
├── main.dart                  # Amorçage : DB, locale fr, scan de maintenance
├── app.dart                   # MaterialApp.router + thèmes clair/sombre/système
├── router.dart                # go_router — 5 onglets + ~35 routes modules
├── core/
│   ├── db/
│   │   ├── tables.dart        # ~60 tables Drift (Dossiers 01→14)
│   │   ├── database.dart      # AppDatabase, file de sync, notifications, espaces
│   │   ├── seed.dart          # Fondations par espace + données de démo
│   │   └── connection_*.dart  # SQLite natif (mobile) / WASM (web)
│   ├── providers.dart         # Riverpod : espace actif, réglages, cockpit
│   ├── theme/                 # Tokens noir/or/émeraude + thèmes (CDC §4)
│   ├── utils/                 # Money (XOF, unités mineures), dates civiles fr
│   └── widgets/common.dart    # LHCard, StatusChip, ProgressRing, BudgetBar…
├── shell/                     # Bottom nav 5 destinations + LhAppBar transversal
└── features/                  # 1 dossier par dossier du CDC
    ├── onboarding/            # 3 écrans + création des 3 espaces
    ├── cockpit/               # D02 : sections configurables, priorités hybrides
    ├── tasks/                 # D03 : 5 statuts, sous-tâches, dépendances, récurrences
    ├── agenda/                # D04 : jour/semaine/mois, invitations, reports
    ├── finance/               # D05 : comptes, transactions, budgets, échéances
    ├── notes/                 # D06 : éditeur par blocs, versions, corbeille
    ├── projects/              # D07 : étapes/jalons, objectifs & indicateurs
    ├── habits/                # D08 : occurrences, séries, routines
    ├── wellbeing/             # D09 : journal, bilan quotidien guidé
    ├── career/                # D10 : compétences, parcours, certifications
    ├── contacts/              # D11 : personnes/organisations, interactions
    ├── messaging/             # D12 : conversations, accusés, simulation
    ├── notifications/         # D13 : centre, priorités, plages silencieuses
    ├── search/                # D14 : recherche multi-modules + filtres
    └── more/                  # Plus : modules, paramètres, espaces, sync
```

**Stack :** Flutter · Riverpod 2 · go_router · Drift (SQLite) · intl (fr) — aucun backend requis.

## 📋 Couverture du CDC

| Dossier | Module | Statut MVP local |
|---|---|---|
| 01 | Fondations : espaces, sync offline, design system | ✅ 3 espaces isolés, file d'opérations journalisée, tokens noir/or/émeraude |
| 02 | Cockpit | ✅ Sections configurables, priorités hybrides, résumé du jour |
| 03 | Tâches | ✅ 5 statuts, archivage distinct, sous-tâches, dépendances (cycles interdits), récurrences à occurrences indépendantes, assignation multiple |
| 04 | Agenda | ✅ Jour/semaine/mois, récurrences + exceptions, invitations, chevauchements signalés non bloquants, report avec historique |
| 05 | Finances | ✅ Solde initial + POSTED/PENDING, transferts ≠ revenus/dépenses, multi-devises avec taux conservés, budgets E=B+A+R / S=E−D, seuil 80 % réglable, échéances, rapprochement avec écart explicite |
| 06 | Notes | ✅ Éditeur par blocs, dossiers hiérarchiques, versions + restauration (jamais destructive), corbeille 30 j |
| 07 | Projets & objectifs | ✅ Étapes ≠ jalons, progression calculée + ajustement manuel traçable, indicateurs multiples, historique |
| 08 | Habitudes | ✅ Binaire & quantitatif, manquée ≠ ignorée, séries tolérantes aux repos, routines liées aux habitudes |
| 09 | Bien-être | ✅ Journal privé, bilan guidé, absente ≠ zéro |
| 10 | Carrière | ✅ Compétences (autoévaluée/preuvée/certifiée), parcours, expériences, certifications (déclarée/justificatif/vérifiée) |
| 11 | Contacts | ✅ Personnes/organisations, carnets par espace, interactions manuelles uniquement |
| 12 | Messagerie | ✅ Conversations internes simulées, statuts fidèles (pending→read), réactions, mentions, accusés configurables, modification < 15 min |
| 13 | Notifications | ✅ 4 priorités, déduplication, snooze, plages silencieuses, préférences par catégorie, archivage/restauration |
| 14 | Recherche | ✅ Multi-modules avec filtres, suggestions debouncées, espace actif par défaut, historique |

**Transverse :** chaque mutation métier appelle `logOp()` → file `SyncOperations` (identifiants stables, prêts pour l'API NestJS `POST /api/v1/sync/operations` du D01.4). Écran **Plus → Synchronisation** pour visualiser la file et simuler un cycle.

## ⚖️ Arbitrages proposés (à confirmer)

Ces choix sont marqués « proposé » conformément aux règles de gouvernance du dossier maître :

1. **Formule du classement hybride** (D02) : priorité pondérée (URGENT 50 / HIGH 35 / NORMAL 20 / LOW 10) + bonus échéance (retard +40+, jour +30, ≤2 j +18, fenêtre +8) + en cours +6.
2. **Rétention corbeille Notes** : 30 jours (purge automatique au démarrage).
3. **Délai de modification des messages** : 15 minutes (D12).
4. **Séries d'habitudes** : SKIPPED et jours non programmés ne cassent pas la série ; MISSED la casse.
5. **Taux de conversion indicatifs** : affichage des soldes non-XOF (EUR 655,957…) — remplacés par les taux réels des transferts dès qu'ils existent.
6. **Notifications push système** : non incluses dans ce MVP local (aucune dépendance plugin) — le centre intégré est complet ; le branchement `flutter_local_notifications`/FCM est prévu côté intégration native.

## 🎨 Design system

Palette (CDC §4.1) : noir profond `#101010` · or champagne `#C6A85B` · émeraude `#087F5B` · ivoire `#F7F5EF` —
thème sombre premium par défaut, bascule clair/sombre/système dans **Paramètres**.
Polices bundlées : **Manrope** (titres) + **Inter** (texte) — aucune dépendance réseau.

## ✅ Tests

```bash
flutter test   # 4 tests : calcul des soldes, budgets, allocations, régression LHCard
```

Vérifiés : soldes exacts des comptes seedés (24 500 / 378 400 / 1 510 000 / 1 350 000 FCFA),
enveloppes budgétaires (E = 100 000, D = 26 000), rendu des cartes en hauteur non bornée.

## 🔜 Prochaines étapes (hors périmètre de ce livrable)

- Backend NestJS + PostgreSQL/Prisma (API versionnée `/api/v1`, OpenAPI)
- Authentification D01.3 (courriel/téléphone, 2FA, rotation des jetons)
- Synchronisation réelle (upload de la file, curseur de changements, conflits par type de ressource)
- Notifications système (push + planificateur local)
- OCR / recherche sémantique (D06/D14 — traitement asynchrone serveur)
- HELM AI (gouvernance à documenter avant intégration — CDC §2.4)
