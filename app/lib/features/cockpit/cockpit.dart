import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart' as dbm;
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;
import '../agenda/agenda.dart' as agenda;
import '../ai/briefing.dart';
import '../finance/finance.dart' as fin;
import '../tasks/tasks.dart' as tasks;

// ═══════════════════════════ CLASSEMENT HYBRIDE (D02 §7.1-2) ═══════════════════════════

/// Score hybride proposé (formule à arbitrer — CDC D02 §7.5) :
/// priorité manuelle pondérée + bonus d'échéance + bonus d'avancement.
/// La priorité manuelle n'est JAMAIS modifiée silencieusement.
int hybridScore(dbm.Task t, String todayKey, int windowDays) {
  final weight = switch (t.priority) {
    'URGENT' => 50,
    'HIGH' => 35,
    'NORMAL' => 20,
    _ => 10,
  };
  var score = weight;
  final due = t.dueDate;
  if (due != null) {
    final days = fmt.daysBetween(fmt.parseKey(todayKey), fmt.parseKey(due));
    if (days < 0) {
      score += 40 + (-days).clamp(0, 5) * 2; // en retard
    } else if (days == 0) {
      score += 30;
    } else if (days <= 2) {
      score += 18;
    } else if (days <= windowDays) {
      score += 8;
    }
  }
  if (t.status == 'IN_PROGRESS') score += 6;
  return score;
}

// ═══════════════════════════ ÉCRAN : COCKPIT ═══════════════════════════

/// Ouvre la feuille briefing sur demande d'une notification (le signal est
/// consommé immédiatement — une seule ouverture par tap).
void _openBriefingOnTap(BuildContext context, WidgetRef ref) {
  if (!ref.read(briefingOpenRequest)) return;
  ref.read(briefingOpenRequest.notifier).state = false;
  showBriefingSheet(context);
}

