import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'core/providers.dart';

/// État d'amorçage global — rempli avant `runApp`.
final bootState = BootState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');

  // Ouverture de la base locale avant le rendu (offline-first).
  final db = AppDatabase();
  bootState.onboarded = await db.isOnboarded();
  if (bootState.onboarded) {
    // Purge unique des données de démonstration (installations antérieures).
    await db.purgeDemoDataOnce();
    await db.maintenanceScan();
    await db.purgeExpired();
  }

  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const LifeHelmApp(),
  ));
}

class BootState {
  bool onboarded = false;
}
