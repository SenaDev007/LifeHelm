import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;

// ═══════════════════════════ LABELS MÉTIER (D03) ═══════════════════════════

const taskStatuses = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];

String taskStatusLabel(String s) {
  switch (s) {
    case 'TODO':
      return 'À faire';
    case 'IN_PROGRESS':
      return 'En cours';
    case 'WAITING':
      return 'En attente';
    case 'DONE':
      return 'Terminée';
    case 'CANCELLED':
      return 'Annulée';
    default:
      return s;
  }
}

Color taskStatusColor(String s) {
  switch (s) {
    case 'TODO':
      return LHColors.tacheTodo;
    case 'IN_PROGRESS':
      return LHColors.tacheEnCours;
    case 'WAITING':
      return LHColors.tacheAttente;
    case 'DONE':
      return LHColors.tacheTerminee;
    default:
      return LHColors.tacheAnnulee;
  }

}

const taskPriorities = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];

String taskPriorityLabel(String p) {
  switch (p) {
    case 'LOW':
      return 'Basse';
    case 'NORMAL':
      return 'Normale';
    case 'HIGH':
      return 'Haute';
    case 'URGENT':
      return 'Urgente';
    default:
      return p;
  }
}

Color taskPriorityColor(String p) {
  switch (p) {
    case 'LOW':
      return LHColors.prioBasse;
    case 'NORMAL':
      return LHColors.prioNormale;
    case 'HIGH':
      return LHColors.prioHaute;
    default:
      return LHColors.prioUrgente;
  }
}

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension TaskQueries on AppDatabase {
  Stream<List<Task>> watchTasks(String spaceId, {String? parentId}) {
    var q = select(tasks)..where((t) => t.spaceId.equals(spaceId));
    if (parentId != null) {
      q = q..where((t) => t.parentId.equals(parentId));
    }
    return (q
          ..orderBy([
            (t) => OrderingTerm(expression: t.position),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<Task> watchTask(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).watchSingle();

  Future<List<Task>> getTasks(String spaceId) =>
      (select(tasks)..where((t) => t.spaceId.equals(spaceId))).get();

  Stream<List<TaskAssignee>> watchAssignees(String taskId) =>
      (select(taskAssignees)..where((a) => a.taskId.equals(taskId))).watch();

  Stream<List<TaskDependency>> watchDependencies(String taskId) =>
      (select(taskDependencies)..where((d) => d.taskId.equals(taskId))).watch();

  Stream<List<TaskDependency>> watchDependents(String taskId) =>
      (select(taskDependencies)
            ..where((d) => d.dependsOnTaskId.equals(taskId)))
          .watch();

  Future<Task?> getTask(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Une tâche est bloquée si une dépendance n'est ni terminée ni annulée (D07/D03).
  Future<bool> isBlocked(Task t) async {
    final deps = await (select(taskDependencies)
          ..where((d) => d.taskId.equals(t.id)))
        .get();
    for (final d in deps) {
      final dep = await getTask(d.dependsOnTaskId);
      if (dep != null && dep.status != 'DONE' && dep.status != 'CANCELLED') {
        return true;
      }
    }
    return false;
  }

  Future<void> saveTask(Task t) async {
    await into(tasks).insert(t, mode: InsertMode.insertOrReplace);
    logOp('Task', t.id, t.createdAt == t.updatedAt ? 'CREATE' : 'UPDATE',
        {'title': t.title, 'status': t.status});
  }

  /// Termine la tâche ; les récurrences produisent une occurrence
  /// indépendante pour la prochaine échéance (D03 §8.1-4).
  Future<void> completeTask(Task t, {bool checkDeps = true}) async {
    if (checkDeps && await isBlocked(t)) return;
    final now = DateTime.now();
    await (update(tasks)..where((x) => x.id.equals(t.id))).write(
        TasksCompanion(status: const Value('DONE'), completedAt: Value(now), updatedAt: Value(now)));
    logOp('Task', t.id, 'UPDATE', {'status': 'DONE'});
    await pushNotification(
        spaceId: t.spaceId,
        category: 'TASK',
        priority: 'INFO',
        title: 'Tâche terminée',
        body: '« ${t.title} » est terminée.',
        resourceType: 'TASK',
        resourceId: t.id);

    if (t.recurrenceRuleId != null && t.dueDate != null) {
      final rule = await (select(recurrenceRules)
            ..where((r) => r.id.equals(t.recurrenceRuleId!)))
          .getSingleOrNull();
      if (rule != null) {
        final next = nextOccurrence(rule, t.dueDate!);
        if (next != null) {
          final nextTask = Task(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            spaceId: t.spaceId,
            listId: t.listId,
            parentId: t.parentId,
            title: t.title,
            notes: t.notes,
            status: 'TODO',
            priority: t.priority,
            startDate: t.startDate,
            dueDate: next,
            reminderMinutes: t.reminderMinutes,
            estimatedMinutes: t.estimatedMinutes,
            progressPercent: null,
            recurrenceRuleId: t.recurrenceRuleId,
            position: t.position,
            createdAt: now,
            updatedAt: now,
          );
          await into(tasks).insert(nextTask);
          logOp('Task', nextTask.id, 'CREATE', {'title': t.title, 'recurrence': true});
        }
      }
    }
  }

  Future<void> reopenTask(String id) async {
    final now = DateTime.now();
    await (update(tasks)..where((t) => t.id.equals(id)))
        .write(TasksCompanion(status: const Value('TODO'), completedAt: const Value(null), updatedAt: Value(now)));
    logOp('Task', id, 'UPDATE', {'status': 'TODO'});
  }

  Future<void> setTaskStatus(String id, String status) async {
    final now = DateTime.now();
    await (update(tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(
        status: Value(status),
        completedAt: status == 'DONE' ? Value(now) : const Value.absent(),
        updatedAt: Value(now)));
    logOp('Task', id, 'UPDATE', {'status': status});
  }

  /// Archivage distinct du statut (D03 §8.1-2).
  Future<void> archiveTask(String id, bool archived) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(
        archivedAt: Value(archived ? DateTime.now() : null),
        updatedAt: Value(DateTime.now())));
    logOp('Task', id, 'UPDATE', {'archived': archived});
  }

  Future<void> deleteTask(Task t) async {
    // Supprime la branche de sous-tâches après confirmation (règle appliquée).
    await (delete(taskAssignees)..where((a) => a.taskId.equals(t.id))).go();
    final deps = await (select(taskDependencies)
          ..where((d) => d.taskId.equals(t.id) | d.dependsOnTaskId.equals(t.id)))
        .get();
    await (delete(taskDependencies)
          ..where((d) => d.taskId.equals(t.id) | d.dependsOnTaskId.equals(t.id)))
        .go();
    for (final d in deps) {
      logOp('TaskDependency', d.id, 'DELETE', {});
    }
    final subs = await (select(tasks)..where((x) => x.parentId.equals(t.id))).get();
    await (delete(tasks)..where((x) => x.parentId.equals(t.id))).go();
    for (final s in subs) {
      logOp('Task', s.id, 'DELETE', {'title': s.title, 'cascade': true});
    }
    await (delete(tasks)..where((x) => x.id.equals(t.id))).go();
    logOp('Task', t.id, 'DELETE', {'title': t.title});
  }

  Future<void> addAssignee(String taskId, String name) async {
    await into(taskAssignees).insert(
        TaskAssignee(id: '${taskId}_$name', taskId: taskId, name: name));
  }

  Future<void> removeAssignee(String id) =>
      (delete(taskAssignees)..where((a) => a.id.equals(id))).go();

  Future<void> addDependency(String taskId, String dependsOn) async {
    // Cycles interdits : on remonte les ancêtres de `dependsOn`.
    if (taskId == dependsOn) return;
    var cursor = dependsOn;
    for (var i = 0; i < 100; i++) {
      if (cursor == taskId) return; // cycle détecté
      final deps = await (select(taskDependencies)
            ..where((d) => d.taskId.equals(cursor)))
          .get();
      if (deps.isEmpty) break;
      cursor = deps.first.dependsOnTaskId;
    }
    await into(taskDependencies).insert(TaskDependency(
        id: '${taskId}_$dependsOn', taskId: taskId, dependsOnTaskId: dependsOn));
    logOp('TaskDependency', '${taskId}_$dependsOn', 'CREATE',
        {'dependsOn': dependsOn});
  }

  Future<void> removeDependency(String id) async {
    await (delete(taskDependencies)..where((d) => d.id.equals(id))).go();
    logOp('TaskDependency', id, 'DELETE', {});
  }

  /// Prochaine occurrence d'une règle de récurrence, ou null si terminée.
  String? nextOccurrence(RecurrenceRule rule, String fromKey) {
    var d = fmt.parseKey(fromKey);
    if (rule.untilKey != null && d.isAfter(fmt.parseKey(rule.untilKey!))) {
      return null;
    }
    switch (rule.freq) {
      case 'DAILY':
        d = fmt.addDays(d, rule.interval);
        break;
      case 'WEEKLY':
        final wd = rule.byWeekday != null
            ? ((jsonDecode(rule.byWeekday!) as List).cast<int>()..sort())
            : <int>[d.weekday];
        if (wd.isEmpty) wd.add(d.weekday);
        // Prochain jour prévu après `d`.
        for (var i = 1; i <= 7 * rule.interval + 7; i++) {
          final cand = fmt.addDays(d, i);
          final weeks = fmt.daysBetween(fmt.startOfWeek(d), fmt.startOfWeek(cand)) ~/ 7;
          if (wd.contains(cand.weekday) && weeks % rule.interval == 0) {
            d = cand;
            break;
          }
        }
        break;
      case 'MONTHLY':
        d = fmt.addMonths(d, rule.interval);
        break;
      case 'YEARLY':
        d = fmt.addMonths(d, 12 * rule.interval);
        break;
      default:
        return null;
    }
    if (rule.untilKey != null && d.isAfter(fmt.parseKey(rule.untilKey!))) {
      return null;
    }
    return fmt.dateKey(d);
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final tasksProvider = StreamProvider.family<List<Task>, String>((ref, spaceId) =>
    ref.watch(dbProvider).watchTasks(spaceId));

final taskListsProvider =
    StreamProvider.family<List<TaskList>, String>((ref, spaceId) {
      final db = ref.watch(dbProvider);
      return (db.select(db.taskLists)
            ..where((l) => l.spaceId.equals(spaceId))
            ..orderBy([(l) => OrderingTerm(expression: l.name)]))
          .watch();
    });

final taskProvider = StreamProvider.family<Task?, String>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.tasks)..where((t) => t.id.equals(id)))
      .watchSingleOrNull();
});

final taskAssigneesProvider =
    StreamProvider.family<List<TaskAssignee>, String>(
        (ref, taskId) => ref.watch(dbProvider).watchAssignees(taskId));

final taskDependenciesProvider =
    StreamProvider.family<List<TaskDependency>, String>(
        (ref, taskId) => ref.watch(dbProvider).watchDependencies(taskId));

// ═══════════════════════════ ÉCRAN : LISTE ═══════════════════════════

enum _TaskFilter { today, late, week, all }

/// Liste des activités de l'espace actif — D03.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final tasksAsync = ref.watch(tasksProvider(spaceId));
    final listsAsync = ref.watch(taskListsProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Activités'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/task/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle tâche'),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
            icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (allTasks) {
          final lists = listsAsync.valueOrNull ?? <TaskList>[];
          return _TasksBody(
              tasks: allTasks, lists: lists, spaceId: spaceId);
        },
      ),
    );
  }
}