/// Cockpit personnel — agrégation sans duplication : les modules sources
/// restent les sources de vérité (CDC D02 §7.3).
class CockpitScreen extends ConsumerWidget {
  const CockpitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    if (spaceId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final prefs = ref.watch(cockpitPrefsProvider);
    final space = ref.watch(activeSpaceProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
    final firstName = (settings['ownerName'] ?? '').trim();

    // Tap sur une notification (push FCM ou locale) → ouverture automatique
    // de la feuille briefing (D17.6) — le signal est posé par le service push.
    ref.listen<bool>(briefingOpenRequest, (prev, next) {
      if (next) _openBriefingOnTap(context, ref);
    });
    // Cas d'un démarrage depuis la notification (signal déjà posé avant le
    // premier build du cockpit).
    if (ref.read(briefingOpenRequest)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openBriefingOnTap(context, ref));
    }

    return Scaffold(
      appBar: LhAppBar(title: space?.name ?? 'LifeHelm'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _Greeting(firstName: firstName, spaceName: space?.name ?? ''),
          // Briefing quotidien HELM AI (Phase 3, D17.6) — invisible si
          // l'utilisateur ne l'a pas activé dans ses préférences IA.
          const BriefingCard(),
          // Sections ordonnées et filtrées selon les préférences (D02 §7.1-3).
          for (final key in prefs.sectionOrder)
            if (prefs.visibleSections.contains(key))
              switch (key) {
                'today' => _TodaySection(spaceId: spaceId),
                'actions' => const _QuickActions(),
                'priorities' => _PrioritiesSection(spaceId: spaceId),
                'agenda' => _AgendaSection(spaceId: spaceId),
                'finance' when prefs.showFinanceSummary =>
                  _FinanceSection(spaceId: spaceId),
                'goals' => _GoalsSection(spaceId: spaceId),
                'alerts' => const _AlertsSection(),
                _ => const SizedBox(),
              },
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.firstName, required this.spaceName});
  final String firstName;
  final String spaceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    // Salutation selon le moment de la journée (CDC §4.2) :
    // 5h-12h Bonjour · 12h-18h Bon après-midi · 18h-23h Bonsoir · 23h-5h Bonne nuit
    final salut = hour >= 5 && hour < 12
        ? 'Bonjour'
        : hour >= 12 && hour < 18
            ? 'Bon après-midi'
            : hour >= 18 && hour < 23
                ? 'Bonsoir'
                : 'Bonne nuit';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          firstName.isEmpty ? '$salut 👋' : '$salut, $firstName 👋',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          fmt.formatFull(fmt.today()),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

// ── Résumé du jour ──

class _TodaySection extends ConsumerWidget {
  const _TodaySection({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayKey = fmt.dateKey(fmt.today());
    final tasksList = ref.watch(tasks.tasksProvider(spaceId)).valueOrNull ?? [];
    final events = ref.watch(agenda.eventsProvider(spaceId)).valueOrNull ?? [];
    final exceptions =
        ref.watch(agenda.eventExceptionsProvider(spaceId)).valueOrNull ?? [];
    final rules = ref.watch(agenda.ruleMapProvider).valueOrNull ?? {};

    final dayTasks = tasksList.where((t) =>
        t.dueDate == todayKey &&
        t.status != 'DONE' &&
        t.status != 'CANCELLED' &&
        t.archivedAt == null);
    final doneToday = tasksList.where((t) =>
        t.completedAt != null && fmt.isSameDay(t.completedAt!, fmt.today()));
    final dayEvents = agenda
        .expandOccurrences(events, rules, exceptions, fmt.today(), fmt.today())
        .where((e) => e.event.status == 'SCHEDULED');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        Expanded(
          child: _stat(
            context,
            icon: Icons.checklist_rounded,
            color: LHColors.or,
            value: '${dayTasks.length}',
            label: dayTasks.isEmpty
                ? 'Aucune tâche due'
                : dayTasks.length == 1
                    ? 'tâche à traiter'
                    : 'tâches à traiter',
            onTap: () => context.push('/activities'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _stat(
            context,
            icon: Icons.event_rounded,
            color: LHColors.info,
            value: '${dayEvents.length}',
            label: dayEvents.isEmpty
                ? 'Aucun événement'
                : dayEvents.length == 1
                    ? 'événement'
                    : 'événements',
            onTap: () => context.push('/agenda'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _stat(
            context,
            icon: Icons.task_alt_rounded,
            color: LHColors.emeraudeClair,
            value: '${doneToday.length}',
            label: doneToday.isEmpty ? 'Rien de fini' : 'terminées',
            onTap: () => context.push('/activities'),
          ),
        ),
      ]),
    );
  }

  Widget _stat(BuildContext context,
      {required IconData icon,
      required Color color,
      required String value,
      required String label,
      VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LHRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(LHRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ── Actions rapides ──

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        _qa(context, Icons.add_task_rounded, 'Tâche', LHColors.or, () => context.push('/task/new')),
        _qa(context, Icons.north_east_rounded, 'Dépense', LHColors.erreur, () => context.push('/transaction/new?type=expense')),
        _qa(context, Icons.south_west_rounded, 'Revenu', LHColors.emeraudeClair, () => context.push('/transaction/new?type=income')),
        _qa(context, Icons.event_rounded, 'Événement', LHColors.info, () => context.push('/event/new')),
        _qa(context, Icons.edit_note_rounded, 'Note', LHColors.navy, () => context.push('/notes')),
      ]),
    );
  }

  Widget _qa(BuildContext context, IconData icon, String label, Color color,
      VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: theme.textTheme.labelSmall),
        ]),
      ),
    );
  }
}

// ── Priorités hybrides ──

class _PrioritiesSection extends ConsumerWidget {
  const _PrioritiesSection({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(cockpitPrefsProvider);
    final todayKey = fmt.dateKey(fmt.today());
    final all = ref.watch(tasks.tasksProvider(spaceId)).valueOrNull ?? [];
    final candidates = all
        .where((t) =>
            t.parentId == null &&
            t.archivedAt == null &&
            (t.status == 'TODO' || t.status == 'IN_PROGRESS' || t.status == 'WAITING'))
        .toList()
      ..sort((a, b) => hybridScore(b, todayKey, prefs.upcomingWindowDays)
          .compareTo(hybridScore(a, todayKey, prefs.upcomingWindowDays)));

    return Column(children: [
      SectionHeader('Priorités',
          overline: 'Classement hybride',
          action: TextButton(
              onPressed: () => context.push('/activities'),
              child: const Text('Tout voir'))),
      if (candidates.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LHCard(
            child: Row(children: [
              Icon(Icons.celebration_outlined, color: LHColors.emeraudeClair),
              SizedBox(width: 12),
              Expanded(child: Text('Rien d\'urgent — profitez de votre journée.')),
            ]),
          ),
        )
      else
        for (final t in candidates.take(5))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: LHCard(
              onTap: () => context.push('/task/${t.id}'),
              child: Row(children: [
                Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tasks.taskPriorityColor(t.priority),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Wrap(spacing: 6, runSpacing: 3, children: [
                          if (t.priority != 'NORMAL')
                            StatusChip(
                                label: tasks.taskPriorityLabel(t.priority),
                                color: tasks.taskPriorityColor(t.priority),
                                small: true),
                          if (t.dueDate != null)
                            StatusChip(
                                label: fmt.humanDate(fmt.parseKey(t.dueDate!)),
                                color: t.dueDate!.compareTo(todayKey) < 0
                                    ? LHColors.erreur
                                    : LHColors.neutre,
                                small: true),
                          if (t.status == 'IN_PROGRESS')
                            const StatusChip(
                                label: 'En cours',
                                color: LHColors.info,
                                small: true),
                        ]),
                      ]),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: LHColors.neutre, size: 20),
              ]),
            ),
          ),
    ]);
  }
}

