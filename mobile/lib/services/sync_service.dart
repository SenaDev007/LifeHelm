// V2 — Sync Service : orchestre la synchronisation offline → online
// - Push les entités modifiées offline vers le serveur
// - Pull les modifications serveur vers SQLite
// - Se déclenche quand le réseau revient (connectivity_plus)

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'app_database.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref);
});

enum SyncStatus { idle, pushing, pulling, done, error, offline }

class SyncService {
  SyncService(this._ref);

  final Ref _ref;
  final _statusController = StreamController<SyncStatus>.broadcast();
  final _progressController = StreamController<String>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<String> get progressStream => _progressController.stream;

  SyncStatus _currentStatus = SyncStatus.idle;
  SyncStatus get currentStatus => _currentStatus;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      // connectivity_plus >= 6 retourne une liste
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      if (result != ConnectivityResult.none && _currentStatus == SyncStatus.offline) {
        sync();
      }
    });
    // Vérifie l'état initial
    Connectivity().checkConnectivity().then((r) {
      final result = r.isNotEmpty ? r.first : ConnectivityResult.none;
      if (result == ConnectivityResult.none) {
        _setStatus(SyncStatus.offline);
      }
    });
  }

  void stopListening() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> sync({bool force = false}) async {
    if (_isSyncing) return;

    // Vérifier connectivité
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      _setStatus(SyncStatus.offline);
      return;
    }

    _isSyncing = true;
    try {
      // 1. Push les entités non synchronisées
      _setStatus(SyncStatus.pushing);
      _progress.add('Envoi des données en attente…');
      await _pushPending();

      // 2. Pull les modifications serveur
      _setStatus(SyncStatus.pulling);
      _progress.add('Récupération des dernières données…');
      await _pullServer(force: force);

      await AppDatabase.instance.setLastSync(DateTime.now());
      _setStatus(SyncStatus.done);
      _progress.add('Synchronisé');
    } catch (e) {
      debugPrint('[Sync] Erreur: $e');
      _setStatus(SyncStatus.error);
      _progress.add('Erreur: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pushPending() async {
    final dio = _ref.read(dioProvider);
    final db = AppDatabase.instance;

    final items = <Map<String, dynamic>>[];

    // Transactions
    final txs = await db.getUnsyncedTransactions();
    for (final tx in txs) {
      items.add({
        'entityType': 'TRANSACTION',
        'entityId': tx['id'],
        'operation': tx['operation'] ?? 'CREATE',
        'payload': {
          'id': tx['id'],
          'accountId': tx['account_id'],
          'type': tx['type'],
          'amount': tx['amount'],
          'category': tx['category'],
          'label': tx['label'],
          'note': tx['note'],
          'date': DateTime.fromMillisecondsSinceEpoch(tx['date'] as int).toIso8601String(),
        },
      });
    }

    // Habits
    final habits = await db.getUnsyncedHabits();
    for (final h in habits) {
      items.add({
        'entityType': 'HABIT',
        'entityId': h['id'],
        'operation': h['operation'] ?? 'CREATE',
        'payload': {
          'id': h['id'],
          'name': h['name'],
          'description': h['description'],
          'type': h['type'],
          'frequency': h['frequency'],
          'targetValue': h['target_value'],
          'unit': h['unit'],
          'color': h['color'],
        },
      });
    }

    if (items.isEmpty) return;

    try {
      final r = await dio.post('/sync/push', data: {'items': items});
      final results = (r.data['results'] as List?) ?? [];

      // Marquer comme synchronisés ceux qui ont réussi
      for (final result in results) {
        if (result['success'] == true) {
          final entityId = result['entityId'] as String;
          await db.markTransactionSynced(entityId);
          // TODO: marquer autres types
        }
      }
    } catch (e) {
      debugPrint('[Sync] Push error: $e');
      // On continue quand même sur le pull
    }
  }

  Future<void> _pullServer({bool force = false}) async {
    final dio = _ref.read(dioProvider);
    final db = AppDatabase.instance;

    final lastSync = force ? null : await db.getLastSync();
    final since = lastSync?.toIso8601String() ??
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    try {
      final r = await dio.get('/sync/pull', queryParameters: {'since': since});
      final entities = r.data['entities'] as Map<String, dynamic>?;

      if (entities == null) return;

      // Accounts
      final accounts = entities['accounts'] as List? ?? [];
      for (final a in accounts) {
        await db.upsertAccount(a as Map<String, dynamic>);
      }

      // Transactions
      final transactions = entities['transactions'] as List? ?? [];
      for (final t in transactions) {
        await db.upsertTransaction(t as Map<String, dynamic>, synced: true);
      }

      // Habits
      final habits = entities['habits'] as List? ?? [];
      for (final h in habits) {
        await db.upsertHabit(h as Map<String, dynamic>, synced: true);
      }

      // Habit logs
      final habitLogs = entities['habitLogs'] as List? ?? [];
      for (final l in habitLogs) {
        await db.upsertHabitLog(l as Map<String, dynamic>, synced: true);
      }

      // Sleep logs
      final sleepLogs = entities['sleepLogs'] as List? ?? [];
      for (final l in sleepLogs) {
        await db.upsertSleepLog(l as Map<String, dynamic>, synced: true);
      }

      // Mood logs
      final moodLogs = entities['moodLogs'] as List? ?? [];
      for (final l in moodLogs) {
        await db.upsertMoodLog(l as Map<String, dynamic>, synced: true);
      }

      // Workout logs
      final workoutLogs = entities['workoutLogs'] as List? ?? [];
      for (final l in workoutLogs) {
        await db.upsertWorkoutLog(l as Map<String, dynamic>, synced: true);
      }

      // Hydration logs
      final hydrationLogs = entities['hydrationLogs'] as List? ?? [];
      for (final l in hydrationLogs) {
        await db.upsertHydrationLog(l as Map<String, dynamic>, synced: true);
      }

      // Boutique logs
      final boutiqueLogs = entities['boutiqueLogs'] as List? ?? [];
      for (final l in boutiqueLogs) {
        await db.upsertBoutiqueLog(l as Map<String, dynamic>, synced: true);
      }

      debugPrint('[Sync] Pull OK: ${accounts.length} accounts, ${transactions.length} txs, ${habits.length} habits');
    } catch (e) {
      debugPrint('[Sync] Pull error: $e');
      rethrow;
    }
  }

  void _setStatus(SyncStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    stopListening();
    _statusController.close();
    _progressController.close();
  }
}

// Extension pour accéder facilement au _progress
extension on SyncService {
  StreamController<String> get _progress => _progressController;
}
