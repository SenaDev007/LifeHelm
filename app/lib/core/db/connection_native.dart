import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Connexion SQLite native (Android / iOS / desktop) — CDC D01.4.
/// `createInBackground` exécute SQLite sur un isolate dédié (fluidité UI).
QueryExecutor connect() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lifehelm.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