// ── Agenda proche ──

class _AgendaSection extends ConsumerWidget {
  const _AgendaSection({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(cockpitPrefsProvider);
    final theme = Theme.of(context);
    final events = ref.watch(agenda.eventsProvider(spaceId)).valueOrNull ?? [];
    final exceptions =
        ref.watch(agenda.eventExceptionsProvider(spaceId)).valueOrNull ?? [];
    final rules = ref.watch(agenda.ruleMapProvider).valueOrNull ?? {};
    final to = fmt.addDays(fmt.today(), prefs.upcomingWindowDays);
    final entries = agenda
        .expandOccurrences(events, rules, exceptions, fmt.today(), to)
        .where((e) => e.event.status == 'SCHEDULED')
        .take(4);

    return Column(children: [
      SectionHeader('Agenda proche',
          overline: '${prefs.upcomingWindowDays} prochains jours',
          action: TextButton(
              onPressed: () => context.push('/agenda'),
              child: const Text('Agenda'))),
      if (entries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LHCard(
            child: Row(children: [
              Icon(Icons.event_available, color: LHColors.emeraudeClair),
              SizedBox(width: 12),
              Expanded(child: Text('Aucun événement à venir.')),
            ]),
          ),
        )
      else
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: LHCard(
              onTap: () => context.push('/event/${e.event.id}'),
              child: Row(children: [
                SizedBox(
                  width: 46,
                  child: Column(children: [
                    Text(fmt.weekdaysFr[e.date.weekday - 1],
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text('${e.date.day}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                        Text(
                          e.isAllDay
                              ? 'Journée entière${e.event.location != null ? ' · ${e.event.location}' : ''}'
                              : '${e.event.startTime ?? ''}${e.event.location != null ? ' · ${e.event.location}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ]),
                ),
              ]),
            ),
          ),
    ]);
  }
}

// ── Résumé financier ──

class _FinanceSection extends ConsumerWidget {
  const _FinanceSection({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balances =
        ref.watch(fin.balancesProvider(spaceId)).valueOrNull ?? [];
    final budgetStats =
        ref.watch(fin.budgetStatsProvider(spaceId)).valueOrNull ?? [];
    final dues = ref.watch(fin.duesProvider(spaceId)).valueOrNull ?? [];
    final todayKey = fmt.dateKey(fmt.today());

    var totalXof = 0;
    for (final b in balances) {
      totalXof += b.currency.code == 'XOF'
          ? b.current
          : b.current * (Currency.tauxVersXof[b.currency.code] ?? 1).round();
    }
    final alertBudgets = budgetStats.where((s) => s.ratio >= 0.8).length;
    final lateDues = dues.where((d) =>
        d.status == 'OPEN' && d.dueDate.compareTo(todayKey) < 0);

    return Column(children: [
      SectionHeader('Finances',
          overline: 'Vue consolidée',
          action: TextButton(
              onPressed: () => context.push('/finance'),
              child: const Text('Détails'))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: LHCard(
          onTap: () => context.push('/finance'),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.savings_outlined, color: LHColors.or, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('Patrimoine',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant))),
                  Text(
                    Money(totalXof, Currency.xof).format(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ]),
                if (alertBudgets > 0 || lateDues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (alertBudgets > 0)
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: LHColors.alerte),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '$alertBudgets budget${alertBudgets > 1 ? 's' : ''} au-delà du seuil d\'alerte',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: LHColors.alerte))),
                    ]),
                  for (final d in lateDues.take(2))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.event_busy,
                            size: 16, color: LHColors.erreur),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                '${d.label} — en retard (${Money(d.expectedAmount, Currency.byCode(d.currency)).format(withCode: false)})',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: LHColors.erreur))),
                      ]),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Budgets sous contrôle, aucune échéance en retard.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: LHColors.emeraudeClair)),
                  ),
              ]),
        ),
      ),
    ]);
  }
}

