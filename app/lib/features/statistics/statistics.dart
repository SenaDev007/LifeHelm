import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/utils/money.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/common.dart';
import '../finance/finance.dart';
import '../projects/projects.dart'
    show autoProjectProgress, projectTasksProvider, projectsProvider;

// ═══════════════════════════ STATISTIQUES (module transversal) ═══════════════════════════

/// Statistiques complètes : recettes & dépenses, répartitions par catégorie
/// et sous-catégorie, budgets (prévu vs réalisé) et taux d'évolution des
/// projets. Graphiques peints à la main (charts.dart) — professionnels et
/// légers, sans dépendance externe.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final txs = ref.watch(transactionsProvider(spaceId)).valueOrNull ??
        const <FinancialTransaction>[];
    final categories =
        ref.watch(categoriesProvider(spaceId)).valueOrNull ?? [];
    final budgetStats =
        ref.watch(budgetStatsProvider(spaceId)).valueOrNull ?? [];

    // Fenêtre d'analyse : N derniers mois complets + mois en cours.
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - (_months - 1), 1);

    final inPeriod = txs.where((t) =>
        t.status == 'POSTED' &&
        (t.kind == 'INCOME' || t.kind == 'EXPENSE') &&
        !t.occurredAt.isBefore(from));

    // Résolution catégorie parente (une dépense compte dans sa famille).
    FinancialCategory? parentOf(FinancialTransaction t) {
      final cat = t.categoryId == null
          ? null
          : categories.where((c) => c.id == t.categoryId).firstOrNull;
      if (cat == null) return null;
      if (cat.parentId == null) return cat;
      return categories.where((c) => c.id == cat.parentId).firstOrNull ?? cat;
    }

    FinancialCategory? exactCategory(FinancialTransaction t) =>
        t.categoryId == null
            ? null
            : categories.where((c) => c.id == t.categoryId).firstOrNull;

    // ── Agrégats globaux ──
    var totalIncome = 0, totalExpense = 0;
    for (final t in inPeriod) {
      if (t.kind == 'INCOME') {
        totalIncome += t.amount;
      } else if (t.kind == 'EXPENSE') {
        totalExpense += t.amount;
      }
    }
    final net = totalIncome - totalExpense;
    final savingRate = totalIncome > 0 ? (net / totalIncome * 100) : 0.0;
    final avgExpense = totalExpense / _months;

    // ── Série mensuelle ──
    final points = <MonthlyPoint>[];
    for (var i = 0; i < _months; i++) {
      final m = DateTime(from.year, from.month + i, 1);
      final next = DateTime(from.year, from.month + i + 1, 1);
      var mi = 0, me = 0;
      for (final t in inPeriod) {
        if (!t.occurredAt.isBefore(m) && t.occurredAt.isBefore(next)) {
          if (t.kind == 'INCOME') {
            mi += t.amount;
          } else {
            me += t.amount;
          }
        }
      }
      // Budgets de ce mois (enveloppe totale) pour la ligne prévisionnelle.
      final monthKey = fmt.dateKey(m);
      var mb = 0;
      for (final s in budgetStats) {
        if (s.budget.periodStart == monthKey) mb += s.envelope;
      }
      points.add(MonthlyPoint(
          ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août',
              'sept', 'oct', 'nov', 'déc'][m.month - 1],
          income: mi.toDouble(),
          expense: me.toDouble(),
          budget: mb > 0 ? mb.toDouble() : null));
    }

    // ── Répartitions par catégorie parente ──
    Map<String, int> groupBy(bool income) {
      final map = <String, int>{};
      for (final t in inPeriod) {
        if ((t.kind == 'INCOME') != income) continue;
        final key = parentOf(t)?.name ?? 'Sans catégorie';
        map[key] = (map[key] ?? 0) + t.amount;
      }
      return map;
    }

    List<ChartSlice> slices(Map<String, int> raw) {
      final entries = raw.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (var i = 0; i < entries.length; i++)
          ChartSlice(
            entries[i].key,
            entries[i].value.toDouble(),
            _palette[i % _palette.length],
          ),
      ];
    }

    final expenseSlices = slices(groupBy(false));
    final incomeSlices = slices(groupBy(true));

    // ── Top sous-catégories (dépenses) ──
    final subMap = <String, int>{};
    for (final t in inPeriod) {
      if (t.kind != 'EXPENSE') continue;
      final cat = exactCategory(t);
      if (cat == null || cat.parentId == null) continue;
      subMap[cat.name] = (subMap[cat.name] ?? 0) + t.amount;
    }
    final topSubs = subMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxSub = topSubs.isEmpty ? 1.0 : topSubs.first.value.toDouble();

    // ── Budgets de la période ──
    final periodBudgets = budgetStats
        .where((s) => s.budget.periodStart.compareTo(fmt.dateKey(from)) >= 0)
        .toList();
    var totalEnvelope = 0, totalSpentBudget = 0;
    for (final s in periodBudgets) {
      totalEnvelope += s.envelope;
      totalSpentBudget += s.spent;
    }
    final budgetUse = totalEnvelope > 0
        ? totalSpentBudget / totalEnvelope * 100
        : 0.0;

    final theme = Theme.of(context);
    final or = theme.brightness == Brightness.dark ? LHColors.or : LHColors.orDeep;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LHSpacing.screen, LHSpacing.sm, LHSpacing.screen, 0),
            child: LhSegmented<int>(
              value: _months,
              items: const {3: '3 mois', 6: '6 mois', 12: '12 mois'},
              onChanged: (v) => setState(() => _months = v),
            ),
          ),
          SectionHeader('Vue d\'ensemble', overline: 'Période de $_months mois'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: StatTile(
                      label: 'Recettes',
                      value: Money(totalIncome, Currency.xof)
                          .format(withCode: false),
                      color: LHColors.financePositif,
                      icon: Icons.south_west_rounded,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Dépenses',
                      value: Money(totalExpense, Currency.xof)
                          .format(withCode: false),
                      color: LHColors.financeNegatif,
                      icon: Icons.north_east_rounded,
                    ),
                  ),
                ]),
                const SizedBox(height: LHSpacing.lg),
                Row(children: [
                  Expanded(
                    child: StatTile(
                      label: 'Solde net',
                      value: Money(net, Currency.xof).format(withCode: false),
                      color: net >= 0
                          ? LHColors.emeraudeClair
                          : LHColors.erreur,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Taux d\'épargne',
                      value: '${savingRate.toStringAsFixed(1)} %',
                      color: or,
                      icon: Icons.savings_outlined,
                    ),
                  ),
                ]),
                const SizedBox(height: LHSpacing.sm),
                Text(
                  'Dépense moyenne : ${Money(avgExpense.round(), Currency.xof).format(withCode: false)} / mois',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
          ),
          SectionHeader('Évolution mensuelle',
              overline: 'Recettes vs dépenses'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: Column(children: [
                LhMonthlyBars(points: points),
                const SizedBox(height: LHSpacing.md),
                const ChartLegend(entries: [
                  ChartSlice('Recettes', 0, LHColors.financePositif),
                  ChartSlice('Dépenses', 0, LHColors.financeNegatif),
                ]),
                const SizedBox(height: 6),
                ChartLegend(entries: [
                  ChartSlice('Budget prévisionnel', 0, or),
                ]),
              ]),
            ),
          ),
          SectionHeader('Répartition des dépenses', overline: 'Par catégorie'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: expenseSlices.isEmpty
                  ? Text(
                      'Aucune dépense sur la période.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : Column(children: [
                      LhDonutChart(
                        slices: expenseSlices,
                        centerValue: '100 %',
                        centerLabel: 'des dépenses',
                      ),
                      const SizedBox(height: LHSpacing.md),
                      for (final s in expenseSlices)
                        LhRankBar(
                          label: s.label,
                          value: Money(s.value.round(), Currency.xof)
                              .format(withCode: false),
                          ratio: totalExpense > 0
                              ? s.value / totalExpense
                              : 0,
                          color: s.color,
                          trailing:
                              '${(s.value / (totalExpense == 0 ? 1 : totalExpense) * 100).round()} %',
                        ),
                    ]),
            ),
          ),
          SectionHeader('Top sous-catégories', overline: 'Dépenses détaillées'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: topSubs.isEmpty
                  ? Text(
                      'Classez vos dépenses avec les sous-catégories pour '
                      'affiner l\'analyse.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : Column(
                      children: [
                        for (final e in topSubs.take(6))
                          LhRankBar(
                            label: e.key,
                            value: Money(e.value, Currency.xof)
                                .format(withCode: false),
                            ratio: e.value / maxSub,
                            color: or,
                          ),
                      ],
                    ),
            ),
          ),
          SectionHeader('Répartition des recettes', overline: 'Par catégorie'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: incomeSlices.isEmpty
                  ? Text(
                      'Aucune recette sur la période.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : Column(children: [
                      LhDonutChart(
                        slices: incomeSlices,
                        centerValue: '100 %',
                        centerLabel: 'des recettes',
                      ),
                      const SizedBox(height: LHSpacing.md),
                      for (final s in incomeSlices)
                        LhRankBar(
                          label: s.label,
                          value: Money(s.value.round(), Currency.xof)
                              .format(withCode: false),
                          ratio: totalIncome > 0
                              ? s.value / totalIncome
                              : 0,
                          color: s.color,
                          trailing:
                              '${(s.value / (totalIncome == 0 ? 1 : totalIncome) * 100).round()} %',
                        ),
                    ]),
            ),
          ),
          SectionHeader('Budgets : prévu vs réalisé',
              overline: 'Taux d\'utilisation'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
            child: LHCard(
              child: periodBudgets.isEmpty
                  ? Text(
                      'Aucun budget sur la période — planifiez des enveloppes '
                      'dans le module Finances.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: StatTile(
                              label: 'Enveloppe totale',
                              value: Money(totalEnvelope, Currency.xof)
                                  .format(withCode: false),
                              icon: Icons.savings_outlined,
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: 'Dépensé',
                              value: Money(totalSpentBudget, Currency.xof)
                                  .format(withCode: false),
                              color: budgetUse >= 100
                                  ? LHColors.erreur
                                  : budgetUse >= 80
                                      ? LHColors.alerte
                                      : LHColors.financePositif,
                              icon: Icons.trending_down_rounded,
                            ),
                          ),
                        ]),
                        const SizedBox(height: LHSpacing.sm),
                        Text(
                          'Taux d\'utilisation global : ${budgetUse.toStringAsFixed(1)} %',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: or),
                        ),
                        const SizedBox(height: LHSpacing.md),
                        for (final s in periodBudgets.take(8))
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      '${s.budget.name}'
                                      '${s.budget.planningCategory != null ? ' · ${s.budget.planningCategory}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    '${(s.ratio * 100).round()} %',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color: s.ratio >= 1
                                                ? LHColors.erreur
                                                : s.ratio >= 0.8
                                                    ? LHColors.alerte
                                                    : LHColors.emeraudeClair,
                                            fontWeight: FontWeight.w700),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                BudgetBar(ratio: s.ratio),
                                const SizedBox(height: 3),
                                Text(
                                  '${Money(s.spent, Currency.xof).format(withCode: false)} dépensés sur ${Money(s.envelope, Currency.xof).format(withCode: false)}'
                                  ' (${fmt.formatShort(fmt.parseKey(s.budget.periodStart))})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme
                                          .onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          SectionHeader('Projets : taux d\'évolution',
              overline: 'Avancement en cours'),
          const _ProjectsEvolution(),
        ],
      ),
    );
  }
}

