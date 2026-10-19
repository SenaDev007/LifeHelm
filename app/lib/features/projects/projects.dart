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

// ═══════════════════════════ LABELS MÉTIER (D07) ═══════════════════════════

const projectStatuses = ['PLANNED', 'ACTIVE', 'ON_HOLD', 'COMPLETED', 'CANCELLED'];

String projectStatusLabel(String s) => switch (s) {
      'PLANNED' => 'Planifié',
      'ACTIVE' => 'Actif',
      'ON_HOLD' => 'En pause',
      'COMPLETED' => 'Terminé',
      'CANCELLED' => 'Annulé',
      _ => s,
    };

Color projectStatusColor(String s) => switch (s) {
      'PLANNED' => LHColors.neutre,
      'ACTIVE' => LHColors.info,
      'ON_HOLD' => LHColors.alerte,
      'COMPLETED' => LHColors.emeraudeClair, // #10A878 (CDC D07)
      _ => LHColors.erreur, // #E05B5B
    };

const goalStatuses = ['NOT_STARTED', 'ACTIVE', 'PAUSED', 'ACHIEVED', 'ABANDONED'];

String goalStatusLabel(String s) => switch (s) {
      'NOT_STARTED' => 'Non commencé',
      'ACTIVE' => 'Actif',
      'PAUSED' => 'En pause',
      'ACHIEVED' => 'Atteint',
      'ABANDONED' => 'Abandonné',
      _ => s,
    };

Color goalStatusColor(String s) => switch (s) {
      'NOT_STARTED' => LHColors.neutre,
      'ACTIVE' => LHColors.info,
      'PAUSED' => LHColors.alerte,
      'ACHIEVED' => LHColors.emeraudeClair,
      _ => LHColors.erreur,
    };

const goalCategories = ['PERSONAL', 'CAREER', 'FAMILY', 'FINANCE'];

String goalCategoryLabel(String c) => switch (c) {
      'PERSONAL' => 'Personnel',
      'CAREER' => 'Carrière',
      'FAMILY' => 'Famille',
      'FINANCE' => 'Finance',
      _ => c,
    };

Color goalCategoryColor(String c) => switch (c) {
      'PERSONAL' => LHColors.or,
      'CAREER' => LHColors.espacePro,
      'FAMILY' => LHColors.espaceFamille,
      _ => LHColors.alerte,
    };

IconData goalCategoryIcon(String c) => switch (c) {
      'PERSONAL' => Icons.person_outline,
      'CAREER' => Icons.work_outline,
      'FAMILY' => Icons.family_restroom,
      _ => Icons.savings_outlined,
    };

String stageStatusLabel(String s) => switch (s) {
      'TODO' => 'À faire',
      'IN_PROGRESS' => 'En cours',
      _ => 'Terminée',
    };

Color stageStatusColor(String s) => switch (s) {
      'TODO' => LHColors.tacheTodo,
      'IN_PROGRESS' => LHColors.tacheEnCours,
      _ => LHColors.tacheTerminee,
    };

String memberRoleLabel(String r) =>
    r == 'LEAD' ? 'Responsable' : 'Contributeur';

// Libellés de statut de tâche (affichage des tâches liées — D03/D07).
String _taskStatusLabel(String s) => switch (s) {
      'TODO' => 'À faire',
      'IN_PROGRESS' => 'En cours',
      'WAITING' => 'En attente',
      'DONE' => 'Terminée',
      _ => 'Annulée',
    };

Color _taskStatusColor(String s) => switch (s) {
      'TODO' => LHColors.tacheTodo,
      'IN_PROGRESS' => LHColors.tacheEnCours,
      'WAITING' => LHColors.tacheAttente,
      'DONE' => LHColors.tacheTerminee,
      _ => LHColors.tacheAnnulee,
    };

/// Progression automatique d'un projet : tâches DONE / tâches non annulées
/// (CDC D07 §12.1-2).
double autoProjectProgress(List<LinkedTask> linked) {
  final relevant =
      linked.where((l) => l.task.status != 'CANCELLED').toList();
  if (relevant.isEmpty) return 0;
  return relevant.where((l) => l.task.status == 'DONE').length /
      relevant.length;
}

/// Progression relative d'un indicateur, sensible à la direction.
double metricProgress(GoalMetric m) {
  final delta = m.direction == 'DECREASE'
      ? m.startValue - m.targetValue
      : m.targetValue - m.startValue;
  if (delta == 0) return m.currentValue >= m.targetValue ? 1 : 0;
  return ((m.currentValue - m.startValue) / delta).clamp(0.0, 1.0);
}

/// Affiche une valeur d'indicateur : « 1 250 000 » ou « 3,5 ».
String fmtMetricValue(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e15) {
    final digits = v.truncate().abs().toString();
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      sb.write(digits[i]);
      final remaining = digits.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) sb.write('\u00A0');
    }
    return '${v < 0 ? '−' : ''}$sb';
  }
  return v.toStringAsFixed(1);
}

// ═════════════════ LIEN OBJECTIF ↔ PROJET (table auxiliaire) ═════════════════

/// Le schéma consolidé n'expose pas encore de table typée `GoalProjectLinks`
/// (D07 §12.7) ; une table auxiliaire strictement équivalente est gérée en SQL
/// brut et journalisée comme les autres ressources via `logOp`. Aucune
/// modification du schéma généré n'étant permise à cette étape, c'est le
/// moyen le plus sûr de conserver la fonctionnalité (et sa trace de synchro).
class GoalProjectLink {
  const GoalProjectLink(
      {required this.id, required this.goalId, required this.projectId});

  final String id;
  final String goalId;
  final String projectId;
}

Future<void>? _goalProjectLinksInit;

Future<void> ensureGoalProjectLinks(AppDatabase db) =>
    _goalProjectLinksInit ??= db.customStatement(
        'CREATE TABLE IF NOT EXISTS goal_project_links '
        '(id TEXT NOT NULL PRIMARY KEY, goal_id TEXT NOT NULL, '
        'project_id TEXT NOT NULL)');

/// Tâche liée à un projet (lien + tâche jointe).
class LinkedTask {
  const LinkedTask({required this.linkId, required this.task});

  final String linkId;
  final Task task;
}

// ═══════════════════════════ REQUÊTES — PROJETS ═══════════════════════════