class _TasksBody extends StatefulWidget {
  const _TasksBody(
      {required this.tasks, required this.lists, required this.spaceId});

  final List<Task> tasks;
  final List<TaskList> lists;
  final String spaceId;

  @override
  State<_TasksBody> createState() => _TasksBodyState();
}

class _TasksBodyState extends State<_TasksBody> {
  _TaskFilter _filter = _TaskFilter.today;
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = fmt.today();
    final todayKey = fmt.dateKey(today);
    final weekEnd = fmt.dateKey(fmt.addDays(today, 7));

    // Tâches racines seulement (les sous-tâches apparaissent dans le détail).
    var visible = widget.tasks.where((t) => t.parentId == null).toList();

    switch (_filter) {
      case _TaskFilter.today:
        visible = visible
            .where((t) => t.dueDate != null && t.dueDate! == todayKey)
            .toList();
        break;
      case _TaskFilter.late:
        visible = visible
            .where((t) =>
                t.dueDate != null &&
                t.dueDate!.compareTo(todayKey) < 0 &&
                t.status != 'DONE' &&
                t.status != 'CANCELLED')
            .toList();
        break;
      case _TaskFilter.week:
        visible = visible.where((t) =>
            t.dueDate != null &&
            t.dueDate!.compareTo(todayKey) >= 0 &&
            t.dueDate!.compareTo(weekEnd) <= 0).toList();
        break;
      case _TaskFilter.all:
        break;
    }
    if (!_showDone) {
      visible = visible.where((t) =>
              t.status != 'DONE' &&
              t.status != 'CANCELLED' &&
              t.archivedAt == null)
          .toList();
    } else {
      visible = visible.where((t) => t.archivedAt == null).toList();
    }