// ── Objectifs ──

class _GoalsSection extends ConsumerWidget {
  const _GoalsSection({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Les objectifs sont exposés par le module Projets (D07).
    final goals = ref.watch(goalsSummaryProvider(spaceId)).valueOrNull ?? [];

    return Column(children: [
      SectionHeader('Objectifs',
          overline: 'Cap sur l\'essentiel',
          action: TextButton(
              onPressed: () => context.push('/goals'),
              child: const Text('Tout voir'))),
      if (goals.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LHCard(
            child: Row(children: [
              Icon(Icons.flag_outlined, color: LHColors.neutre),
              SizedBox(width: 12),
              Expanded(
                  child:
                      Text('Définissez un objectif pour donner du cap à vos efforts.')),
            ]),
          ),
        )
      else
        for (final g in goals.take(3))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: LHCard(
              onTap: () => context.push('/goal/${g.id}'),
              child: Row(children: [
                ProgressRing(
                    progress: g.progress,
                    size: 42,
                    child: Text('${(g.progress * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        if (g.detail != null)
                          Text(g.detail!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
          ),
    ]);
  }
}

/// Résumé d'objectif calculé côté module D07 (source de vérité).
class GoalSummary {
  GoalSummary(this.id, this.title, this.progress, this.detail);
  final String id;
  final String title;
  final double progress;
  final String? detail;
}

final goalsSummaryProvider =
    StreamProvider.family<List<GoalSummary>, String>((ref, spaceId) {
  final db = ref.watch(dbProvider);
  return db.watchGoalsForCockpit(spaceId);
});

// ── Alertes ──

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final alerts = ref.watch(importantAlertsProvider(spaceId)).valueOrNull ?? [];

    return Column(children: [
      SectionHeader('Alertes',
          overline: 'Nécessite votre attention',
          action: TextButton(
              onPressed: () => context.push('/notifications'),
              child: const Text('Centre'))),
      if (alerts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LHCard(
            child: Row(children: [
              Icon(Icons.notifications_none, color: LHColors.neutre),
              SizedBox(width: 12),
              Expanded(child: Text('Aucune alerte importante.')),
            ]),
          ),
        )
      else
        for (final a in alerts.take(4))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: LHCard(
              onTap: () => context.push('/notifications'),
              accent: _priorityColor(a.priority),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: theme.textTheme.titleSmall),
                        Text(a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
          ),
    ]);
  }

  Color _priorityColor(String p) => switch (p) {
        'CRITICAL' => LHColors.notifCritique,
        'IMPORTANT' => LHColors.notifImportante,
        'INFO' => LHColors.notifInfo,
        _ => LHColors.notifNormale,
      };
}

/// Notifications importantes non lues (IMPORTANT et CRITICAL — D13).
final importantAlertsProvider =
    StreamProvider.family<List<dbm.Notification>, String>((ref, spaceId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.notifications)
        ..where((n) =>
            n.spaceId.equals(spaceId) &
            n.readAt.isNull() &
            n.archivedAt.isNull() &
            n.priority.isIn(['IMPORTANT', 'CRITICAL']))
        ..orderBy([
          (n) =>
              OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc)
        ]))
      .watch();
});

/// Requêtes du cockpit vers le module Objectifs (D07 — source de vérité).
extension CockpitGoalQueries on dbm.AppDatabase {
  Stream<List<GoalSummary>> watchGoalsForCockpit(String spaceId) {
    final q = (select(goals)
      ..where((g) =>
          g.spaceId.equals(spaceId) &
          g.status.isIn(['NOT_STARTED', 'ACTIVE'])));
    return q.watch().asyncMap((goalList) async {
      final result = <GoalSummary>[];
      for (final g in goalList) {
        final metrics = await (select(goalMetrics)
              ..where((m) => m.goalId.equals(g.id)))
            .get();
        double progress = 0;
        String? detail;
        if (metrics.isNotEmpty) {
          final m = metrics.first;
          final range = (m.targetValue - m.startValue).abs();
          progress = range == 0
              ? 0
              : ((m.currentValue - m.startValue) / range).clamp(0.0, 1.0);
          detail =
              '${_fmtNum(m.currentValue)} / ${_fmtNum(m.targetValue)}${m.unit != null ? ' ${m.unit}' : ''}';
        }
        result.add(GoalSummary(g.id, g.title, progress, detail));
      }
      return result;
    });
  }

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