extension ProjectQueries on AppDatabase {
  Stream<List<Project>> watchProjects(String spaceId) {
    return (select(projects)
          ..where((p) => p.spaceId.equals(spaceId) & p.archivedAt.isNull())
          ..orderBy([
            (p) =>
                OrderingTerm(expression: p.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<Project?> watchProject(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<Project?> getProject(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<Project>> getProjects(String spaceId) =>
      (select(projects)..where((p) => p.spaceId.equals(spaceId))).get();

  Stream<List<ProjectStage>> watchStages(String projectId) {
    return (select(projectStages)
          ..where((s) => s.projectId.equals(projectId))
          ..orderBy([(s) => OrderingTerm(expression: s.position)]))
        .watch();
  }

  Stream<List<ProjectMilestone>> watchMilestones(String projectId) {
    return (select(projectMilestones)
          ..where((m) => m.projectId.equals(projectId))
          ..orderBy([(m) => OrderingTerm(expression: m.position)]))
        .watch();
  }

  Stream<List<ProjectMember>> watchProjectMembers(String projectId) {
    return (select(projectMembers)
          ..where((m) => m.projectId.equals(projectId))
          ..orderBy([
            (m) => OrderingTerm(expression: m.role, mode: OrderingMode.desc),
            (m) => OrderingTerm(expression: m.name),
          ]))
        .watch();
  }

  /// Tâches liées via ProjectTaskLinks (jointure, flux réactif).
  Stream<List<LinkedTask>> watchProjectTasks(String projectId) {
    final query = select(projectTaskLinks).join([
      innerJoin(tasks, tasks.id.equalsExp(projectTaskLinks.taskId)),
    ])
      ..where(projectTaskLinks.projectId.equals(projectId));
    return query.watch().map((rows) => [
          for (final r in rows)
            LinkedTask(
                linkId: r.readTable(projectTaskLinks).id,
                task: r.readTable(tasks)),
        ]);
  }

  Future<void> saveProject(Project p, {bool existed = false}) async {
    await into(projects).insert(p, mode: InsertMode.insertOrReplace);
    logOp('Project', p.id, existed ? 'UPDATE' : 'CREATE',
        {'name': p.name, 'status': p.status});
  }

  Future<void> setProjectStatus(String id, String status) async {
    await (update(projects)..where((p) => p.id.equals(id)))
        .write(ProjectsCompanion(
            status: Value(status), updatedAt: Value(DateTime.now())));
    logOp('Project', id, 'UPDATE', {'status': status});
  }

  Future<void> updateProjectDescription(String id, String? description) async {
    await (update(projects)..where((p) => p.id.equals(id)))
        .write(ProjectsCompanion(
            description: Value(description),
            updatedAt: Value(DateTime.now())));
    logOp('Project', id, 'UPDATE', {'description': description ?? ''});
  }

  /// Ajustement manuel de la progression — traçable ; null = retour au calcul
  /// automatique (CDC D07 §12.1-2).
  Future<void> setManualProgress(String id, int? percent) async {
    await (update(projects)..where((p) => p.id.equals(id)))
        .write(ProjectsCompanion(
            manualProgress: Value(percent),
            updatedAt: Value(DateTime.now())));
    logOp('Project', id, 'UPDATE', {'manualProgress': percent});
  }

  /// L'archivage est distinct du statut (CDC D07 §12.3).
  Future<void> archiveProject(String id, bool archived) async {
    await (update(projects)..where((p) => p.id.equals(id)))
        .write(ProjectsCompanion(
            archivedAt: Value(archived ? DateTime.now() : null),
            updatedAt: Value(DateTime.now())));
    logOp('Project', id, 'UPDATE', {'archived': archived});
  }

  Future<void> deleteProject(String id) async {
    final p = await getProject(id);
    await (delete(projectMembers)..where((m) => m.projectId.equals(id))).go();
    await (delete(projectStages)..where((s) => s.projectId.equals(id))).go();
    await (delete(projectMilestones)..where((m) => m.projectId.equals(id)))
        .go();
    await (delete(projectTaskLinks)..where((l) => l.projectId.equals(id)))
        .go();
    await ensureGoalProjectLinks(this);
    await customUpdate('DELETE FROM goal_project_links WHERE project_id = ?',
        variables: [Variable<String>(id)], updates: {projects});
    await (delete(projects)..where((x) => x.id.equals(id))).go();
    logOp('Project', id, 'DELETE', {'name': p?.name ?? ''});
  }

  // —— Étapes (distinctes des jalons — D07 §12.1-1) ——

  Future<void> addStage(String projectId, String name) async {
    final existing = await (select(projectStages)
          ..where((s) => s.projectId.equals(projectId)))
        .get();
    final s = ProjectStage(
      id: 'stage_${DateTime.now().microsecondsSinceEpoch}',
      projectId: projectId,
      name: name,
      position: existing.length,
      status: 'TODO',
    );
    await into(projectStages).insert(s);
    logOp('ProjectStage', s.id, 'CREATE',
        {'name': name, 'projectId': projectId});
  }

  /// Cycle TODO → IN_PROGRESS → DONE → TODO.
  Future<void> cycleStage(ProjectStage s) async {
    final next = switch (s.status) {
      'TODO' => 'IN_PROGRESS',
      'IN_PROGRESS' => 'DONE',
      _ => 'TODO',
    };
    await (update(projectStages)..where((x) => x.id.equals(s.id)))
        .write(ProjectStagesCompanion(status: Value(next)));
    logOp('ProjectStage', s.id, 'UPDATE', {'status': next});
  }

  Future<void> deleteStage(String id) async {
    await (delete(projectStages)..where((s) => s.id.equals(id))).go();
    logOp('ProjectStage', id, 'DELETE', {});
  }

  // —— Jalons ——

  Future<void> addMilestone(String projectId, String name, String? dueDate) async {
    final existing = await (select(projectMilestones)
          ..where((m) => m.projectId.equals(projectId)))
        .get();
    final m = ProjectMilestone(
      id: 'ms_${DateTime.now().microsecondsSinceEpoch}',
      projectId: projectId,
      name: name,
      dueDate: dueDate,
      status: 'PENDING',
      position: existing.length,
    );
    await into(projectMilestones).insert(m);
    logOp('ProjectMilestone', m.id, 'CREATE',
        {'name': name, 'projectId': projectId, 'dueDate': dueDate});
  }

  /// Marque atteint / rouvre un jalon.
  Future<void> toggleMilestone(ProjectMilestone m) async {
    final next = m.status == 'REACHED' ? 'PENDING' : 'REACHED';
    await (update(projectMilestones)..where((x) => x.id.equals(m.id)))
        .write(ProjectMilestonesCompanion(status: Value(next)));
    logOp('ProjectMilestone', m.id, 'UPDATE', {'status': next});
  }

  Future<void> deleteMilestone(String id) async {
    await (delete(projectMilestones)..where((m) => m.id.equals(id))).go();
    logOp('ProjectMilestone', id, 'DELETE', {});
  }

  // —— Membres : responsables & contributeurs dès le MVP (D07 §12.1-4) ——

  Future<void> addMember(String projectId, String name, String role) async {
    final m = ProjectMember(
      id: 'pm_${DateTime.now().microsecondsSinceEpoch}',
      projectId: projectId,
      name: name,
      role: role,
    );
    await into(projectMembers).insert(m);
    logOp('ProjectMember', m.id, 'CREATE', {'name': name, 'role': role});
  }

  Future<void> removeMember(String id) async {
    await (delete(projectMembers)..where((m) => m.id.equals(id))).go();
    logOp('ProjectMember', id, 'DELETE', {});
  }

  // —— Tâches liées : les tâches restent gérées par le module Activités (D07 §12.6) ——

  Future<void> linkTask(String projectId, String taskId) async {
    final dup = await (select(projectTaskLinks)
          ..where((l) =>
              l.projectId.equals(projectId) & l.taskId.equals(taskId)))
        .get();
    if (dup.isNotEmpty) return;
    final l = ProjectTaskLink(
      id: 'ptl_${DateTime.now().microsecondsSinceEpoch}',
      projectId: projectId,
      taskId: taskId,
    );
    await into(projectTaskLinks).insert(l);
    logOp('ProjectTaskLink', l.id, 'CREATE',
        {'projectId': projectId, 'taskId': taskId});
  }

  Future<void> unlinkTask(String linkId) async {
    await (delete(projectTaskLinks)..where((l) => l.id.equals(linkId))).go();
    logOp('ProjectTaskLink', linkId, 'DELETE', {});
  }
}

// ═══════════════════════════ REQUÊTES — OBJECTIFS ═══════════════════════════

extension GoalQueries on AppDatabase {
  Stream<List<Goal>> watchGoals(String spaceId) {
    return (select(goals)
          ..where((g) => g.spaceId.equals(spaceId))
          ..orderBy([
            (g) =>
                OrderingTerm(expression: g.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<Goal?> watchGoal(String id) =>
      (select(goals)..where((g) => g.id.equals(id))).watchSingleOrNull();

  Future<Goal?> getGoal(String id) =>
      (select(goals)..where((g) => g.id.equals(id))).getSingleOrNull();

  Stream<List<GoalMetric>> watchGoalMetrics(String goalId) {
    return (select(goalMetrics)
          ..where((m) => m.goalId.equals(goalId))
          ..orderBy([(m) => OrderingTerm(expression: m.name)]))
        .watch();
  }

  /// Historique des valeurs : conservé intégralement (D07 §12.5).
  Stream<List<GoalProgressEntry>> watchGoalProgress(String goalId) {
    return (select(goalProgressEntries)
          ..where((e) => e.goalId.equals(goalId))
          ..orderBy([
            (e) => OrderingTerm(
                expression: e.recordedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<void> saveGoal(Goal g, {bool existed = false}) async {
    await into(goals).insert(g, mode: InsertMode.insertOrReplace);
    logOp('Goal', g.id, existed ? 'UPDATE' : 'CREATE',
        {'title': g.title, 'status': g.status});
  }

  Future<void> setGoalStatus(String id, String status) async {
    await (update(goals)..where((g) => g.id.equals(id))).write(
        GoalsCompanion(
            status: Value(status), updatedAt: Value(DateTime.now())));
    logOp('Goal', id, 'UPDATE', {'status': status});
  }

  Future<void> updateGoalHeader(String id, String title, String? description,
      {String? targetDate}) async {
    await (update(goals)..where((g) => g.id.equals(id))).write(GoalsCompanion(
        title: Value(title),
        description: Value(description),
        targetDate: Value(targetDate),
        updatedAt: Value(DateTime.now())));
    logOp('Goal', id, 'UPDATE', {'title': title});
  }

  Future<void> addGoalMetric(GoalMetric m) async {
    await into(goalMetrics).insert(m);
    logOp('GoalMetric', m.id, 'CREATE',
        {'name': m.name, 'goalId': m.goalId});
  }

  Future<void> deleteGoalMetric(String id) async {
    await (delete(goalProgressEntries)
          ..where((e) => e.metricId.equals(id)))
        .go();
    await (delete(goalMetrics)..where((m) => m.id.equals(id))).go();
    logOp('GoalMetric', id, 'DELETE', {});
  }

  /// Enregistre une progression : nouvelle entrée d'historique + valeur
  /// courante de l'indicateur (mises à jour manuelles — D07 §12.1-6).
  Future<void> recordProgress(GoalMetric m, double value, String? note) async {
    final now = DateTime.now();
    final e = GoalProgressEntry(
      id: 'gpe_${now.microsecondsSinceEpoch}',
      goalId: m.goalId,
      metricId: m.id,
      value: value,
      note: note,
      recordedAt: now,
    );
    await into(goalProgressEntries).insert(e);
    await (update(goalMetrics)..where((x) => x.id.equals(m.id)))
        .write(GoalMetricsCompanion(currentValue: Value(value)));
    logOp('GoalProgressEntry', e.id, 'CREATE',
        {'metricId': m.id, 'value': value});
    logOp('GoalMetric', m.id, 'UPDATE', {'currentValue': value});
  }

  Future<void> deleteGoal(String id) async {
    final g = await getGoal(id);
    await (delete(goalProgressEntries)..where((e) => e.goalId.equals(id)))
        .go();
    await (delete(goalMetrics)..where((m) => m.goalId.equals(id))).go();
    await ensureGoalProjectLinks(this);
    await customUpdate('DELETE FROM goal_project_links WHERE goal_id = ?',
        variables: [Variable<String>(id)], updates: {projects});
    await (delete(goals)..where((x) => x.id.equals(id))).go();
    logOp('Goal', id, 'DELETE', {'title': g?.title ?? ''});
  }

  // —— Liens objectif ↔ projet (table auxiliaire, D07 §12.7) ——

  Stream<List<GoalProjectLink>> watchGoalProjectLinks(String goalId) {
    return customSelect(
      'SELECT id, goal_id, project_id FROM goal_project_links WHERE goal_id = ?',
      variables: [Variable<String>(goalId)],
      readsFrom: {projects}, // ré-émis après chaque écriture via `updates`
    ).watch().map((rows) => [
          for (final r in rows)
            GoalProjectLink(
                id: r.read<String>('id'),
                goalId: r.read<String>('goal_id'),
                projectId: r.read<String>('project_id')),
        ]);
  }

  Future<void> linkGoalToProject(String goalId, String projectId) async {
    await ensureGoalProjectLinks(this);
    final id = 'gpl_${goalId}_$projectId';
    await customInsert(
        'INSERT OR REPLACE INTO goal_project_links (id, goal_id, project_id) '
        'VALUES (?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(goalId),
          Variable<String>(projectId),
        ],
        updates: {projects});
    logOp('GoalProjectLink', id, 'CREATE',
        {'goalId': goalId, 'projectId': projectId});
  }

  Future<void> unlinkGoalFromProject(String linkId) async {
    await ensureGoalProjectLinks(this);
    await customUpdate('DELETE FROM goal_project_links WHERE id = ?',
        variables: [Variable<String>(linkId)], updates: {projects});
    logOp('GoalProjectLink', linkId, 'DELETE', {});
  }
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final projectsProvider = StreamProvider.family<List<Project>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchProjects(spaceId));

final projectProvider = StreamProvider.family<Project?, String>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.projects)..where((p) => p.id.equals(id)))
      .watchSingleOrNull();
});

final projectStagesProvider = StreamProvider.family<List<ProjectStage>, String>(
    (ref, projectId) => ref.watch(dbProvider).watchStages(projectId));

final projectMilestonesProvider =
    StreamProvider.family<List<ProjectMilestone>, String>(
        (ref, projectId) => ref.watch(dbProvider).watchMilestones(projectId));

final projectMembersProvider = StreamProvider.family<List<ProjectMember>,
        String>((ref, projectId) => ref.watch(dbProvider).watchProjectMembers(projectId));

final projectTasksProvider = StreamProvider.family<List<LinkedTask>, String>(
    (ref, projectId) => ref.watch(dbProvider).watchProjectTasks(projectId));

final goalsProvider = StreamProvider.family<List<Goal>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchGoals(spaceId));

final goalProvider = StreamProvider.family<Goal?, String>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.goals)..where((g) => g.id.equals(id)))
      .watchSingleOrNull();
});

final goalMetricsProvider = StreamProvider.family<List<GoalMetric>, String>(
    (ref, goalId) => ref.watch(dbProvider).watchGoalMetrics(goalId));

final goalProgressProvider =
    StreamProvider.family<List<GoalProgressEntry>, String>(
        (ref, goalId) => ref.watch(dbProvider).watchGoalProgress(goalId));

final goalProjectLinksProvider =
    StreamProvider.family<List<GoalProjectLink>, String>((ref, goalId) async* {
  final db = ref.watch(dbProvider);
  await ensureGoalProjectLinks(db);
  yield* db.watchGoalProjectLinks(goalId);
});

// ═══════════════════════════ ÉCRAN : LISTE DES PROJETS ═══════════════════════════

/// Projets de l'espace actif — progression, statuts, archivage distinct (D07).
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  void _newProject(BuildContext context, String spaceId) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewProjectSheet(spaceId: spaceId),
    ).then((created) {
      if (created == true && context.mounted) {
        lhToast(context, 'Projet créé');
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final projectsAsync = ref.watch(projectsProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Projets'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newProject(context, spaceId),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau projet'),
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (projects) => projects.isEmpty
            ? EmptyState(
                icon: Icons.rocket_launch_outlined,
                message: 'Aucun projet',
                hint:
                    'Un projet est un travail organisé pour atteindre un résultat.',
                action: FilledButton.tonal(
                  onPressed: () => _newProject(context, spaceId),
                  child: const Text('Nouveau projet'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 96),
                children: [
                  // Section Objectifs (module voisin, même dossier D07).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(LHSpacing.screen,
                        LHSpacing.sm, LHSpacing.screen, LHSpacing.xs),
                    child: LHCard(
                      accent: LHColors.emeraudeClair,
                      onTap: () => context.push('/goals'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: LHSpacing.md, vertical: LHSpacing.sm + 2),
                      child: Row(children: [
                        const Icon(Icons.flag_outlined,
                            color: LHColors.emeraudeClair),
                        const SizedBox(width: LHSpacing.md),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Objectifs',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                Text(
                                  'Résultats visés, indicateurs et progression',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                ),
                              ]),
                        ),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
                  for (final p in projects)
                    _ProjectTile(project: p),
                ],
              ),
      ),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(projectTasksProvider(project.id)).valueOrNull ?? [];
    final auto = autoProjectProgress(tasks);
    final progress =
        project.manualProgress != null ? project.manualProgress! / 100 : auto;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.screen, vertical: 5),
      child: LHCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProjectDetailScreen(id: project.id),
        )),
        child: Row(children: [
          ProgressRing(
            progress: progress,
            size: 46,
            stroke: 4,
            child: Text(
              '${(progress * 100).round()}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusChip(
                      label: projectStatusLabel(project.status),
                      color: projectStatusColor(project.status),
                      small: true,
                    ),
                  ]),
                  if (project.description != null &&
                      project.description!.isNotEmpty)
                    Text(
                      project.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 3, children: [
                    if (project.startDate != null)
                      _metaBadge(
                          Icons.play_arrow_outlined,
                          fmt.humanDate(fmt.parseKey(project.startDate!)),
                          theme),
                    if (project.targetDate != null)
                      _metaBadge(
                          Icons.flag_outlined,
                          fmt.humanDate(fmt.parseKey(project.targetDate!)),
                          theme),
                    _metaBadge(
                        Icons.link,
                        '${tasks.length} tâche${tasks.length > 1 ? 's' : ''} liée${tasks.length > 1 ? 's' : ''}',
                        theme),
                  ]),
                ]),
          ),
          // Archivage distinct du statut (D07 §12.3).
          PopupMenuButton<String>(
            tooltip: 'Options du projet',
            onSelected: (v) async {
              if (v == 'archive') {
                await ref
                    .read(dbProvider)
                    .archiveProject(project.id, true);
                if (context.mounted) {
                  lhToast(context, 'Projet archivé (distinct du statut)');
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'archive', child: Text('Archiver')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _metaBadge(IconData icon, String label, ThemeData theme) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon,
          size: 13, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(label,
          style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// Feuille de création de projet : nom, description, statut, dates.
class _NewProjectSheet extends ConsumerStatefulWidget {
  const _NewProjectSheet({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends ConsumerState<_NewProjectSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _status = 'PLANNED';
  String? _startDate;
  String? _targetDate;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = fmt.parseKey(
        (isStart ? _startDate : _targetDate) ?? fmt.dateKey(fmt.today()));
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
          _targetDate = fmt.dateKey(picked);
        }
      });
    }
  }

  Future<void> _save() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final p = Project(
      id: 'project_${now.microsecondsSinceEpoch}',
      spaceId: widget.spaceId,
      name: _name.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      status: _status,
      startDate: _startDate,
      targetDate: _targetDate,
      manualProgress: null,
      archivedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveProject(p);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _name.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(LHSpacing.screen, 0,
            LHSpacing.screen, LHSpacing.lg),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Nouveau projet',
                    style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Nom du projet',
                    hintText: 'Ex. Refonte du site vitrine'),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description (optionnel)'),
              ),
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Statut',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in projectStatuses)
                      ChoiceChip(
                        label: Text(projectStatusLabel(s)),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: LHSpacing.md),
              Row(children: [
                Expanded(
                  child: LabeledField(
                    label: 'Début (optionnel)',
                    child: _dateTile(
                        _startDate != null
                            ? fmt.humanDate(fmt.parseKey(_startDate!))
                            : 'Non définie',
                        _startDate != null, () => _pickDate(true)),
                  ),
                ),
                const SizedBox(width: LHSpacing.md),
                Expanded(
                  child: LabeledField(
                    label: 'Objectif (optionnel)',
                    child: _dateTile(
                        _targetDate != null
                            ? fmt.humanDate(fmt.parseKey(_targetDate!))
                            : 'Non définie',
                        _targetDate != null, () => _pickDate(false)),
                  ),
                ),
              ]),
              const SizedBox(height: LHSpacing.lg),
              FilledButton.icon(
                onPressed: canSave ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('Créer le projet'),
              ),
            ]),
      ),
    );
  }

  Widget _dateTile(String label, bool defined, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LHRadius.md),
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(
          label,
          style: TextStyle(color: defined ? null : theme.hintColor),
        ),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : DÉTAIL PROJET (D07 §12.1) ═══════════════════════════

