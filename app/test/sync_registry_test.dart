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
    // Les données de démonstration ont été retirées de l'app : le test
    // insère lui-même une ligne minimale par type synchronisable.
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    final spaceId = personal.id;
    final lists = await (db.select(db.taskLists)
          ..where((l) => l.spaceId.equals(spaceId)))
        .get();
    final cals = await (db.select(db.calendars)
          ..where((c) => c.spaceId.equals(spaceId)))
        .get();

    // Compte financier + membre de conversation pour les clés étrangères.
    await db.into(db.financialAccounts).insert(FinancialAccountsCompanion.insert(
        id: 'acc1', spaceId: spaceId, name: 'Espèces', type: 'CASH',
        initialDate: '2026-01-01'));
    await db.into(db.conversations).insert(
        ConversationsCompanion.insert(id: 'conv1', spaceId: spaceId));
    await db.into(db.conversationMembers).insert(
        ConversationMembersCompanion.insert(
            id: 'cm1', conversationId: 'conv1', displayName: 'Test'));
    await db.into(db.contacts).insert(
        ContactsCompanion.insert(id: 'ct1', spaceId: spaceId, kind: 'PERSON'));
    await db.into(db.goals).insert(
        GoalsCompanion.insert(id: 'g1', spaceId: spaceId, title: 'Objectif test'));

    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 'task1', spaceId: spaceId, title: 'Tâche test',
        listId: Value(lists.first.id)));
    await db.into(db.notes).insert(
        NotesCompanion.insert(id: 'note1', spaceId: spaceId, title: 'Note test'));
    await db.into(db.financialTransactions).insert(
        FinancialTransactionsCompanion.insert(
            id: 'tx1', spaceId: spaceId, accountId: 'acc1',
            kind: 'EXPENSE', currency: 'XOF', amount: 500,
            occurredAt: DateTime(2026)));
    await db.into(db.habits).insert(
        HabitsCompanion.insert(id: 'hb1', spaceId: spaceId, name: 'Habitude test'));
    await db.into(db.messages).insert(MessagesCompanion.insert(
        id: 'msg1', conversationId: 'conv1', senderMemberId: 'cm1',
        body: 'Message test'));
    await db.into(db.recurrenceRules).insert(
        RecurrenceRulesCompanion.insert(id: 'rr1', freq: 'WEEKLY'));
    await db.into(db.calendarEvents).insert(CalendarEventsCompanion.insert(
        id: 'ev1', spaceId: spaceId, calendarId: cals.first.id,
        title: 'Événement test',
        startDate: '2026-01-01T08:00', endDate: '2026-01-01T09:00'));
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
        id: 'bg1', spaceId: spaceId, name: 'Budget test', initialAmount: 50000,
        periodStart: '2026-01-01', periodEnd: '2026-01-31'));
    await db.into(db.transfers).insert(TransfersCompanion.insert(
        id: 'tr1', spaceId: spaceId, fromAccountId: 'acc1', toAccountId: 'acc1',
        fromCurrency: 'XOF', toCurrency: 'XOF',
        fromAmount: 500, toAmount: 500, occurredAt: DateTime(2026)));
    await db.into(db.folders).insert(
        FoldersCompanion.insert(id: 'fd1', spaceId: spaceId, name: 'Dossier test'));
    await db.into(db.projects).insert(
        ProjectsCompanion.insert(id: 'pj1', spaceId: spaceId, name: 'Projet test'));
    await db.into(db.routines).insert(
        RoutinesCompanion.insert(id: 'rt1', spaceId: spaceId, name: 'Routine test'));
    await db.into(db.wellbeingEntries).insert(
        WellbeingEntriesCompanion.insert(
            id: 'wb1', spaceId: spaceId, dateKey: '2026-01-01'));
    await db.into(db.skills).insert(
        SkillsCompanion.insert(id: 'sk1', name: 'Compétence test'));
    await db.into(db.certifications).insert(
        CertificationsCompanion.insert(id: 'ce1', name: 'Certification test'));
    await db.into(db.contactInteractions).insert(
        ContactInteractionsCompanion.insert(
            id: 'ci1', contactId: 'ct1', dateKey: '2026-01-01',
            kind: 'NOTE', summary: 'Interaction test'));
    await db.into(db.goalProgressEntries).insert(
        GoalProgressEntriesCompanion.insert(id: 'gp1', goalId: 'g1', value: 1));
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
