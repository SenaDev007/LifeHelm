import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../providers.dart' show dbProvider;
import 'api_client.dart'
    show ApiClient, LhApiException, LhNetworkException, apiClientProvider,
        apiErrorText, tokenStoreProvider;

// ══════════════════════════ REGISTRE DES RESSOURCES ══════════════════════════

/// Table Drift synchronisable + décodeur JSON (drift DataClass.toJson/fromJson).
class SyncTable {
  const SyncTable(this.table, this.fromJson);

  final TableInfo<Table, DataClass> table;

  /// Reconstruit un companion complet (nulls inclus → upsert fidèle).
  final Insertable<DataClass> Function(Map<String, dynamic> json) fromJson;
}

/// Construit le registre exhaustif resourceType → table Drift.
///
/// Types journalisés via `logOp` et couverts ici ; les tables locales à
/// l'appareil (Notification, NotificationPref, RecentSearches, SyncOperations,
/// Settings, TaskAssignee, EventParticipant, Documents, AttachmentLinks,
/// ReflectionQuestions) en sont volontairement EXCLUES (CDC D01.4 : la sync
/// est additive et ne touche jamais les données device).
Map<String, SyncTable> buildSyncRegistry(AppDatabase db) => {
      // D01
      'Space': SyncTable(db.spaces, (j) => Space.fromJson(j).toCompanion(false)),
      'SpaceMember':
          SyncTable(db.spaceMembers, (j) => SpaceMember.fromJson(j).toCompanion(false)),
      'RecurrenceRule': SyncTable(db.recurrenceRules,
          (j) => RecurrenceRule.fromJson(j).toCompanion(false)),
      // D03
      'TaskList':
          SyncTable(db.taskLists, (j) => TaskList.fromJson(j).toCompanion(false)),
      'Task': SyncTable(db.tasks, (j) => Task.fromJson(j).toCompanion(false)),
      'TaskDependency': SyncTable(db.taskDependencies,
          (j) => TaskDependency.fromJson(j).toCompanion(false)),
      // D04
      'Calendar':
          SyncTable(db.calendars, (j) => Calendar.fromJson(j).toCompanion(false)),
      'CalendarEvent': SyncTable(db.calendarEvents,
          (j) => CalendarEvent.fromJson(j).toCompanion(false)),
      'EventException': SyncTable(db.eventExceptions,
          (j) => EventException.fromJson(j).toCompanion(false)),
      // D05
      'FinancialAccount': SyncTable(db.financialAccounts,
          (j) => FinancialAccount.fromJson(j).toCompanion(false)),
      'FinancialCategory': SyncTable(db.financialCategories,
          (j) => FinancialCategory.fromJson(j).toCompanion(false)),
      'FinancialTransaction': SyncTable(db.financialTransactions,
          (j) => FinancialTransaction.fromJson(j).toCompanion(false)),
      'Transfer':
          SyncTable(db.transfers, (j) => Transfer.fromJson(j).toCompanion(false)),
      'TransactionAllocation': SyncTable(db.transactionAllocations,
          (j) => TransactionAllocation.fromJson(j).toCompanion(false)),
      'Budget': SyncTable(db.budgets, (j) => Budget.fromJson(j).toCompanion(false)),
      'BudgetAdjustment': SyncTable(db.budgetAdjustments,
          (j) => BudgetAdjustment.fromJson(j).toCompanion(false)),
      'BudgetCarryover': SyncTable(db.budgetCarryovers,
          (j) => BudgetCarryover.fromJson(j).toCompanion(false)),
      'FinancialDueItem': SyncTable(db.financialDueItems,
          (j) => FinancialDueItem.fromJson(j).toCompanion(false)),
      'AccountReconciliation': SyncTable(db.accountReconciliations,
          (j) => AccountReconciliation.fromJson(j).toCompanion(false)),
      'Loan': SyncTable(db.loans, (j) => Loan.fromJson(j).toCompanion(false)),
      // D06
      'Folder':
          SyncTable(db.folders, (j) => Folder.fromJson(j).toCompanion(false)),
      'Note': SyncTable(db.notes, (j) => Note.fromJson(j).toCompanion(false)),
      'NoteVersion': SyncTable(
          db.noteVersions, (j) => NoteVersion.fromJson(j).toCompanion(false)),
      // D07
      'Project':
          SyncTable(db.projects, (j) => Project.fromJson(j).toCompanion(false)),
      'ProjectMember': SyncTable(db.projectMembers,
          (j) => ProjectMember.fromJson(j).toCompanion(false)),
      'ProjectStage': SyncTable(db.projectStages,
          (j) => ProjectStage.fromJson(j).toCompanion(false)),
      'ProjectMilestone': SyncTable(db.projectMilestones,
          (j) => ProjectMilestone.fromJson(j).toCompanion(false)),
      'ProjectTaskLink': SyncTable(db.projectTaskLinks,
          (j) => ProjectTaskLink.fromJson(j).toCompanion(false)),
      'Goal': SyncTable(db.goals, (j) => Goal.fromJson(j).toCompanion(false)),
      'GoalMetric':
          SyncTable(db.goalMetrics, (j) => GoalMetric.fromJson(j).toCompanion(false)),
      'GoalProgressEntry': SyncTable(db.goalProgressEntries,
          (j) => GoalProgressEntry.fromJson(j).toCompanion(false)),
      // NB : « GoalProjectLink » est porté par une table auxiliaire SQL brut
      // (goal_project_links) — géré hors registre par le SyncService.
      // D08
      'Habit': SyncTable(db.habits, (j) => Habit.fromJson(j).toCompanion(false)),
      'HabitSchedule': SyncTable(db.habitSchedules,
          (j) => HabitSchedule.fromJson(j).toCompanion(false)),
      'HabitOccurrence': SyncTable(db.habitOccurrences,
          (j) => HabitOccurrence.fromJson(j).toCompanion(false)),
      'Routine':
          SyncTable(db.routines, (j) => Routine.fromJson(j).toCompanion(false)),
      'RoutineStep': SyncTable(
          db.routineSteps, (j) => RoutineStep.fromJson(j).toCompanion(false)),
      'RoutineOccurrence': SyncTable(db.routineOccurrences,
          (j) => RoutineOccurrence.fromJson(j).toCompanion(false)),
      // D09
      'WellbeingEntry': SyncTable(db.wellbeingEntries,
          (j) => WellbeingEntry.fromJson(j).toCompanion(false)),
      'DailyReview': SyncTable(
          db.dailyReviews, (j) => DailyReview.fromJson(j).toCompanion(false)),
      // D10
      'CareerProfile': SyncTable(db.careerProfiles,
          (j) => CareerProfile.fromJson(j).toCompanion(false)),
      'Skill': SyncTable(db.skills, (j) => Skill.fromJson(j).toCompanion(false)),
      'UserSkill':
          SyncTable(db.userSkills, (j) => UserSkill.fromJson(j).toCompanion(false)),
      'LearningPath': SyncTable(
          db.learningPaths, (j) => LearningPath.fromJson(j).toCompanion(false)),
      'LearningPathStep': SyncTable(db.learningPathSteps,
          (j) => LearningPathStep.fromJson(j).toCompanion(false)),
      'ProfessionalExperience': SyncTable(db.professionalExperiences,
          (j) => ProfessionalExperience.fromJson(j).toCompanion(false)),
      'Certification': SyncTable(
          db.certifications, (j) => Certification.fromJson(j).toCompanion(false)),
      'PortfolioItem': SyncTable(db.portfolioItems,
          (j) => PortfolioItem.fromJson(j).toCompanion(false)),
      // D11
      'Contact':
          SyncTable(db.contacts, (j) => Contact.fromJson(j).toCompanion(false)),
      'ContactPoint': SyncTable(
          db.contactPoints, (j) => ContactPoint.fromJson(j).toCompanion(false)),
      'ContactInteraction': SyncTable(db.contactInteractions,
          (j) => ContactInteraction.fromJson(j).toCompanion(false)),
      'ContactLink': SyncTable(
          db.contactLinks, (j) => ContactLink.fromJson(j).toCompanion(false)),
      // D12
      'Conversation':
          SyncTable(db.conversations, (j) => Conversation.fromJson(j).toCompanion(false)),
      'ConversationMember': SyncTable(db.conversationMembers,
          (j) => ConversationMember.fromJson(j).toCompanion(false)),
      'Message':
          SyncTable(db.messages, (j) => Message.fromJson(j).toCompanion(false)),
      'MessageReaction': SyncTable(db.messageReactions,
          (j) => MessageReaction.fromJson(j).toCompanion(false)),
    };