/// Détail d'un projet : en-tête éditable, progression (calculée ou ajustée),
/// étapes, jalons, membres, tâches liées (D07 §12.1).
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  final _stageCtrl = TextEditingController();
  final _milestoneCtrl = TextEditingController();
  String? _milestoneDate;

  @override
  void dispose() {
    _stageCtrl.dispose();
    _milestoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMilestoneDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _milestoneDate != null
          ? fmt.parseKey(_milestoneDate!)
          : fmt.today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _milestoneDate = fmt.dateKey(picked));
  }

  Future<void> _editDescription(Project p) async {
    final ctrl = TextEditingController(text: p.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Description du projet'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'Contexte, résultat attendu…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    await ref
        .read(dbProvider)
        .updateProjectDescription(p.id, text.isEmpty ? null : text);
  }

  Future<void> _adjustProgress(Project p, double auto) async {
    final initial = (p.manualProgress ?? (auto * 100)).round();
    final ctrl = TextEditingController(text: initial.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajuster la progression'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Pourcentage (0 à 100)'),
            ),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'L\'ajustement est journalisé ; le calcul automatique reste disponible.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    final value = int.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok != true || value == null) return;
    final clamped = value.clamp(0, 100);
    await ref.read(dbProvider).setManualProgress(p.id, clamped);
    if (mounted) lhToast(context, 'Progression ajustée à $clamped %');
  }

  Future<void> _addMember() async {
    final nameCtrl = TextEditingController();
    var role = 'CONTRIBUTOR';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ajouter un membre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Nom du membre'),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Rôle',
                child: LhSegmented<String>(
                  value: role,
                  items: const {
                    'LEAD': 'Responsable',
                    'CONTRIBUTOR': 'Contributeur',
                  },
                  onChanged: (v) => setD(() => role = v),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: nameCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    await ref.read(dbProvider).addMember(widget.id, name, role);
  }

  Future<void> _linkTask() async {
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final all = await (db.select(db.tasks)
          ..where((t) => t.spaceId.equals(spaceId) & t.archivedAt.isNull()))
        .get();
    final linkedIds = (ref.read(projectTasksProvider(widget.id)).valueOrNull ??
            const <LinkedTask>[])
        .map((l) => l.task.id)
        .toSet();
    final candidates = all.where((t) => !linkedIds.contains(t.id)).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: candidates.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Aucune autre tâche disponible dans cet espace.'),
                  ),
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(LHSpacing.screen, 0,
                        LHSpacing.screen, LHSpacing.xs),
                    child: Text('Lier une tâche',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  for (final t in candidates)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        t.status == 'DONE'
                            ? Icons.check_circle
                            : Icons.task_alt_outlined,
                        size: 20,
                        color: _taskStatusColor(t.status),
                      ),
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: t.dueDate != null
                          ? Text(
                              fmt.humanDate(fmt.parseKey(t.dueDate!)),
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      trailing: StatusChip(
                        label: _taskStatusLabel(t.status),
                        color: _taskStatusColor(t.status),
                        small: true,
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await db.linkTask(widget.id, t.id);
                      },
                    ),
                ],
        ),
      ),
    );
  }

  Future<void> _archive(Project p) async {
    await ref.read(dbProvider).archiveProject(p.id, true);
    if (mounted) lhToast(context, 'Projet archivé (distinct du statut)');
  }

  Future<void> _delete(Project p) async {
    final ok = await lhConfirm(
      context,
      title: 'Supprimer le projet ?',
      message:
          '« ${p.name} », ses étapes, jalons, membres et liens de tâches seront supprimés. La suppression est journalisée pour la synchronisation.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(dbProvider).deleteProject(p.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final project = ref.watch(projectProvider(widget.id)).valueOrNull;

    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Projet')),
        body: const EmptyState(
            icon: Icons.rocket_launch_outlined,
            message: 'Projet introuvable',
            hint: 'Il a peut-être été supprimé.'),
      );
    }

    final stages =
        ref.watch(projectStagesProvider(widget.id)).valueOrNull ?? [];
    final milestones =
        ref.watch(projectMilestonesProvider(widget.id)).valueOrNull ?? [];
    final members =
        ref.watch(projectMembersProvider(widget.id)).valueOrNull ?? [];
    final linkedTasks =
        ref.watch(projectTasksProvider(widget.id)).valueOrNull ?? [];

    final auto = autoProjectProgress(linkedTasks);
    final progress =
        project.manualProgress != null ? project.manualProgress! / 100 : auto;
    final doneCount = linkedTasks
        .where((l) => l.task.status == 'DONE')
        .length;
    final totalCount =
        linkedTasks.where((l) => l.task.status != 'CANCELLED').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (v) {
              switch (v) {
                case 'archive':
                  _archive(project);
                  break;
                case 'delete':
                  _delete(project);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'archive', child: Text('Archiver')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, 96),
        children: [
          // —— En-tête : nom, statut, dates, description éditable ——
          LHCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        project.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFamily: LHFonts.titres),
                      ),
                    ),
                  ]),
                  const SizedBox(height: LHSpacing.sm),
                  // Statut (changeable).
                  PopupMenuButton<String>(
                    tooltip: 'Changer le statut',
                    onSelected: (s) => db.setProjectStatus(project.id, s),
                    itemBuilder: (_) => [
                      for (final s in projectStatuses)
                        PopupMenuItem(
                          value: s,
                          child: Row(children: [
                            Icon(Icons.circle,
                                size: 10, color: projectStatusColor(s)),
                            const SizedBox(width: LHSpacing.sm),
                            Text(projectStatusLabel(s)),
                          ]),
                        ),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(
                          label: projectStatusLabel(project.status),
                          color: projectStatusColor(project.status),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: LHSpacing.sm),
                  Wrap(spacing: 6, runSpacing: 3, children: [
                    if (project.startDate != null)
                      _metaBadge(
                          Icons.play_arrow_outlined,
                          'Début ${fmt.humanDate(fmt.parseKey(project.startDate!))}',
                          theme),
                    if (project.targetDate != null)
                      _metaBadge(
                          Icons.flag_outlined,
                          'Objectif ${fmt.humanDate(fmt.parseKey(project.targetDate!))}',
                          theme),
                    if (project.archivedAt != null)
                      _metaBadge(Icons.archive_outlined, 'Archivé', theme),
                  ]),
                  const SizedBox(height: LHSpacing.md),
                  InkWell(
                    onTap: () => _editDescription(project),
                    borderRadius: BorderRadius.circular(LHRadius.sm),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: LHSpacing.sm),
                          Expanded(
                            child: Text(
                              project.description == null ||
                                      project.description!.isEmpty
                                  ? 'Ajouter une description…'
                                  : project.description!,
                              style: project.description == null ||
                                      project.description!.isEmpty
                                  ? theme.textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.hintColor)
                                  : theme.textTheme.bodyMedium,
                            ),
                          ),
                          Icon(Icons.edit_outlined,
                              size: 14, color: theme.hintColor),
                        ]),
                  ),
                ]),
          ),

          // —— Progression : calculée depuis les tâches, ajustement manuel
          //    traçable (D07 §12.1-2) ——
          SectionHeader('Progression',
              overline:
                  project.manualProgress != null ? 'Ajustée manuellement' : null),
          LHCard(
            child: Column(children: [
              Row(children: [
                ProgressRing(
                  progress: progress,
                  size: 64,
                  stroke: 6,
                  child: Text(
                    '${(progress * 100).round()} %',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: LHSpacing.lg),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.manualProgress != null
                              ? 'Valeur ajustée manuellement'
                              : 'Calculée depuis les tâches liées',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                            '$doneCount / $totalCount tâche${totalCount > 1 ? 's' : ''} terminée${doneCount > 1 ? 's' : ''}',
                            style: theme.textTheme.bodySmall),
                        if (project.manualProgress != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: LHColors.or.withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(LHRadius.full),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune,
                                      size: 12, color: LHColors.orDeep),
                                  const SizedBox(width: 4),
                                  Text('Ajustée manuellement',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: LHColors.orDeep,
                                              fontWeight: FontWeight.w700)),
                                ]),
                          ),
                        ],
                      ]),
                ),
              ]),
              const SizedBox(height: LHSpacing.md),
              if (project.manualProgress != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await db.setManualProgress(project.id, null);
                      if (context.mounted) {
                        lhToast(context,
                            'Retour au calcul automatique depuis les tâches');
                      }
                    },
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Revenir au calcul automatique'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _adjustProgress(project, auto),
                    icon: const Icon(Icons.tune),
                    label: const Text('Ajuster manuellement'),
                  ),
                ),
            ]),
          ),

          // —— Étapes : checklist cursive (distincte des jalons) ——
          SectionHeader('Étapes',
              overline: '${stages.where((s) => s.status == 'DONE').length}/${stages.length}'),
          if (stages.isEmpty)
            const Text('Aucune étape pour l\'instant.',
                style: TextStyle(fontSize: 13))
          else
            LHCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: LHSpacing.md, vertical: LHSpacing.sm),
              child: Column(
                  children: [
                    for (final (i, s) in stages.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      Row(children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => db.cycleStage(s),
                          child: Tooltip(
                            message: 'Changer le statut',
                            child: Icon(
                              switch (s.status) {
                                'TODO' => Icons.radio_button_unchecked,
                                'IN_PROGRESS' => Icons.timelapse,
                                _ => Icons.check_circle,
                              },
                              size: 22,
                              color: stageStatusColor(s.status),
                            ),
                          ),
                        ),
                        const SizedBox(width: LHSpacing.md),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                Text(
                                  stageStatusLabel(s.status),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: stageStatusColor(s.status)),
                                ),
                              ]),
                        ),
                        IconButton(
                          tooltip: 'Supprimer l\'étape',
                          iconSize: 18,
                          icon: const Icon(Icons.close),
                          onPressed: () => db.deleteStage(s.id),
                        ),
                      ]),
                    ],
                  ]),
            ),
          const SizedBox(height: LHSpacing.sm),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _stageCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Nouvelle étape…', isDense: true),
                onSubmitted: (v) => _addStage(),
              ),
            ),
            IconButton(
              tooltip: 'Ajouter l\'étape',
              icon: const Icon(Icons.add),
              onPressed: _addStage,
            ),
          ]),

          // —— Jalons : atteints ou en attente ——
          SectionHeader('Jalons',
              overline:
                  '${milestones.where((m) => m.status == 'REACHED').length}/${milestones.length}'),
          if (milestones.isEmpty)
            const Text('Aucun jalon pour l\'instant.',
                style: TextStyle(fontSize: 13))
          else
            LHCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: LHSpacing.md, vertical: LHSpacing.sm),
              child: Column(children: [
                for (final (i, m) in milestones.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => db.toggleMilestone(m),
                    borderRadius: BorderRadius.circular(LHRadius.sm),
                    child: Row(children: [
                      Icon(
                        m.status == 'REACHED'
                            ? Icons.flag
                            : Icons.flag_outlined,
                        size: 20,
                        color: m.status == 'REACHED'
                            ? LHColors.emeraudeClair
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: LHSpacing.md),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      decoration: m.status == 'REACHED'
                                          ? TextDecoration.lineThrough
                                          : null)),
                              if (m.dueDate != null)
                                Text(
                                  m.status == 'REACHED'
                                      ? 'Atteint · ${fmt.humanDate(fmt.parseKey(m.dueDate!))}'
                                      : 'Prévu le ${fmt.humanDate(fmt.parseKey(m.dueDate!))}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                            ]),
                      ),
                      IconButton(
                        tooltip: 'Supprimer le jalon',
                        iconSize: 18,
                        icon: const Icon(Icons.close),
                        onPressed: () => db.deleteMilestone(m.id),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: LHSpacing.sm),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _milestoneCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Nouveau jalon…', isDense: true),
                onSubmitted: (v) => _addMilestone(),
              ),
            ),
            IconButton(
              tooltip: _milestoneDate != null
                  ? fmt.humanDate(fmt.parseKey(_milestoneDate!))
                  : 'Choisir une date',
              icon: Icon(
                Icons.event_outlined,
                color: _milestoneDate != null ? LHColors.or : null,
              ),
              onPressed: _pickMilestoneDate,
            ),
            IconButton(
              tooltip: 'Ajouter le jalon',
              icon: const Icon(Icons.add),
              onPressed: _addMilestone,
            ),
          ]),

          // —— Membres : responsables & contributeurs (D07 §12.1-4) ——
          SectionHeader('Membres'),
          LHCard(
            padding: const EdgeInsets.symmetric(
                horizontal: LHSpacing.md, vertical: LHSpacing.sm + 2),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (members.isEmpty)
                    Text('Aucun membre pour l\'instant.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: LHSpacing.sm,
                      runSpacing: LHSpacing.sm,
                      children: [
                        for (final m in members)
                          InputChip(
                            avatar: InitialsAvatar(
                              name: m.name,
                              size: 24,
                              color: m.role == 'LEAD'
                                  ? LHColors.or
                                  : LHColors.info,
                            ),
                            label: Text(
                                '${m.name} · ${memberRoleLabel(m.role)}',
                                style: theme.textTheme.labelMedium),
                            onDeleted: () => db.removeMember(m.id),
                          ),
                      ],
                    ),
                  const SizedBox(height: LHSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _addMember,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Ajouter un membre'),
                  ),
                ]),
          ),

          // —— Tâches liées : gérées par le module Activités (D07 §12.6) ——
          SectionHeader('Tâches liées', overline: '${linkedTasks.length}'),
          if (linkedTasks.isEmpty)
            const Text(
                'Aucune tâche liée. Les tâches restent gérées dans le module Activités.',
                style: TextStyle(fontSize: 13))
          else
            LHCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: LHSpacing.md, vertical: LHSpacing.sm),
              child: Column(children: [
                for (final (i, l) in linkedTasks.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  Row(children: [
                    Icon(
                      l.task.status == 'DONE'
                          ? Icons.check_circle
                          : Icons.task_alt_outlined,
                      size: 20,
                      color: _taskStatusColor(l.task.status),
                    ),
                    const SizedBox(width: LHSpacing.md),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium),
                            Text(
                              _taskStatusLabel(l.task.status),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: _taskStatusColor(l.task.status)),
                            ),
                          ]),
                    ),
                    const SizedBox(width: LHSpacing.sm),
                    StatusChip(
                      label: _taskStatusLabel(l.task.status),
                      color: _taskStatusColor(l.task.status),
                      small: true,
                    ),
                    IconButton(
                      tooltip: 'Délier la tâche',
                      iconSize: 18,
                      icon: const Icon(Icons.link_off),
                      onPressed: () async {
                        await db.unlinkTask(l.linkId);
                        if (context.mounted) {
                          lhToast(context, 'Tâche déliée du projet');
                        }
                      },
                    ),
                  ]),
                ],
              ]),
            ),
          const SizedBox(height: LHSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _linkTask,
              icon: const Icon(Icons.add_link),
              label: const Text('Lier une tâche'),
            ),
          ),
        ],
      ),
    );
  }

  void _addStage() {
    final name = _stageCtrl.text.trim();
    if (name.isEmpty) return;
    _stageCtrl.clear();
    ref.read(dbProvider).addStage(widget.id, name);
  }

  void _addMilestone() {
    final name = _milestoneCtrl.text.trim();
    if (name.isEmpty) return;
    _milestoneCtrl.clear();
    final date = _milestoneDate;
    setState(() => _milestoneDate = null);
    ref.read(dbProvider).addMilestone(widget.id, name, date);
  }

  Widget _metaBadge(IconData icon, String label, ThemeData theme) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(label,
          style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

// ═══════════════════════════ ÉCRAN : LISTE DES OBJECTIFS ═══════════════════════════

/// Objectifs de l'espace actif — résultats visés et indicateurs (D07).
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  void _newGoal(BuildContext context, String spaceId) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewGoalSheet(spaceId: spaceId),
    ).then((created) {
      if (created == true && context.mounted) {
        lhToast(context, 'Objectif créé');
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final goalsAsync = ref.watch(goalsProvider(spaceId));

    return Scaffold(
      appBar: LhAppBar(title: 'Objectifs'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newGoal(context, spaceId),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel objectif'),
      ),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, message: 'Erreur : $e'),
        data: (goals) => goals.isEmpty
            ? EmptyState(
                icon: Icons.flag_outlined,
                message: 'Aucun objectif',
                hint:
                    'Un objectif décrit un résultat recherché ; un projet organise le travail pour l\'atteindre.',
                action: FilledButton.tonal(
                  onPressed: () => _newGoal(context, spaceId),
                  child: const Text('Nouvel objectif'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 96),
                itemCount: goals.length,
                itemBuilder: (context, i) =>
                    _GoalTile(goal: goals[i]),
              ),
      ),
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const _GoalTile({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final metrics =
        ref.watch(goalMetricsProvider(goal.id)).valueOrNull ?? [];
    final first = metrics.isEmpty ? null : metrics.first;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LHSpacing.screen, vertical: 5),
      child: LHCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => GoalDetailScreen(id: goal.id),
        )),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    goal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(
                  label: goalStatusLabel(goal.status),
                  color: goalStatusColor(goal.status),
                  small: true,
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: goalCategoryColor(goal.category)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(LHRadius.full),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(goalCategoryIcon(goal.category),
                        size: 13, color: goalCategoryColor(goal.category)),
                    const SizedBox(width: 4),
                    Text(
                      goalCategoryLabel(goal.category),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: goalCategoryColor(goal.category),
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                if (goal.targetDate != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event_outlined,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      fmt.humanDate(fmt.parseKey(goal.targetDate!)),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
              ]),
              if (first != null) ...[
                const SizedBox(height: LHSpacing.sm),
                Text(
                  '${first.name} — ${fmtMetricValue(first.currentValue)} / ${fmtMetricValue(first.targetValue)}${first.unit != null ? ' ${first.unit}' : ''}',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(LHRadius.full),
                  child: LinearProgressIndicator(
                    value: metricProgress(first),
                    minHeight: 6,
                    color: metricProgress(first) >= 1
                        ? LHColors.emeraudeClair
                        : null,
                  ),
                ),
              ],
            ]),
      ),
    );
  }
}

