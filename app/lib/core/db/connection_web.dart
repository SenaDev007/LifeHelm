import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Connexion SQLite WASM pour la preview web — la MÊME base SQLite que sur
/// mobile, exécutée dans un web worker (drift_worker.js + sqlite3.wasm),
/// persistée via IndexedDB. Fidèle au principe offline-first du CDC.
QueryExecutor connect() {
  return DatabaseConnection.delayed(Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'lifehelm',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    if (result.missingFeatures.isNotEmpty) {
      // Pas d'OPFS : repli automatique sur IndexedDB — fonctionnel.
    }
    return result.resolvedExecutor;
  }));
}