// ══════════════════════════ REQUÊTES SYNC (extension) ══════════════════════════

extension SyncOpsQueries on AppDatabase {
  /// Toutes les opérations (compteurs d'état).
  Stream<List<SyncOperation>> watchAllSyncOps() =>
      (select(syncOperations)).watch();

  /// Conflits en attente de résolution.
  Stream<List<SyncOperation>> watchSyncConflicts() {
    return (select(syncOperations)
          ..where((o) => o.status.equals('CONFLICT'))
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .watch();
  }

  /// Rejets serveur.
  Stream<List<SyncOperation>> watchSyncRejections() {
    return (select(syncOperations)
          ..where((o) => o.status.equals('REJECTED'))
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .watch();
  }

  /// Opérations PENDING ou CONFLICT pour une ressource (le push tranchera).
  Future<bool> hasPendingOpFor(String resourceType, String resourceId) async {
    final q = selectOnly(syncOperations)
      ..addColumns([countAll()])
      ..where(syncOperations.resourceType.equals(resourceType) &
          syncOperations.resourceId.equals(resourceId) &
          syncOperations.status.isIn(const ['PENDING', 'CONFLICT']));
    final row = await q.getSingle();
    return (row.read(countAll()) ?? 0) > 0;
  }

  /// Nombre d'opérations antérieures pour la même ressource
  /// (distinguer CREATE / UPDATE sur les opérations CREATE_OR_UPDATE).
  Future<bool> hasSyncHistoryFor(String resourceType, String resourceId,
      {String? excludingOpId}) async {
    final q = selectOnly(syncOperations)
      ..addColumns([countAll()])
      ..where(syncOperations.resourceType.equals(resourceType) &
          syncOperations.resourceId.equals(resourceId));
    if (excludingOpId != null) {
      q.where(syncOperations.id.equals(excludingOpId).not());
    }
    final row = await q.getSingle();
    return (row.read(countAll()) ?? 0) > 0;
  }

  /// Fait passer une opération à un statut donné (SYNCED, CONFLICT, REJECTED,
  /// LOCAL, PENDING) avec traçabilité.
  Future<void> resolveSyncOp(String id, String status, {String? error}) async {
    await (update(syncOperations)..where((o) => o.id.equals(id))).write(
      SyncOperationsCompanion(
        status: Value(status),
        lastError: Value(error),
        syncedAt: Value(
            status == 'SYNCED' || status == 'LOCAL' ? DateTime.now() : null),
      ),
    );
  }

  /// Purge immédiate de tout l'historique résolu (bouton de l'écran Synchro).
  Future<void> purgeSyncHistory() => (delete(syncOperations)
        ..where((o) => o.status.isIn(const ['SYNCED', 'LOCAL'])))
      .go();
}

// ══════════════════════════ ÉTAT DE SYNCHRONISATION ══════════════════════════

/// Instantané de l'état du moteur de synchronisation (exposé à l'UI).
class LhSyncState {
  const LhSyncState({
    this.enabled = false,
    this.connected = false,
    this.running = false,
    this.lastSyncAt,
    this.pending = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.lastError,
    this.cursor = 0,
    this.serverSeq,
  });

  final bool enabled; // un compte existe
  final bool connected; // session valide
  final bool running; // cycle en cours
  final DateTime? lastSyncAt;
  final int pending;
  final int conflicts;
  final int rejected;
  final String? lastError;
  final int cursor;
  final int? serverSeq;

  LhSyncState copyWith({
    bool? enabled,
    bool? connected,
    bool? running,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    int? pending,
    int? conflicts,
    int? rejected,
    String? lastError,
    bool clearError = false,
    int? cursor,
    int? serverSeq,
    bool clearServerSeq = false,
  }) =>
      LhSyncState(
        enabled: enabled ?? this.enabled,
        connected: connected ?? this.connected,
        running: running ?? this.running,
        lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
        pending: pending ?? this.pending,
        conflicts: conflicts ?? this.conflicts,
        rejected: rejected ?? this.rejected,
        lastError: clearError ? null : (lastError ?? this.lastError),
        cursor: cursor ?? this.cursor,
        serverSeq: clearServerSeq ? null : (serverSeq ?? this.serverSeq),
      );
}

// ══════════════════════════ MOTEUR DE SYNCHRONISATION ══════════════════════════

/// Moteur offline-first : PUSH (file locale → serveur) puis PULL (serveur →
/// base locale). Déclencheurs : manuel, debounce 5 s après mutation,
/// timer périodique 5 min, login/register (sync initiale).
/// Toute erreur réseau est silencieuse mais exposée dans [LhSyncState].
class SyncController {
  SyncController(this._ref) {
    _registry = buildSyncRegistry(db);
    _init();
  }

  static const int batchSize = 100;
  static const Duration debounceDelay = Duration(seconds: 5);
  static const Duration periodicDelay = Duration(minutes: 5);
  static const String goalProjectLinkTable = 'goal_project_links';

  final Ref _ref;
  late final Map<String, SyncTable> _registry;
  final _states = StreamController<LhSyncState>.broadcast();
  final List<StreamSubscription> _subs = [];
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  LhSyncState _state = const LhSyncState();
  bool _running = false;
  bool _wasConnected = false;
  bool _disposed = false;
  bool _goalProjectLinksReady = false;

  AppDatabase get db => _ref.read(dbProvider);
  ApiClient get api => _ref.read(apiClientProvider);

  /// Flux d'état (rejoue la valeur courante à chaque abonné).
  Stream<LhSyncState> get states async* {
    yield _state;
    yield* _states.stream;
  }

  LhSyncState get state => _state;

  void _emit() {
    if (!_states.isClosed) _states.add(_state);
  }

  // ── Amorçage ──

  Future<void> _init() async {
    // Métadonnées persistées.
    final lastSyncRaw = await db.getSetting('lastSyncAt');
    final cursor = int.tryParse(await db.getSetting('syncCursor') ?? '') ?? 0;
    final serverSeq =
        int.tryParse(await db.getSetting('serverSeq') ?? '');
    _state = _state.copyWith(
      lastSyncAt: lastSyncRaw == null ? null : DateTime.parse(lastSyncRaw),
      cursor: cursor,
      serverSeq: serverSeq,
    );

    // Compteurs de la file (toute écriture les rafraîchit).
    _subs.add(db.watchAllSyncOps().listen((ops) {
      if (_disposed) return;
      _state = _state.copyWith(
        pending: ops.where((o) => o.status == 'PENDING').length,
        conflicts: ops.where((o) => o.status == 'CONFLICT').length,
        rejected: ops.where((o) => o.status == 'REJECTED').length,
      );
      _emit();
      _scheduleDebouncedSync();
    }));

    // Session (le TokenStore est la source de vérité partagée avec l'UI).
    final store = _ref.read(tokenStoreProvider);
    final initial = await store.load();
    _applyConnection(initial != null, triggerInitialSync: false);
    _subs.add(store.changes.listen((session) {
      if (_disposed) return;
      _applyConnection(session != null);
    }));
    _subs.add(api.onSessionExpired.listen((_) {
      if (_disposed) return;
      _applyConnection(false);
    }));

    _emit();
  }

  /// Transition de connexion : démarre/arrête les déclencheurs et lance la
  /// synchronisation initiale à la connexion.
  void _applyConnection(bool connected, {bool triggerInitialSync = true}) {
    _state = _state.copyWith(
        enabled: connected, connected: connected,
        clearError: !connected);
    _emit();

    if (connected && !_wasConnected) {
      _startPeriodicTimer();
      if (triggerInitialSync) {
        unawaited(syncNow()); // sync initiale (push PENDING + pull)
      }
    } else if (!connected) {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
    }
    _wasConnected = connected;
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(periodicDelay, (_) {
      if (!_disposed && _state.connected) unawaited(syncNow());
    });
  }

  /// Debounce 5 s après chaque mutation journalisée (PENDING > 0).
  void _scheduleDebouncedSync() {
    if (_disposed || !_state.connected || _running) return;
    if (_state.pending == 0) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      if (!_disposed && _state.connected) unawaited(syncNow());
    });
  }