    final active = visible.where((t) => t.status != 'DONE' && t.status != 'CANCELLED').toList()
      ..sort(_compareTasks);
    final done = visible.where((t) => t.status == 'DONE' || t.status == 'CANCELLED').toList();

    return Column(children: [
      // Filtres
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('Aujourd\'hui', _TaskFilter.today, activeCount: null),
                const SizedBox(width: 6),
                _chip('En retard', _TaskFilter.late, activeCount: null),
                const SizedBox(width: 6),
                _chip('Cette semaine', _TaskFilter.week, activeCount: null),
                const SizedBox(width: 6),
                _chip('Tout', _TaskFilter.all, activeCount: null),
              ]),
            ),
          ),
          IconButton(
            tooltip: _showDone ? 'Masquer terminées' : 'Afficher terminées',
            onPressed: () => setState(() => _showDone = !_showDone),
            icon: Icon(_showDone
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
          ),
        ]),
      ),
      Expanded(
        child: visible.isEmpty
            ? EmptyState(
                illustration: 'assets/illustrations/tasks.png',
                icon: Icons.task_alt_outlined,
                message: 'Aucune tâche ici',
                hint: 'Créez votre première tâche pour organiser votre journée.',
                action: FilledButton.tonal(
                  onPressed: () => context.push('/task/new'),
                  child: const Text('Nouvelle tâche'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 96, top: 4),
                itemCount: active.length + (done.isEmpty ? 0 : done.length + 1),
                itemBuilder: (context, i) {
                  if (i < active.length) {
                    return _TaskTile(
                        task: active[i],
                        lists: widget.lists,
                        spaceId: widget.spaceId);
                  }
                  final idx = i - active.length;
                  if (idx == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text('Terminées & annulées',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    );
                  }
                  return _TaskTile(
                      task: done[idx - 1],
                      lists: widget.lists,
                      spaceId: widget.spaceId);
                },
              ),
      ),
    ]);
  }

  /// Tri : priorité manuelle puis échéance (le classement hybride complet
  /// du cockpit reste distinct — D03 §8.2).
  int _compareTasks(Task a, Task b) {
    final p = taskPriorities.indexOf(b.priority)
        .compareTo(taskPriorities.indexOf(a.priority));
    if (p != 0) return p;
    final ad = a.dueDate ?? '9999-99-99';
    final bd = b.dueDate ?? '9999-99-99';
    return ad.compareTo(bd);
  }

  Widget _chip(String label, _TaskFilter value, {int? activeCount}) {
    final selected = _filter == value;
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(label + (activeCount != null ? ' ($activeCount)' : '')),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      // Règle n°3 : libellé lisible sur fond doré sélectionné (l'ancien
      // ternaire était inversé — blanc sur lavis clair, noir sur surface
      // sombre : illisible dans les deux thèmes).
      labelStyle: TextStyle(
          color: selected
              ? LHContrast.selectedChipLabel(theme.brightness)
              : null),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile(
      {required this.task, required this.lists, required this.spaceId});

  final Task task;
  final List<TaskList> lists;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final todayKey = fmt.dateKey(fmt.today());
    final isDone = task.status == 'DONE';
    final isLate = task.dueDate != null &&
        task.dueDate!.compareTo(todayKey) < 0 &&
        !isDone &&
        task.status != 'CANCELLED';
    final listName = task.listId == null
        ? null
        : lists.where((l) => l.id == task.listId).firstOrNull?.name;
    final depsAsync = ref.watch(taskDependenciesProvider(task.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LHCard(
        onTap: () => context.push('/task/${task.id}'),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Case à cocher / statut
          GestureDetector(
            onTap: () async {
              if (isDone) {
                await db.reopenTask(task.id);
              } else {
                final blocked = await db.isBlocked(task);
                if (blocked && context.mounted) {
                  lhToast(context,
                      'Tâche bloquée par une dépendance non terminée.');
                  return;
                }
                await db.completeTask(task);
              }
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: isDone ? LHColors.tacheTerminee : taskStatusColor(task.status),
                    width: 2),
                color: isDone ? LHColors.tacheTerminee.withValues(alpha: 0.15) : null,
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 20, color: LHColors.tacheTerminee)
                  : task.status == 'IN_PROGRESS'
                      ? Icon(Icons.more_horiz,
                          size: 18, color: LHColors.tacheEnCours)
                      : null,
            ),
          ),
          const SizedBox(width: LHSpacing.md),
          // Contenu
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (task.priority != 'NORMAL')
                  _miniBadge(taskPriorityLabel(task.priority),
                      taskPriorityColor(task.priority)),
                if (task.dueDate != null)
                  _miniBadge(
                      fmt.humanDate(fmt.parseKey(task.dueDate!)),
                      isLate
                          ? LHColors.erreur
                          : task.dueDate == todayKey
                              ? LHColors.or
                              : theme.colorScheme.onSurfaceVariant),
                if (task.recurrenceRuleId != null)
                  _miniBadge('Récurrente', LHColors.info, icon: Icons.repeat, size: 12),
                if ((depsAsync.valueOrNull ?? []).isNotEmpty)
                  _miniBadge('Dépendance', LHColors.prioHaute,
                      icon: Icons.link, size: 12),
                if (listName != null)
                  _miniBadge(listName, theme.colorScheme.onSurfaceVariant, size: 12),
              ]),
            ]),
          ),
          // Menu
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'complete':
                  await db.completeTask(task);
                  break;
                case 'reopen':
                  await db.reopenTask(task.id);
                  break;
                case 'archive':
                  await db.archiveTask(task.id, true);
                  if (context.mounted) {
                    lhToast(context, 'Tâche archivée');
                  }
                  break;
                case 'delete':
                  final ok = await lhConfirm(context,
                      title: 'Supprimer la tâche ?',
                      message:
                          '« ${task.title} » et ses sous-tâches seront supprimées. La suppression est journalisée pour la synchronisation.',
                      confirmLabel: 'Supprimer',
                      destructive: true);
                  if (ok) await db.deleteTask(task);
                  break;
              }
            },
            itemBuilder: (_) => [
              if (!isDone)
                const PopupMenuItem(value: 'complete', child: Text('Marquer terminée')),
              if (isDone)
                const PopupMenuItem(value: 'reopen', child: Text('Rouvrir')),
              const PopupMenuItem(value: 'archive', child: Text('Archiver')),
              const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _miniBadge(String label, Color color, {IconData? icon, double size = 13}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LHRadius.full),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: size, color: color),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: TextStyle(
                fontSize: size, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ═══════════════════════════ ÉCRAN : ÉDITION ═══════════════════════════

/// Création / édition de tâche — statuts, priorité, dates, récurrence,
/// sous-tâches, dépendances, assignations (D03).
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({super.key, this.id, this.parentId});

  final String? id;
  final String? parentId;

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _subtaskCtrl = TextEditingController();
  final _assigneeCtrl = TextEditingController();

  String _status = 'TODO';
  String _priority = 'NORMAL';
  String? _listId;
  String? _startDate;
  String? _dueDate;
  int? _estimated;
  String? _recurrenceFreq;
  List<int> _recurrenceDays = [DateTime.monday];
  List<Task> _subtasks = [];
  List<Task> _deps = [];
  List<String> _assignees = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _subtaskCtrl.dispose();
    _assigneeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final db = ref.read(dbProvider);
    if (widget.id != null) {
      final t = await db.getTask(widget.id!);
      if (t != null) {
        _title.text = t.title;
        _notes.text = t.notes ?? '';
        _status = t.status;
        _priority = t.priority;
        _listId = t.listId;
        _startDate = t.startDate;
        _dueDate = t.dueDate;
        _estimated = t.estimatedMinutes;
        if (t.recurrenceRuleId != null) {
          final rule = await (db.select(db.recurrenceRules)
                ..where((r) => r.id.equals(t.recurrenceRuleId!)))
              .getSingleOrNull();
          if (rule != null) {
            _recurrenceFreq = rule.freq == 'WEEKLY' ? 'WEEKLY' : rule.freq;
            if (rule.byWeekday != null) {
              _recurrenceDays =
                  ((jsonDecode(rule.byWeekday!) as List).cast<int>());
            }
          }
        }
        final subs = await (db.select(db.tasks)
              ..where((x) => x.parentId.equals(t.id)))
            .get();
        _subtasks = subs;
        final deps = await db.watchDependencies(t.id).first;
        final depTasks = <Task>[];
        for (final d in deps) {
          final dt = await db.getTask(d.dependsOnTaskId);
          if (dt != null) depTasks.add(dt);
        }
        _deps = depTasks;
        final assignees = await db.watchAssignees(t.id).first;
        _assignees = assignees.map((a) => a.name).toList();
      }
    } else if (widget.parentId != null) {
      final parent = await db.getTask(widget.parentId!);
      if (parent != null) {
        _listId = parent.listId;
        _dueDate = parent.dueDate;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = fmt.parseKey((isStart ? _startDate : _dueDate) ??
        fmt.dateKey(fmt.today()));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = fmt.dateKey(picked);
        } else {
          _dueDate = fmt.dateKey(picked);
        }
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      lhToast(context, 'Le titre est obligatoire.');
      return;
    }
    setState(() => _saving = true);
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final id = widget.id ?? 'task_${now.microsecondsSinceEpoch}';

    String? ruleId;
    if (_recurrenceFreq != null && _dueDate != null) {
      ruleId = 'rule_${id}_${_recurrenceFreq}';
      final byWd = _recurrenceFreq == 'WEEKLY' ? jsonEncode(_recurrenceDays) : null;
      await db.into(db.recurrenceRules).insert(
          RecurrenceRule(
              id: ruleId, freq: _recurrenceFreq!, interval: 1, byWeekday: byWd),
          mode: InsertMode.insertOrReplace);
      db.logOp('RecurrenceRule', ruleId, 'CREATE_OR_UPDATE',
          {'freq': _recurrenceFreq});
    }

    final existing = await db.getTask(id);
    final task = Task(
      id: id,
      spaceId: existing?.spaceId ?? ref.read(activeSpaceIdProvider),
      listId: _listId,
      parentId: existing?.parentId ?? widget.parentId,
      title: _title.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      status: _status,
      priority: _priority,
      startDate: _startDate,
      dueDate: _dueDate,
      reminderMinutes: existing?.reminderMinutes,
      estimatedMinutes: _estimated,
      progressPercent: existing?.progressPercent,
      recurrenceRuleId: ruleId,
      position: existing?.position ?? 0,
      completedAt: _status == 'DONE' ? (existing?.completedAt ?? now) : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveTask(task);

    // Assignations (plusieurs responsables — D03 §8.1-6)
    final current = await db.watchAssignees(id).first;
    for (final a in current) {
      if (!_assignees.contains(a.name)) await db.removeAssignee(a.id);
    }
    for (final name in _assignees) {
      if (!current.any((a) => a.name == name)) {
        await db.addAssignee(id, name);
      }
    }

    // Dépendances
    final currentDeps = await db.watchDependencies(id).first;
    for (final d in currentDeps) {
      if (!_deps.any((t) => t.id == d.dependsOnTaskId)) {
        await db.removeDependency(d.id);
      }
    }
    for (final dep in _deps) {
      if (!currentDeps.any((d) => d.dependsOnTaskId == dep.id)) {
        await db.addDependency(id, dep.id);
      }
    }

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final listsAsync = ref.watch(taskListsProvider(spaceId));
    final lists = listsAsync.valueOrNull ?? [];
    final isNew = widget.id == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew
            ? widget.parentId != null
                ? 'Nouvelle sous-tâche'
                : 'Nouvelle tâche'
            : 'Modifier la tâche'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleMedium,
            decoration: const InputDecoration(
                hintText: 'Que faut-il faire ?', border: InputBorder.none),
            autofocus: isNew,
          ),
          const Divider(),
          // Statut
          LabeledField(
            label: 'Statut',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in taskStatuses)
                  ChoiceChip(
                    label: Text(taskStatusLabel(s)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          // Priorité manuelle (distincte du classement du cockpit — D03 §8.2)
          LabeledField(
            label: 'Priorité manuelle',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in taskPriorities)
                  ChoiceChip(
                    label: Text(taskPriorityLabel(p)),
                                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                    labelStyle: TextStyle(
                        color: _priority == p
                            ? LHContrast.selectedChipLabel(
                                Theme.of(context).brightness)
                            : null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          // Dates : début / échéance / rappel (distincts — D03 §8.2)
          Row(children: [
            Expanded(
              child: LabeledField(
                label: 'Début (optionnel)',
                child: _dateField(_startDate, () => _pickDate(true)),
              ),
            ),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: LabeledField(
                label: 'Échéance (optionnel)',
                child: _dateField(_dueDate, () => _pickDate(false)),
              ),
            ),
          ]),
          const SizedBox(height: LHSpacing.lg),
          // Liste + durée estimée
          Row(children: [
            Expanded(
              child: LabeledField(
                label: 'Liste',
                child: DropdownButtonFormField<String>(
                  value: _listId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sans liste')),
                    ...lists.map((l) =>
                        DropdownMenuItem(value: l.id, child: Text(l.name))),
                  ],
                  onChanged: (v) => setState(() => _listId = v),
                ),
              ),
            ),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: LabeledField(
                label: 'Durée estimée',
                child: DropdownButtonFormField<int>(
                  value: _estimated,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final m in [15, 30, 45, 60, 90, 120, 180, 240])
                      DropdownMenuItem(
                          value: m, child: Text('$m min')),
                  ],
                  onChanged: (v) => setState(() => _estimated = v),
                ),
              ),
            ),
          ]),
          const SizedBox(height: LHSpacing.lg),
          // Récurrence
          LabeledField(
            label: 'Récurrence (occurrences indépendantes)',
            child: Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Aucune'),
                  selected: _recurrenceFreq == null,
                  onSelected: (_) => setState(() => _recurrenceFreq = null),
                ),
                for (final f in ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'])
                  ChoiceChip(
                    label: Text({
                      'DAILY': 'Quotidienne',
                      'WEEKLY': 'Hebdomadaire',
                      'MONTHLY': 'Mensuelle',
                      'YEARLY': 'Annuelle',
                    }[f]!),
                    selected: _recurrenceFreq == f,
                    onSelected: (_) => setState(() => _recurrenceFreq = f),
                  ),
              ],
            ),
          ),
          if (_recurrenceFreq == 'WEEKLY')
            Padding(
              padding: const EdgeInsets.only(top: LHSpacing.sm),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(fmt.weekdaysFr[d - 1]),
                      selected: _recurrenceDays.contains(d),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _recurrenceDays.add(d);
                        } else {
                          _recurrenceDays.remove(d);
                        }
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: LHSpacing.lg),
          // Sous-tâches (multi-niveaux dès le MVP — D03 §8.1-3)
          LabeledField(
            label: 'Sous-tâches',
            child: Column(children: [
              for (final (i, st) in _subtasks.indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: GestureDetector(
                    onTap: () => setState(() {
                      _subtasks[i] = st.copyWith(
                          status: st.status == 'DONE' ? 'TODO' : 'DONE');
                    }),
                    child: Icon(
                      st.status == 'DONE'
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: st.status == 'DONE'
                          ? LHColors.tacheTerminee
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(st.title,
                      style: TextStyle(
                          decoration: st.status == 'DONE'
                              ? TextDecoration.lineThrough
                              : null)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _subtasks.removeAt(i)),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Ajouter une sous-tâche…'),
                    onSubmitted: (v) => _addSubtask(v),
                  ),
                ),
                IconButton(
                    onPressed: () => _addSubtask(_subtaskCtrl.text),
                    icon: const Icon(Icons.add)),
              ]),
            ]),
          ),
          const SizedBox(height: LHSpacing.lg),
          // Dépendances (requises dès le MVP — D07)
          LabeledField(
            label: 'Dépend de (blocage)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final d in _deps)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link,
                      color: d.status == 'DONE'
                          ? LHColors.tacheTerminee
                          : LHColors.prioHaute),
                  title: Text(d.title),
                  subtitle: d.status == 'DONE'
                      ? const Text('Terminée',
                          style: TextStyle(
                              color: LHColors.tacheTerminee, fontSize: 12))
                      : const Text('En cours — bloque cette tâche',
                          style: TextStyle(
                              color: LHColors.prioHaute, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _deps.remove(d)),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _pickDependency(),
                icon: const Icon(Icons.add_link),
                label: const Text('Ajouter une dépendance'),
              ),
            ]),
          ),
          const SizedBox(height: LHSpacing.lg),
          // Assignations multiples
          LabeledField(
            label: 'Responsables',
            child: Column(children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in _assignees)
                    InputChip(
                      label: Text(a),
                      onDeleted: () => setState(() => _assignees.remove(a)),
                    ),
                ],
              ),
              if (_assignees.isNotEmpty) const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _assigneeCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Nom du responsable…'),
                    onSubmitted: (v) => _addAssignee(v),
                  ),
                ),
                IconButton(
                    onPressed: () => _addAssignee(_assigneeCtrl.text),
                    icon: const Icon(Icons.person_add_alt)),
              ]),
            ]),
          ),
          const SizedBox(height: LHSpacing.lg),
          LabeledField(
            label: 'Notes',
            child: TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText: 'Détails, contexte, liens…'),
            ),
          ),
          const SizedBox(height: LHSpacing.xl),
        ]),
      ),
    );
  }

  void _addSubtask(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() {
      _subtasks.add(Task(
        id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
        spaceId: ref.read(activeSpaceIdProvider),
        parentId: widget.id ?? 'pending',
        title: v,
        status: 'TODO',
        priority: 'NORMAL',
        position: _subtasks.length,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      _subtaskCtrl.clear();
    });
  }

  void _addAssignee(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() {
      _assignees.add(v);
      _assigneeCtrl.clear();
    });
  }

  Future<void> _pickDependency() async {
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final candidates = await db.getTasks(spaceId);
    final selfId = widget.id;
    final selectable = candidates
        .where((t) =>
            t.id != selfId &&
            !_deps.any((d) => d.id == t.id) &&
            t.status != 'DONE')
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: selectable.isEmpty
              ? [
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucune autre tâche disponible.'))
                ]
              : [
                  for (final t in selectable)
                    ListTile(
                      leading: const Icon(Icons.task_alt_outlined),
                      title: Text(t.title),
                      trailing: Text(
                          t.dueDate != null
                              ? fmt.humanDate(fmt.parseKey(t.dueDate!))
                              : '',
                          style: const TextStyle(fontSize: 12)),
                      onTap: () {
                        setState(() => _deps.add(t));
                        Navigator.pop(ctx);
                      },
                    ),
                ],
        ),
      ),
    );
  }

  Widget _dateField(String? key, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LHRadius.md),
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(
          key != null ? fmt.humanDate(fmt.parseKey(key)) : 'Non définie',
          style: TextStyle(
            color: key != null ? null : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }
}
