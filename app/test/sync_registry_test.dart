import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/net/api_client.dart' show tokenStoreProvider;
import 'package:lifehelm/core/net/sync_service.dart';
import 'package:lifehelm/core/net/token_store.dart';
import 'package:lifehelm/core/providers.dart';

/// Tests du registre de synchronisation (D01.4) :
/// - couverture exhaustive des resourceType annoncés ;
/// - exclusion des tables locales à l'appareil ;
/// - round-trip JSON (toJson → companion → insertOnConflictUpdate) ;
/// - table auxiliaire goal_project_links (SQL brut) via le SyncController.
void main() {
  late AppDatabase db;

  /// Les 54 types synchronisables (le 55e, GoalProjectLink, est porté par la
  /// table auxiliaire SQL brut et testé séparément).
  const expectedTypes = <String>{
    // D01
    'Space', 'SpaceMember', 'RecurrenceRule',
    // D03
    'TaskList', 'Task', 'TaskDependency',
    // D04
    'Calendar', 'CalendarEvent', 'EventException',
    // D05
    'FinancialAccount', 'FinancialCategory', 'FinancialTransaction',
    'Transfer', 'TransactionAllocation', 'Budget', 'BudgetAdjustment',
    'BudgetCarryover', 'FinancialDueItem', 'AccountReconciliation',
    // D06
    'Folder', 'Note', 'NoteVersion',
    // D07
    'Project', 'ProjectMember', 'ProjectStage', 'ProjectMilestone',
    'ProjectTaskLink', 'Goal', 'GoalMetric', 'GoalProgressEntry',
    // D08
    'Habit', 'HabitSchedule', 'HabitOccurrence', 'Routine', 'RoutineStep',
    'RoutineOccurrence',
    // D09
    'WellbeingEntry', 'DailyReview',
    // D10
    'CareerProfile', 'Skill', 'UserSkill', 'LearningPath',
    'LearningPathStep', 'ProfessionalExperience', 'Certification',
    'PortfolioItem',
    // D11
    'Contact', 'ContactPoint', 'ContactInteraction', 'ContactLink',
    // D12
    'Conversation', 'ConversationMember', 'Message', 'MessageReaction',
  };

  /// Types volontairement EXCLUS (device-local, jamais envoyés au serveur).
  const excludedTypes = <String>{
    'Notification', 'NotificationPref', 'RecentSearches', 'SyncOperations',
    'Settings', 'TaskAssignee', 'EventParticipant', 'Documents',
    'AttachmentLinks', 'ReflectionQuestions',
  };

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    await db.seedDemoData();
  });

  tearDown(() async => db.close());

  test('registre : couverture exacte des resourceType annoncés', () {
    final registry = buildSyncRegistry(db);
    expect(registry.keys.toSet(), expectedTypes,
        reason: 'Le registre doit contenir exactement les types annoncés.');
    // Aucune table device ne doit figurer dans le registre.
    for (final excluded in excludedTypes) {
      expect(registry.containsKey(excluded), isFalse,
          reason: '$excluded est une table locale, exclue de la sync.');
    }
  });

  test('registre : chaque type map vers une table existante avec colonne id',
      () {
    final registry = buildSyncRegistry(db);
    for (final entry in registry.entries) {
      expect(entry.value.table, isNotNull, reason: entry.key);
      expect(entry.value.table.columnsByName.containsKey('id'), isTrue,
          reason:
              '${entry.key} : la table doit exposer une colonne id (UUID stable).');
    }
  });

  test('round-trip toJson → companion → insertOnConflictUpdate (idempotence)',
      () async {
    final registry = buildSyncRegistry(db);
    // Types demandés + échantillon représentatif de chaque dossier.
    const types = [
      'Task', // D03
      'Note', // D06
      'FinancialTransaction', // D05
      'Habit', // D08
      'Message', // D12
      'Space', 'RecurrenceRule', 'TaskList', 'Calendar', 'CalendarEvent',
      'FinancialAccount', 'FinancialCategory', 'Budget', 'Transfer',
      'Folder', 'Project', 'Goal', 'Contact', 'Conversation',
      'Routine', 'WellbeingEntry', 'Skill', 'Certification',
      'ContactInteraction', 'GoalProgressEntry',
    ];
    for (final type in types) {
      final t = registry[type]!;
      final rows = await (db.select(t.table)).get();
      expect(rows, isNotEmpty,
          reason: '$type : aucune ligne d\'exemple (données de démo ?)');
      final row = rows.first;
      final json = row.toJson();

      // 1. toJson → companion complet (nulls inclus).
      final companion = t.fromJson(Map<String, dynamic>.from(json));
      // 2. upsert : la ligne existe déjà → ON CONFLICT DO UPDATE.
      await db.into(t.table).insertOnConflictUpdate(companion);
      // 3. relecture : l'état doit être identique bit à bit.
      final idCol = t.table.columnsByName['id']!;
      final reread = await (db.select(t.table)
            ..where((tbl) => idCol.equals(json['id'] as String)))
          .getSingle();
      expect(reread.toJson(), json,
          reason:
              '$type : le round-trip JSON doit préserver tous les champs.');
    }
  });

  test('goal_project_links (table auxiliaire SQL brut) : lecture/upsert/delete',
      () async {
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      tokenStoreProvider
          .overrideWithValue(TokenStore(backend: MemoryTokenBackend())),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(syncControllerProvider);

    // Absente → snapshot null (sera poussée comme DELETE).
    expect(await controller.readSnapshot('GoalProjectLink', 'gpl_x'),
        isNull);

    // Upsert depuis le JSON serveur puis relecture.
    await controller.upsertLocal('GoalProjectLink',
        {'id': 'gpl_1', 'goalId': 'g1', 'projectId': 'p1'});
    final snap = await controller.readSnapshot('GoalProjectLink', 'gpl_1');
    expect(snap,
        {'id': 'gpl_1', 'goalId': 'g1', 'projectId': 'p1'});

    // Round-trip JSON idempotent.
    await controller.upsertLocal(
        'GoalProjectLink', Map<String, dynamic>.from(snap!));
    expect(await controller.readSnapshot('GoalProjectLink', 'gpl_1'), snap);

    // Update (id stable, projectId modifié).
    await controller.upsertLocal('GoalProjectLink',
        {'id': 'gpl_1', 'goalId': 'g1', 'projectId': 'p2'});
    expect((await controller.readSnapshot('GoalProjectLink', 'gpl_1'))!['projectId'],
        'p2');

    // Suppression locale (DELETE serveur).
    await controller.deleteLocal('GoalProjectLink', 'gpl_1');
    expect(await controller.readSnapshot('GoalProjectLink', 'gpl_1'), isNull);
  });

  test('logOp → file PENDING : les mutations locales alimentent la file',
      () async {
    db.logOp('Task', 't1', 'CREATE', {'title': 'Test'});
    db.logOp('Task', 't1', 'UPDATE', {'status': 'DONE'});
    db.logOp('Notification', 'n1', 'UPDATE', {});
    final ops = await (db.select(db.syncOperations)
          ..where((o) => o.status.equals('PENDING') &
              o.resourceId.isIn(const ['t1', 'n1'])))
        .get();
    expect(ops.length, 3);
    // La plus récente pour (Task, t1) est l'UPDATE (déduplication push).
    final taskOps = ops.where((o) => o.resourceType == 'Task').toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    expect(taskOps.last.op, 'UPDATE');
  });

  test('clearSyncedOps ne purge que l\'historique de plus de 7 jours', () async {
    final now = DateTime.now();
    Future<void> seedOp(String id, String status, DateTime syncedAt) async {
      await db.into(db.syncOperations).insert(SyncOperation(
          id: id,
          resourceType: 'Task',
          resourceId: 'r-$id',
          op: 'UPDATE',
          status: status,
          attempts: 1,
          createdAt: DateTime.now(),
          syncedAt: syncedAt));
    }

    await seedOp('old', 'SYNCED', now.subtract(const Duration(days: 10)));
    await seedOp('recent', 'SYNCED', now.subtract(const Duration(days: 2)));
    await seedOp('oldLocal', 'LOCAL', now.subtract(const Duration(days: 10)));
    await db.clearSyncedOps();
    final remaining = await (db.select(db.syncOperations)
          ..where((o) => o.id.isIn(const ['old', 'recent', 'oldLocal'])))
        .get();
    expect(remaining.map((o) => o.id), ['recent']);
  });
}
