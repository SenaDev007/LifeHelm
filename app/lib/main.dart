import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'core/providers.dart';
import 'core/widgets/error_shield.dart';

/// État d'amorçage global — rempli avant `runApp`.
final bootState = BootState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bouclier anti-crash : écran de récupération propre (jamais la page
  // grise « package:flutter … ») + erreurs asynchrones loguées sans crash.
  ErrorShield.install();

  await initializeDateFormatting('fr');

  // Ouverture de la base locale avant le rendu (offline-first).
  final db = AppDatabase();
  bootState.onboarded = await db.isOnboarded();
  if (bootState.onboarded) {
    // Purge unique des données de démonstration (installations antérieures).
    await db.purgeDemoDataOnce();
    await db.maintenanceScan();
    await db.purgeExpired();
    // Montée de version de la taxonomie financière (idempotent) : les
    // installations existantes reçoivent les catégories & sous-catégories
    // exhaustives sans toucher aux données existantes.
    await db.ensureTaxonomy();
    // Comptes types pour les espaces qui n'en ont encore aucun (idempotent) :
    // sans compte, la saisie d'opération est impossible (sélecteurs grisés).
    await db.ensureDefaultAccounts();
  }

  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const LifeHelmApp(),
  ));
}

class BootState {
  bool onboarded = false;
}