/// Feuille de création d'objectif : titre, description, catégorie, statut,
/// date cible, indicateur initial optionnel (D07 §12.5).
class _NewGoalSheet extends ConsumerStatefulWidget {
  const _NewGoalSheet({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends ConsumerState<_NewGoalSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _metricName = TextEditingController();
  final _metricUnit = TextEditingController();
  final _metricStart = TextEditingController();
  final _metricTarget = TextEditingController();

  String _category = 'PERSONAL';
  String _status = 'NOT_STARTED';
  String _direction = 'INCREASE';
  String? _targetDate;
  bool _withMetric = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _metricName.dispose();
    _metricUnit.dispose();
    _metricStart.dispose();
    _metricTarget.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _targetDate != null ? fmt.parseKey(_targetDate!) : fmt.today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _targetDate = fmt.dateKey(picked));
  }

  Future<void> _save() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final goalId = 'goal_${now.microsecondsSinceEpoch}';
    await db.saveGoal(Goal(
      id: goalId,
      spaceId: widget.spaceId,
      title: _title.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      status: _status,
      category: _category,
      targetDate: _targetDate,
      createdAt: now,
      updatedAt: now,
    ));
    if (_withMetric && _metricName.text.trim().isNotEmpty) {
      final start =
          double.tryParse(_metricStart.text.trim().replaceAll(',', '.')) ?? 0;
      final target =
          double.tryParse(_metricTarget.text.trim().replaceAll(',', '.')) ??
              100;
      await db.addGoalMetric(GoalMetric(
        id: 'gm_${now.microsecondsSinceEpoch}',
        goalId: goalId,
        name: _metricName.text.trim(),
        unit: _metricUnit.text.trim().isEmpty ? null : _metricUnit.text.trim(),
        startValue: start,
        targetValue: target,
        currentValue: start,
        direction: _direction,
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _title.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, 0, LHSpacing.screen, LHSpacing.lg),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Nouvel objectif',
                    style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Titre',
                    hintText: 'Ex. Courir 5 km sans pause'),
              ),
              const SizedBox(height: LHSpacing.md),
              TextField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description (optionnel)'),
              ),
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Catégorie',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in goalCategories)
                      ChoiceChip(
                        label: Text(goalCategoryLabel(c)),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Statut',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in goalStatuses)
                      ChoiceChip(
                        label: Text(goalStatusLabel(s)),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: LHSpacing.md),
              LabeledField(
                label: 'Date cible (optionnel)',
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(LHRadius.md),
                  child: InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(
                      _targetDate != null
                          ? fmt.humanDate(fmt.parseKey(_targetDate!))
                          : 'Non définie',
                      style: TextStyle(
                          color: _targetDate != null
                              ? null
                              : theme.hintColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: LHSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ajouter un indicateur'),
                subtitle: const Text(
                    'Mesure chiffrée suivie dans le temps (ex. km, FCFA, sessions).',
                    style: TextStyle(fontSize: 12)),
                value: _withMetric,
                onChanged: (v) => setState(() => _withMetric = v),
              ),
              if (_withMetric) ...[
                TextField(
                  controller: _metricName,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      const InputDecoration(labelText: 'Nom de l\'indicateur'),
                ),
                const SizedBox(height: LHSpacing.sm),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _metricUnit,
                      decoration: const InputDecoration(
                          labelText: 'Unité (optionnel)'),
                    ),
                  ),
                  const SizedBox(width: LHSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _metricStart,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Valeur de départ'),
                    ),
                  ),
                  const SizedBox(width: LHSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _metricTarget,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cible'),
                    ),
                  ),
                ]),
                const SizedBox(height: LHSpacing.sm),
                LabeledField(
                  label: 'Direction',
                  child: LhSegmented<String>(
                    value: _direction,
                    items: const {
                      'INCREASE': 'Augmenter',
                      'DECREASE': 'Diminuer',
                    },
                    onChanged: (v) => setState(() => _direction = v),
                  ),
                ),
              ],
              const SizedBox(height: LHSpacing.lg),
              FilledButton.icon(
                onPressed: canSave ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('Créer l\'objectif'),
              ),
            ]),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : DÉTAIL OBJECTIF (D07 §12.5) ═══════════════════════════

