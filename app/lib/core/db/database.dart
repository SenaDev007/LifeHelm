import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'connection.dart';
import 'seed.dart';
import 'tables.dart';

part 'database.g.dart';

/// Base LifeHelm — source de vérité locale offline-first (CDC §2.3, D01.4).
/// Chaque mutation métier est journalisée dans la file `SyncOperations`
/// en attente de synchronisation serveur (idempotence, identifiants stables).
@DriftDatabase(tables: [
  // D01
  Spaces, SpaceMembers, RecurrenceRules, SyncOperations, Settings,
  // D03
  TaskLists, Tasks, TaskAssignees, TaskDependencies,
  // D04
  Calendars, CalendarEvents, EventParticipants, EventExceptions,
  // D05
  FinancialAccounts, FinancialCategories, FinancialTransactions, Transfers,
  TransactionAllocations, Budgets, BudgetAdjustments, BudgetCarryovers,
  FinancialDueItems, AccountReconciliations,
  // D06
  Folders, Notes, NoteVersions, Documents, AttachmentLinks,
  // D07
  Projects, ProjectMembers, ProjectStages, ProjectMilestones, ProjectTaskLinks,
  Goals, GoalMetrics, GoalProgressEntries,
  // D08
  Habits, HabitSchedules, HabitOccurrences, Routines, RoutineSteps,
  RoutineOccurrences,
  // D09
  WellbeingEntries, DailyReviews, ReflectionQuestions,
  // D10
  CareerProfiles, Skills, UserSkills, LearningPaths, LearningPathSteps,
  ProfessionalExperiences, Certifications, PortfolioItems,
  // D11
  Contacts, ContactPoints, ContactInteractions, ContactLinks,
  // D12
  Conversations, ConversationMembers, Messages, MessageReactions,
  // D13
  Notifications, NotificationPrefs,
  // D14
  RecentSearches,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? connect());

  /// Constructeur de test : base en mémoire isolée.
  AppDatabase.test(QueryExecutor executor) : super(executor);

  static const _uuid = Uuid();

  @override
  int get schemaVersion => 1;

  // ══════════════════════════ RÉGLAGES (clé-valeur) ══════════════════════════

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(settings).insertOnConflictUpdate(Setting(key: key, value: value));
  }

  Future<void> removeSetting(String key) =>
      (delete(settings)..where((s) => s.key.equals(key))).go();

  Stream<Map<String, String>> watchSettings() {
    return (select(settings)).watch().map(
        (rows) => {for (final r in rows) r.key: r.value});
  }

  Future<bool> isOnboarded() async => await getSetting('onboarded') == 'true';

  // ══════════════════════════ FILE DE SYNCHRONISATION (D01.4) ══════════════════════════

  /// Journalise une opération en file d'attente persistante.
  void logOp(String resourceType, String resourceId, String op,
      [Map<String, dynamic>? payload]) {
    into(syncOperations).insert(SyncOperationsCompanion.insert(
      id: _uuid.v4(),
      resourceType: resourceType,
      resourceId: resourceId,
      op: op,
      payloadJson: Value(payload == null ? null : jsonEncode(payload)),
    ));
  }

  Stream<List<SyncOperation>> watchPendingOps() {
    return (select(syncOperations)
          ..where((o) => o.status.equals('PENDING'))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .watch();
  }

  Stream<int> watchPendingOpCount() =>
      watchPendingOps().map((l) => l.length);

  /// Simule un cycle de synchronisation serveur : les opérations en attente
  /// passent à SYNCED. Le backend NestJS (CDC §3) prendra le relais en prod.
  Future<int> simulateSyncCycle() async {
    return await (update(syncOperations)..where((o) => o.status.equals('PENDING')))
        .write(SyncOperationsCompanion(
      status: const Value('SYNCED'),
      syncedAt: Value(DateTime.now()),
    ));
  }

  /// Purge de l'historique synchronisé : ne conserve que 7 jours
  /// (rétention D01.4). Les statuts LOCAL (opérations device non envoyées,
  /// ex. notifications) suivent la même règle.
  Future<void> clearSyncedOps() => (delete(syncOperations)
        ..where((o) =>
            o.status.isIn(const ['SYNCED', 'LOCAL']) &
            (o.syncedAt.isNull() |
                o.syncedAt.isSmallerThanValue(
                    DateTime.now().subtract(const Duration(days: 7))))))
      .go();

  // ══════════════════════════ NOTIFICATIONS (D13) ══════════════════════════

  /// Crée une notification avec déduplication technique (CDC D13 §18.5) :
  /// une `dedupKey` identique ne crée jamais deux alertes logiques.
  Future<void> pushNotification({
    required String spaceId,
    required String category,
    required String priority,
    required String title,
    required String body,
    String? resourceType,
    String? resourceId,
    String? dedupKey,
  }) async {
    final pref = await (select(notificationPrefs)
          ..where((p) => p.category.equals(category)))
        .getSingleOrNull();
    if (pref != null && !pref.inAppEnabled) return;

    if (dedupKey != null) {
      final exists = await (select(notifications)
            ..where((n) => n.dedupKey.equals(dedupKey)))
          .getSingleOrNull();
      if (exists != null) return;
    }
    await into(notifications).insert(NotificationsCompanion.insert(
      id: _uuid.v4(),
      spaceId: spaceId,
      category: category,
      priority: Value(priority),
      title: title,
      body: body,
      resourceType: Value(resourceType),
      resourceId: Value(resourceId),
      dedupKey: Value(dedupKey),
    ));
  }

  Stream<int> watchUnreadCount() {
    final q = selectOnly(notifications)
      ..addColumns([countAll()])
      ..where(notifications.readAt.isNull() &
          notifications.archivedAt.isNull() &
          notifications.spaceId.isNotNull());
    return q.watchSingle().map((r) => r.read(countAll()) ?? 0);
  }

  // ══════════════════════════ ESPACES (D01.2) ══════════════════════════

  Stream<List<Space>> watchSpaces() =>
      (select(spaces)..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).watch();

  Future<List<Space>> getAllSpaces() =>
      (select(spaces)..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).get();

  Future<Space?> getSpace(String id) =>
      (select(spaces)..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<Space> watchSpace(String id) =>
      (select(spaces)..where((s) => s.id.equals(id))).watchSingle();

  Stream<List<SpaceMember>> watchMembers(String spaceId) {
    return (select(spaceMembers)
          ..where((m) => m.spaceId.equals(spaceId)))
        .watch();
  }

  Future<Space> createSpace({
    required String type,
    required String name,
    String colorHex = '#FFD700',
    bool isDefault = false,
  }) async {
    final space = Space(
      id: _uuid.v4(),
      type: type,
      name: name,
      colorHex: colorHex,
      isDefault: isDefault,
      createdAt: DateTime.now(),
    );
    await into(spaces).insert(space);
    final ownerId = _uuid.v4();
    await into(spaceMembers).insert(SpaceMember(
      id: ownerId,
      spaceId: space.id,
      displayName: 'Vous',
      role: 'OWNER',
      createdAt: DateTime.now(),
    ));
    logOp('Space', space.id, 'CREATE', {'name': name, 'type': type});
    logOp('SpaceMember', ownerId, 'CREATE',
        {'role': 'OWNER', 'spaceId': space.id});
    return space;
  }

  /// Transfert de propriété explicite et audité (CDC §5.3).
  Future<void> transferOwnership(String spaceId, String memberId) async {
    await (update(spaceMembers)..where((m) => m.id.equals(memberId)))
        .write(const SpaceMembersCompanion(role: Value('OWNER')));
    await (update(spaceMembers)
          ..where((m) =>
              m.spaceId.equals(spaceId) & m.role.equals('OWNER') &
              m.id.equals(memberId).not()))
        .write(const SpaceMembersCompanion(role: Value('ADMIN')));
    logOp('SpaceMember', memberId, 'UPDATE', {'role': 'OWNER', 'spaceId': spaceId});
  }

  /// Balayage de maintenance — génère les alertes d'échéance, retard et
  /// dépassement de budget (dédupliquées), exécuté à l'ouverture du cockpit.
  Future<void> maintenanceScan({String? spaceId}) async {
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final spaces = spaceId == null ? await getAllSpaces() : [await getSpace(spaceId)].whereType<Space>().toList();
    for (final space in spaces) {
      // Tâches en retard ou à échéance proche (fenêtre réglable, défaut 7 j — D02).
      final activeTasks = await (select(tasks)
            ..where((t) =>
                t.spaceId.equals(space.id) &
                t.archivedAt.isNull() &
                t.status.isIn(['TODO', 'IN_PROGRESS', 'WAITING'])))
          .get();
      for (final t in activeTasks) {
        final due = t.dueDate;
        if (due == null) continue;
        if (due.compareTo(todayKey) < 0) {
          await pushNotification(
            spaceId: space.id,
            category: 'TASK',
            priority: 'IMPORTANT',
            title: 'Tâche en retard',
            body: '« ${t.title} » était prévue avant aujourd\'hui.',
            resourceType: 'TASK',
            resourceId: t.id,
            dedupKey: 'task-overdue-${t.id}',
          );
        } else if (due.compareTo(todayKey) == 0) {
          await pushNotification(
            spaceId: space.id,
            category: 'TASK',
            priority: 'NORMAL',
            title: "Échéance aujourd'hui",
            body: '« ${t.title} » arrive à échéance aujourd\'hui.',
            resourceType: 'TASK',
            resourceId: t.id,
            dedupKey: 'task-due-${t.id}-$todayKey',
          );
        }
      }

      // Événements du jour.
      final events = await (select(calendarEvents)
            ..where((e) =>
                e.spaceId.equals(space.id) &
                e.status.equals('SCHEDULED') &
                e.startDate.equals(todayKey)))
          .get();
      for (final e in events.take(3)) {
        await pushNotification(
          spaceId: space.id,
          category: 'AGENDA',
          priority: 'NORMAL',
          title: 'Événement aujourd\'hui',
          body: '${e.title}${e.startTime != null ? ' à ${e.startTime}' : ''}.',
          resourceType: 'EVENT',
          resourceId: e.id,
          dedupKey: 'event-today-${e.id}-$todayKey',
        );
      }

      // Échéances financières à venir (7 jours).
      final in7 = DateTime(now.year, now.month, now.day + 7);
      final in7Key =
          '${in7.year}-${in7.month.toString().padLeft(2, '0')}-${in7.day.toString().padLeft(2, '0')}';
      final dues = await (select(financialDueItems)
            ..where((d) =>
                d.spaceId.equals(space.id) &
                d.status.equals('OPEN') &
                d.dueDate.isBiggerOrEqualValue(todayKey) &
                d.dueDate.isSmallerOrEqualValue(in7Key)))
          .get();
      for (final d in dues) {
        await pushNotification(
          spaceId: space.id,
          category: 'FINANCE',
          priority: 'IMPORTANT',
          title: 'Échéance financière proche',
          body: '« ${d.label} » arrive à échéance le ${d.dueDate.split('-').reversed.join('/')}.',
          resourceType: 'DUE',
          resourceId: d.id,
          dedupKey: 'due-soon-${d.id}',
        );
      }

      // Dépassement de budget (seuil configurable, défaut 80 % — D05 §10.1-4).
      final threshold =
          (double.tryParse(await getSetting('budgetAlertThreshold') ?? '') ?? 0.8);
      final budgetRows = await (select(budgets)
            ..where((b) => b.spaceId.equals(space.id)))
          .get();
      for (final b in budgetRows) {
        final spent = await _spentForBudget(b.id);
        final envelope = b.initialAmount +
            await _adjustmentsFor(b.id) +
            await _carryoverFor(b.id);
        if (envelope > 0 && spent / envelope >= threshold) {
          final pct = (100 * spent / envelope).round();
          await pushNotification(
            spaceId: space.id,
            category: 'FINANCE',
            priority: pct >= 100 ? 'CRITICAL' : 'IMPORTANT',
            title: 'Budget à $pct %',
            body: '« ${b.name} » a consommé $pct % de son enveloppe.',
            resourceType: 'BUDGET',
            resourceId: b.id,
            dedupKey: 'budget-alert-${b.id}-$pct',
          );
        }
      }
    }
  }

  Future<int> _spentForBudget(String budgetId) async {
    final allocs = await (select(transactionAllocations)
          ..where((a) => a.budgetId.equals(budgetId)))
        .get();
    var total = 0;
    for (final a in allocs) {
      final tx = await (select(financialTransactions)
            ..where((t) => t.id.equals(a.transactionId) & t.status.equals('POSTED')))
          .getSingleOrNull();
      if (tx != null && tx.kind == 'EXPENSE') total += a.amount;
    }
    return total;
  }

  Future<int> _adjustmentsFor(String budgetId) async {
    final rows = await (select(budgetAdjustments)
          ..where((a) => a.budgetId.equals(budgetId)))
        .get();
    return rows.fold<int>(0, (sum, a) => sum + a.amount);
  }

  Future<int> _carryoverFor(String budgetId) async {
    final rows = await (select(budgetCarryovers)
          ..where((a) => a.budgetId.equals(budgetId)))
        .get();
    return rows.fold<int>(0, (sum, a) => sum + a.amount);
  }

  // ══════════════════════════ AMORÇAGE / ONBOARDING ══════════════════════════

  /// Crée les trois espaces et leurs fondations (D01.2, §2.1).
  Future<void> initializeDefaultSpaces({required String ownerName}) async {
    if (await isOnboarded()) return;

    final personal = await createSpace(
        type: 'PERSONAL', name: 'Personnel', colorHex: '#FFD700', isDefault: true);
    final family = await createSpace(
        type: 'FAMILY', name: 'Famille', colorHex: '#10A878');
    final pro = await createSpace(
        type: 'PROFESSIONAL', name: 'Professionnel', colorHex: '#5B8DD9');

    await seedSpaceFoundations(this, personal.id,
        ownerName: ownerName,
        withDemo: false);
    await seedSpaceFoundations(this, family.id, ownerName: ownerName, withDemo: false);
    await seedSpaceFoundations(this, pro.id, ownerName: ownerName, withDemo: false);

    await setSetting('activeSpaceId', personal.id);
    await setSetting('onboarded', 'true');
    await setSetting('themeMode', 'dark');
    await setSetting('upcomingWindowDays', '7');
    await setSetting('budgetAlertThreshold', '0.8');
    await setSetting('quietHoursEnabled', 'false');
    await setSetting('quietStart', '22:00');
    await setSetting('quietEnd', '07:00');
    await setSetting('cockpitVisibleSections',
        jsonEncode(['today', 'actions', 'priorities', 'agenda', 'finance', 'goals', 'alerts']));
    await setSetting('showFinanceSummary', 'true');
    await setSetting('showAiSummary', 'false');

    // Préférences de notifications : activées par défaut (D13).
    for (final cat in [
      'TASK', 'AGENDA', 'FINANCE', 'PROJECT', 'HABIT', 'NOTE', 'MESSAGE', 'SECURITY'
    ]) {
      await into(notificationPrefs)
          .insert(NotificationPref(id: _uuid.v4(), category: cat, inAppEnabled: true));
    }
  }

  /// Charge des données d'exemple dans les trois espaces (choix onboarding).
  Future<void> seedDemoData() => seedAllDemoData(this);

  /// Purge la corbeille et les notifications expirées (rétention).
  Future<void> purgeExpired() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    await (delete(notes)..where((n) => n.trashedAt.isSmallerThanValue(cutoff))).go();
    await (delete(notifications)
          ..where((n) => n.archivedAt.isNotNull() &
              n.archivedAt.isSmallerThanValue(
                  DateTime.now().subtract(const Duration(days: 90)))))
        .go();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