  /// Identifiant stable de l'appareil (UUID v4, réglage `deviceId`).
  Future<String> deviceId() async {
    var id = await db.getSetting('deviceId');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await db.setSetting('deviceId', id);
    }
    return id;
  }

  // ── Cycle complet ──

  /// Force un cycle push + pull. Retourne false si non connecté ou en erreur.
  Future<bool> syncNow() async {
    if (_running) return false;
    if (!_state.connected) {
      _state = _state.copyWith(
          lastError:
              'Non connecté — activez la synchronisation depuis l\'onglet Plus.');
      _emit();
      return false;
    }
    _running = true;
    _state = _state.copyWith(running: true, clearError: true);
    _emit();
    var ok = true;
    try {
      await _push();
      await _pull();
    } on LhNetworkException {
      ok = false;
      _state = _state.copyWith(
          lastError:
              'Serveur injoignable — nouvelle tentative automatique plus tard.');
    } on LhApiException catch (e) {
      ok = false;
      _state = _state.copyWith(lastError: apiErrorText(e));
    } catch (e) {
      ok = false;
      _state = _state.copyWith(lastError: 'Erreur de synchronisation : $e');
    } finally {
      _running = false;
      if (ok) {
        final now = DateTime.now();
        await db.setSetting('lastSyncAt', now.toIso8601String());
        _state = _state.copyWith(lastSyncAt: now, clearError: true);
      }
      _state = _state.copyWith(running: false);
      _emit();
    }
    return ok;
  }

  // ── PUSH : file locale → serveur ──

  Future<void> _push() async {
    final ops = await (db.select(db.syncOperations)
          ..where((o) => o.status.equals('PENDING'))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .get();
    if (ops.isEmpty) return;

    // Types device (Notification, NotificationPref…) : résolus localement,
    // jamais envoyés au serveur.
    final kept = <String, SyncOperation>{};
    for (final o in ops) {
      if (!_isSyncable(o.resourceType)) {
        await db.resolveSyncOp(o.id, 'LOCAL');
        continue;
      }
      // Déduplication (resourceType, resourceId) : la plus récente gagne.
      kept['${o.resourceType}|${o.resourceId}'] = o;
    }
    if (kept.isEmpty) return;

    final device = await deviceId();
    final entries = kept.values.toList();
    for (var start = 0; start < entries.length; start += batchSize) {
      final batch = entries.skip(start).take(batchSize).toList();
      final operations = <Map<String, dynamic>>[];
      for (final o in batch) {
        final snapshot = await readSnapshot(o.resourceType, o.resourceId);
        // Entrée « data » incluse seulement si snapshot non nul
        // (équivalent Dart <3.8 de l'élément null-aware `'data': ?snapshot`).
        final entry = <String, dynamic>{
          'opId': o.id,
          'resourceType': o.resourceType,
          'resourceId': o.resourceId,
          'op': await _finalOpFor(o, snapshot),
          'occurredAt': o.createdAt.toIso8601String(),
          if (snapshot != null) 'data': snapshot,
        };
        operations.add(entry);
      }
      final res = await api.post('/sync/operations',
          body: {'deviceId': device, 'operations': operations});
      final results = (res['results'] as List? ?? const []);
      for (final raw in results) {
        final r = Map<String, dynamic>.from(raw as Map);
        final opId = r['opId'] as String?;
        if (opId == null) continue;
        switch (r['status'] as String? ?? 'REJECTED') {
          case 'APPLIED':
          case 'DUPLICATE':
            await db.resolveSyncOp(opId, 'SYNCED');
            break;
          case 'CONFLICT':
            await db.resolveSyncOp(opId, 'CONFLICT',
                error: 'Divergence serveur');
            break;
          default:
            await db.resolveSyncOp(opId, 'REJECTED',
                error: (r['reason'] as String?) ?? 'Rejetée par le serveur');
        }
      }
      // Purge de l'historique synchronisé de plus de 7 jours (D01.4).
      await db.clearSyncedOps();
    }
  }

  bool _isSyncable(String resourceType) =>
      _registry.containsKey(resourceType) ||
      resourceType == 'GoalProjectLink';

  /// Op finale envoyée : DELETE si la ligne n'existe plus localement,
  /// CREATE si la ressource est nouvelle, sinon UPDATE.
  Future<String> _finalOpFor(
      SyncOperation op, Map<String, dynamic>? snapshot) async {
    if (snapshot == null) return 'DELETE';
    switch (op.op) {
      case 'CREATE':
        return 'CREATE';
      case 'CREATE_OR_UPDATE':
        // Insert-or-replace local : CREATE à première apparition, sinon UPDATE.
        final hasHistory = await db.hasSyncHistoryFor(
            op.resourceType, op.resourceId,
            excludingOpId: op.id);
        return hasHistory ? 'UPDATE' : 'CREATE';
      default:
        return 'UPDATE';
    }
  }

  // ── PULL : serveur → base locale ──

  Future<void> _pull() async {
    var cursor = _state.cursor;
    var hasMore = true;
    var guard = 0;
    while (hasMore && guard < 1000) {
      guard++;
      final data = await api.get('/sync/changes?cursor=$cursor&limit=200');
      final changes = (data['changes'] as List? ?? const []);
      for (final raw in changes) {
        final c = Map<String, dynamic>.from(raw as Map);
        final type = c['resourceType'] as String?;
        final id = c['resourceId'] as String?;
        if (type == null || id == null) continue;
        // Une opération locale PENDING/CONFLICT pour cette ressource :
        // on ne l'écrase pas, le push tranchera.
        if (await db.hasPendingOpFor(type, id)) continue;
        final op = (c['op'] as String?) ?? 'UPDATE';
        final deleted = (c['deleted'] as bool?) ?? (op == 'DELETE');
        if (deleted) {
          await deleteLocal(type, id);
        } else {
          final row = c['data'];
          if (row is Map) {
            await upsertLocal(type, Map<String, dynamic>.from(row));
          }
        }
      }
      cursor = (data['nextCursor'] as num?)?.toInt() ?? cursor;
      hasMore = (data['hasMore'] as bool?) ?? false;
      await db.setSetting('syncCursor', '$cursor');
      _state = _state.copyWith(cursor: cursor);
    }

    // serverSeq : séquence globale du serveur (carte ÉTAT).
    try {
      final status = await api.get('/sync/status');
      final seq = (status['serverSeq'] as num?)?.toInt();
      if (seq != null) {
        await db.setSetting('serverSeq', '$seq');
        _state = _state.copyWith(serverSeq: seq);
      }
    } on LhApiException {
      // /sync/status indisponible : on conserve le dernier connu.
    }
  }

  // ── Lecture / écriture génériques ──

  /// Snapshot JSON complet d'une ligne (null si absente localement).
  Future<Map<String, dynamic>?> readSnapshot(
      String resourceType, String resourceId) async {
    if (resourceType == 'GoalProjectLink') {
      return _readGoalProjectLink(resourceId);
    }
    final t = _registry[resourceType];
    if (t == null) return null;
    final row = await (db.select(t.table)
          ..where((tbl) => t.table.columnsByName['id']!.equals(resourceId)))
        .getSingleOrNull();
    return row?.toJson();
  }

  /// Upsert local (insertOnConflictUpdate) d'une ligne serveur.
  Future<void> upsertLocal(String resourceType, Map<String, dynamic> data) async {
    if (resourceType == 'GoalProjectLink') {
      await _upsertGoalProjectLink(data);
      return;
    }
    final t = _registry[resourceType];
    if (t == null) return; // type inconnu → ignoré (jamais de crash)
    await db.into(t.table).insertOnConflictUpdate(t.fromJson(data));
  }

  /// Suppression locale d'une ligne (DELETE serveur).
  Future<void> deleteLocal(String resourceType, String resourceId) async {
    if (resourceType == 'GoalProjectLink') {
      await _deleteGoalProjectLink(resourceId);
      return;
    }
    final t = _registry[resourceType];
    if (t == null) return;
    await (db.delete(t.table)
          ..where((tbl) => t.table.columnsByName['id']!.equals(resourceId)))
        .go();
  }

  // ── Table auxiliaire goal_project_links (SQL brut, D07 §12.7) ──

  Future<void> _ensureGoalProjectLinks() async {
    if (_goalProjectLinksReady) return;
    await db.customStatement(
        'CREATE TABLE IF NOT EXISTS $goalProjectLinkTable '
        '(id TEXT NOT NULL PRIMARY KEY, goal_id TEXT NOT NULL, '
        'project_id TEXT NOT NULL)');
    _goalProjectLinksReady = true;
  }

  Future<Map<String, dynamic>?> _readGoalProjectLink(String id) async {
    await _ensureGoalProjectLinks();
    final row = await db
        .customSelect(
            'SELECT id, goal_id AS "goalId", project_id AS "projectId" '
            'FROM $goalProjectLinkTable WHERE id = ?',
            variables: [Variable.withString(id)])
        .getSingleOrNull();
    if (row == null) return null;
    return {
      'id': row.read<String>('id'),
      'goalId': row.read<String>('goalId'),
      'projectId': row.read<String>('projectId'),
    };
  }

  Future<void> _upsertGoalProjectLink(Map<String, dynamic> data) async {
    await _ensureGoalProjectLinks();
    final id = data['id'] as String?;
    final goalId = (data['goalId'] ?? data['goal_id']) as String?;
    final projectId = (data['projectId'] ?? data['project_id']) as String?;
    if (id == null || goalId == null || projectId == null) return;
    await db.customUpdate(
        'INSERT OR REPLACE INTO $goalProjectLinkTable '
        '(id, goal_id, project_id) VALUES (?, ?, ?)',
        variables: [
          Variable.withString(id),
          Variable.withString(goalId),
          Variable.withString(projectId),
        ]);
  }

  Future<void> _deleteGoalProjectLink(String id) async {
    await _ensureGoalProjectLinks();
    await db.customUpdate('DELETE FROM $goalProjectLinkTable WHERE id = ?',
        variables: [Variable.withString(id)]);
  }

  // ── Résolution des conflits (écran Synchronisation) ──

  /// « Garder ma version » : l'opération repasse PENDING avec occurredAt
  /// actualisé — elle sera re-poussée au prochain cycle.
  Future<void> keepLocalVersion(String opId) async {
    await (db.update(db.syncOperations)..where((o) => o.id.equals(opId)))
        .write(SyncOperationsCompanion(
      status: const Value('PENDING'),
      lastError: const Value(null),
      syncedAt: const Value(null),
      createdAt: Value(DateTime.now()),
    ));
    unawaited(syncNow());
  }

  /// « Prendre la version serveur » : opération forcée SYNCED puis la
  /// ressource est re-téléchargée depuis le serveur.
  Future<bool> takeServerVersion(String opId) async {
    final op = await (db.select(db.syncOperations)
          ..where((o) => o.id.equals(opId)))
        .getSingleOrNull();
    if (op == null) return false;
    await db.resolveSyncOp(opId, 'SYNCED');
    return _pullResource(op.resourceType, op.resourceId);
  }

  /// Récupère la dernière version serveur d'une ressource précise :
  /// /sync/changes?cursor=serverSeq-1 puis recul par fenêtres de 200,
  /// filtré côté client.
  Future<bool> _pullResource(String resourceType, String resourceId) async {
    final serverSeq = _state.serverSeq ?? 0;
    for (var window = 0; window < 5; window++) {
      var cursor = serverSeq - 1 - window * batchSize;
      if (cursor < 0) cursor = 0;
      final data = await api.get('/sync/changes?cursor=$cursor&limit=200');
      final changes = (data['changes'] as List? ?? const []);
      var found = false;
      for (final raw in changes) {
        final c = Map<String, dynamic>.from(raw as Map);
        if (c['resourceType'] != resourceType ||
            c['resourceId'] != resourceId) {
          continue;
        }
        found = true;
        final op = (c['op'] as String?) ?? 'UPDATE';
        final deleted = (c['deleted'] as bool?) ?? (op == 'DELETE');
        if (deleted) {
          await deleteLocal(resourceType, resourceId);
        } else if (c['data'] is Map) {
          await upsertLocal(
              resourceType, Map<String, dynamic>.from(c['data'] as Map));
        }
      }
      if (found) return true;
      if ((data['hasMore'] as bool?) != true) break;
    }
    _state = _state.copyWith(
        lastError: 'Version serveur introuvable pour $resourceType.');
    _emit();
    return false;
  }

  /// Purge immédiate de tout l'historique résolu (bouton de l'écran Synchro).
  Future<void> purgeHistory() => db.purgeSyncHistory();

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _states.close();
  }
}

// ══════════════════════════ PROVIDERS RIVERPOD ══════════════════════════

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// État complet du moteur de synchronisation.
final syncStateProvider = StreamProvider<LhSyncState>(
    (ref) => ref.watch(syncControllerProvider).states);

/// Force un cycle (family : compteur pour déclencher de nouvelles exécutions).
final syncNowProvider = FutureProvider.family<bool, int>(
    (ref, trigger) => ref.watch(syncControllerProvider).syncNow());

/// Conflits en attente de résolution explicite.
final conflictListProvider = StreamProvider<List<SyncOperation>>(
    (ref) => ref.watch(dbProvider).watchSyncConflicts());

/// Rejets serveur (avec motif).
final rejectedListProvider = StreamProvider<List<SyncOperation>>(
    (ref) => ref.watch(dbProvider).watchSyncRejections());