/// Détail d'un objectif : indicateurs multiples, historique des valeurs,
/// liens vers les projets (D07 §12.5).
class GoalDetailScreen extends ConsumerStatefulWidget {
  const GoalDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  Future<void> _editHeader(Goal g) async {
    final titleCtrl = TextEditingController(text: g.title);
    final descCtrl = TextEditingController(text: g.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier l\'objectif'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: LHSpacing.sm),
            TextField(
              controller: descCtrl,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Description (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final desc = descCtrl.text.trim();
    titleCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || title.isEmpty) return;
    await ref
        .read(dbProvider)
        .updateGoalHeader(g.id, title, desc.isEmpty ? null : desc,
            targetDate: g.targetDate);
  }

  Future<void> _recordProgress(GoalMetric m) async {
    final valueCtrl = TextEditingController(
        text: m.currentValue == m.currentValue.truncateToDouble()
            ? m.currentValue.truncate().toString()
            : m.currentValue.toStringAsFixed(1));
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Progression — ${m.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Nouvelle valeur${m.unit != null ? ' (${m.unit})' : ''}'),
            ),
            const SizedBox(height: LHSpacing.sm),
            TextField(
              controller: noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Note (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    final raw = valueCtrl.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    final note = noteCtrl.text.trim();
    valueCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true) return;
    if (value == null) {
      if (mounted) lhToast(context, 'Valeur invalide.');
      return;
    }
    await ref
        .read(dbProvider)
        .recordProgress(m, value, note.isEmpty ? null : note);
    if (mounted) lhToast(context, 'Progression enregistrée');
  }

  Future<void> _addMetric() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: '0');
    final targetCtrl = TextEditingController(text: '100');
    var direction = 'INCREASE';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ajouter un indicateur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Nom (ex. Distance)'),
                ),
                const SizedBox(height: LHSpacing.sm),
                TextField(
                  controller: unitCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Unité (optionnel)'),
                ),
                const SizedBox(height: LHSpacing.sm),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Départ'),
                    ),
                  ),
                  const SizedBox(width: LHSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: targetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Cible'),
                    ),
                  ),
                ]),
                const SizedBox(height: LHSpacing.md),
                LabeledField(
                  label: 'Direction',
                  child: LhSegmented<String>(
                    value: direction,
                    items: const {
                      'INCREASE': 'Augmenter',
                      'DECREASE': 'Diminuer',
                    },
                    onChanged: (v) => setD(() => direction = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: nameCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    final start =
        double.tryParse(startCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final target =
        double.tryParse(targetCtrl.text.trim().replaceAll(',', '.')) ?? 100;
    final unit = unitCtrl.text.trim();
    nameCtrl.dispose();
    unitCtrl.dispose();
    startCtrl.dispose();
    targetCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    await ref.read(dbProvider).addGoalMetric(GoalMetric(
          id: 'gm_${DateTime.now().microsecondsSinceEpoch}',
          goalId: widget.id,
          name: name,
          unit: unit.isEmpty ? null : unit,
          startValue: start,
          targetValue: target,
          currentValue: start,
          direction: direction,
        ));
  }

  Future<void> _linkProject(List<GoalProjectLink> links) async {
    final db = ref.read(dbProvider);
    final goal = await db.getGoal(widget.id);
    if (goal == null) return;
    final projects = await db.getProjects(goal.spaceId);
    final linkedIds = links.map((l) => l.projectId).toSet();
    final candidates = projects
        .where((p) => !linkedIds.contains(p.id) && p.archivedAt == null)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: candidates.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucun projet disponible à lier.'),
                  ),
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(LHSpacing.screen, 0,
                        LHSpacing.screen, LHSpacing.xs),
                    child: Text('Lier un projet',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  for (final p in candidates)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.rocket_launch_outlined,
                          size: 20),
                      title: Text(p.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(projectStatusLabel(p.status),
                          style: const TextStyle(fontSize: 12)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await db.linkGoalToProject(widget.id, p.id);
                      },
                    ),
                ],
        ),
      ),
    );
  }

  Future<void> _delete(Goal g) async {
    final ok = await lhConfirm(
      context,
      title: 'Supprimer l\'objectif ?',
      message:
          '« ${g.title} », ses indicateurs et son historique de progression seront supprimés. La suppression est journalisée pour la synchronisation.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(dbProvider).deleteGoal(g.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(dbProvider);
    final goal = ref.watch(goalProvider(widget.id)).valueOrNull;

    if (goal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Objectif')),
        body: const EmptyState(
            icon: Icons.flag_outlined,
            message: 'Objectif introuvable',
            hint: 'Il a peut-être été supprimé.'),
      );
    }

    final metrics =
        ref.watch(goalMetricsProvider(widget.id)).valueOrNull ?? [];
    final entries =
        ref.watch(goalProgressProvider(widget.id)).valueOrNull ?? [];
    final links =
        ref.watch(goalProjectLinksProvider(widget.id)).valueOrNull ?? [];
    final projects =
        ref.watch(projectsProvider(goal.spaceId)).valueOrNull ?? [];

    String? projectName(String id) =>
        projects.where((p) => p.id == id).firstOrNull?.name;
    GoalMetric? metricOf(String? id) =>
        id == null ? null : metrics.where((m) => m.id == id).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (v) {
              if (v == 'delete') _delete(goal);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, 96),
        children: [
          // —— En-tête : titre, statut, catégorie, date cible, description ——
          LHCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        goal.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFamily: LHFonts.titres),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editHeader(goal),
                    ),
                  ]),
                  const SizedBox(height: LHSpacing.sm),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    // Statut (changeable).
                    PopupMenuButton<String>(
                      tooltip: 'Changer le statut',
                      onSelected: (s) => db.setGoalStatus(goal.id, s),
                      itemBuilder: (_) => [
                        for (final s in goalStatuses)
                          PopupMenuItem(
                            value: s,
                            child: Row(children: [
                              Icon(Icons.circle,
                                  size: 10, color: goalStatusColor(s)),
                              const SizedBox(width: LHSpacing.sm),
                              Text(goalStatusLabel(s)),
                            ]),
                          ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(
                            label: goalStatusLabel(goal.status),
                            color: goalStatusColor(goal.status),
                          ),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: goalCategoryColor(goal.category)
                            .withValues(alpha: 0.14),
                        border: Border.all(
                            color: goalCategoryColor(goal.category)
                                .withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(LHRadius.full),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(goalCategoryIcon(goal.category),
                                size: 13,
                                color: goalCategoryColor(goal.category)),
                            const SizedBox(width: 5),
                            Text(
                              goalCategoryLabel(goal.category),
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: goalCategoryColor(goal.category),
                                  fontWeight: FontWeight.w600),
                            ),
                          ]),
                    ),
                    if (goal.targetDate != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.event_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Cible : ${fmt.humanDate(fmt.parseKey(goal.targetDate!))}',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ]),
                  ]),
                  if (goal.description != null &&
                      goal.description!.isNotEmpty) ...[
                    const SizedBox(height: LHSpacing.md),
                    Text(goal.description!,
                        style: theme.textTheme.bodyMedium),
                  ],
                ]),
          ),

          // —— Indicateurs : plusieurs par objectif (D07 §12.1-3) ——
          SectionHeader('Indicateurs',
              action: TextButton.icon(
                onPressed: _addMetric,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              )),
          if (metrics.isEmpty)
            const Text(
                'Aucun indicateur. Ajoutez une mesure chiffrée pour suivre la progression.',
                style: TextStyle(fontSize: 13))
          else
            for (final m in metrics) _MetricCard(metric: m, onRecord: () => _recordProgress(m), onDelete: () async {
              final ok = await lhConfirm(
                context,
                title: 'Supprimer l\'indicateur ?',
                message:
                    '« ${m.name} » et son historique de progression seront supprimés.',
                confirmLabel: 'Supprimer',
                destructive: true,
              );
              if (ok) await db.deleteGoalMetric(m.id);
            }),

          // —— Historique des valeurs (conservé intégralement — D07 §12.5) ——
          SectionHeader('Historique', overline: '${entries.length} entrée${entries.length > 1 ? 's' : ''}'),
          if (entries.isEmpty)
            const Text('Aucune progression enregistrée pour l\'instant.',
                style: TextStyle(fontSize: 13))
          else
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.only(left: LHSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        width: 2,
                        color: theme.colorScheme.outline
                            .withValues(alpha: 0.5))),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: LHSpacing.sm),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Icon(Icons.circle,
                                    size: 10, color: LHColors.or),
                              ),
                              const SizedBox(width: LHSpacing.sm),
                              Expanded(
                                child: Builder(builder: (context) {
                                  final m = metricOf(e.metricId);
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${fmtMetricValue(e.value)}'
                                          '${m?.unit != null ? ' ${m!.unit}' : ''}',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.w700),
                                        ),
                                        if (m != null)
                                          Text(
                                            m.name,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        if (e.note != null &&
                                            e.note!.isNotEmpty)
                                          Text(e.note!,
                                              style:
                                                  theme.textTheme.bodySmall),
                                        Text(
                                          '${fmt.formatLong(e.recordedAt)} · ${fmt.formatTime(e.recordedAt)}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                        ),
                                      ]);
                                }),
                              ),
                            ]),
                      ),
                  ]),
            ),

          // —— Projets liés : le travail organisé qui sert l'objectif ——
          SectionHeader('Projets liés'),
          if (links.isEmpty)
            const Text('Aucun projet lié à cet objectif.',
                style: TextStyle(fontSize: 13))
          else
            Wrap(
              spacing: LHSpacing.sm,
              runSpacing: LHSpacing.sm,
              children: [
                for (final l in links)
                  InputChip(
                    avatar: const Icon(Icons.rocket_launch_outlined,
                        size: 16),
                    label: Text(projectName(l.projectId) ?? 'Projet supprimé',
                        style: theme.textTheme.labelMedium),
                    onDeleted: () => db.unlinkGoalFromProject(l.id),
                  ),
              ],
            ),
          const SizedBox(height: LHSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _linkProject(links),
              icon: const Icon(Icons.add_link),
              label: const Text('Lier un projet'),
            ),
          ),
        ],
      ),
    );
  }

}