/// Section Projets : progression calculée (tâches liées) ou ajustée
/// manuellement, avec taux d'évolution et échéance.
class _ProjectsEvolution extends ConsumerWidget {
  const _ProjectsEvolution();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final projects = ref.watch(projectsProvider(spaceId)).valueOrNull ?? [];
    final theme = Theme.of(context);
    final active = projects
        .where((p) =>
            p.status == 'PLANNED' ||
            p.status == 'ACTIVE' ||
            p.status == 'ON_HOLD')
        .toList();

    if (active.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
        child: LHCard(
          child: Text(
            'Aucun projet actif — créez des projets pour suivre leur taux '
            'd\'évolution ici.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LHSpacing.screen),
      child: LHCard(
        child: Column(
          children: [
            for (final p in active) _ProjectEvolutionTile(project: p),
          ],
        ),
      ),
    );
  }
}

class _ProjectEvolutionTile extends ConsumerWidget {
  const _ProjectEvolutionTile({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks =
        ref.watch(projectTasksProvider(project.id)).valueOrNull ?? [];
    final auto = autoProjectProgress(tasks);
    final progress =
        project.manualProgress != null ? project.manualProgress! / 100 : auto;
    final statusLabel = switch (project.status) {
      'PLANNED' => 'Planifié',
      'ACTIVE' => 'En cours',
      'ON_HOLD' => 'En pause',
      _ => project.status,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => context.push('/project/${project.id}'),
        borderRadius: BorderRadius.circular(LHRadius.lg),
        child: Row(children: [
          ProgressRing(
            progress: progress,
            size: 48,
            stroke: 4.5,
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
                    child: Text(project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  StatusChip(
                      label: statusLabel,
                      color: project.status == 'ACTIVE'
                          ? LHColors.emeraudeClair
                          : LHColors.neutre,
                      small: true),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Taux d\'évolution : ${(progress * 100).toStringAsFixed(0)} %'
                  '${project.targetDate != null ? ' · échéance le ${fmt.formatShort(fmt.parseKey(project.targetDate!))}' : ''}'
                  '${tasks.isNotEmpty ? ' · ${tasks.where((l) => l.task.status == 'DONE').length}/${tasks.length} tâches' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Palette de répartition (or, émeraude, bleu, ambre, violet, rouge…).
const List<Color> _palette = [
  Color(0xFFFFD700),
  Color(0xFF10A878),
  Color(0xFF5B8DD9),
  Color(0xFFE8720C),
  Color(0xFF8A6DD9),
  Color(0xFFE05B5B),
  Color(0xFF5BB8D9),
  Color(0xFFC9A227),
  Color(0xFF087F5B),
  Color(0xFF8A8A8A),
];