/// Carte d'indicateur : valeur actuelle / cible, direction, progression
/// relative, saisie de progression (D07 §12.5).
class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.metric, required this.onRecord, required this.onDelete});

  final GoalMetric metric;
  final VoidCallback onRecord;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = metricProgress(metric);
    final done = progress >= 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: LHSpacing.sm),
      child: LHCard(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    metric.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  metric.direction == 'INCREASE'
                      ? Icons.trending_up
                      : Icons.trending_down,
                  size: 20,
                  color: done
                      ? LHColors.emeraudeClair
                      : theme.colorScheme.onSurfaceVariant,
                ),
                IconButton(
                  tooltip: 'Supprimer l\'indicateur',
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                  onPressed: onDelete,
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${fmtMetricValue(metric.currentValue)} / ${fmtMetricValue(metric.targetValue)}'
                '${metric.unit != null ? ' ${metric.unit}' : ''}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '${metric.direction == 'INCREASE' ? 'Augmenter' : 'Diminuer'} depuis ${fmtMetricValue(metric.startValue)}'
                '${metric.unit != null ? ' ${metric.unit}' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: LHSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(LHRadius.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: done ? LHColors.emeraudeClair : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                done ? 'Cible atteinte — 100 %' : '${(progress * 100).round()} %',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: LHSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Enregistrer une progression'),
                ),
              ),
            ]),
      ),
    );
  }
}
