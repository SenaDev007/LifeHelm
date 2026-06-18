import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/score_gauge.dart';
import '../../finance/providers/finance_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(homeDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: const TextStyle(fontSize: 14, color: LifeHelmColors.textSecondary, fontWeight: FontWeight.w500),
            ),
            const Text(
              'LifeHelm',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/ai'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeDashboardProvider),
        child: dashboardAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(error: e.toString(), onRetry: () => ref.invalidate(homeDashboardProvider)),
          data: (dash) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Score global 360°
              _GlobalScoreCard(dashboard: dash)
                  .animate()
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),

              // 6 piliers
              Text('Tes 6 piliers de vie', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  PillarScoreBar(label: 'Finance', score: dash.scores.finance, color: LifeHelmColors.finance, icon: Icons.account_balance_wallet, onTap: () => context.push('/finance')),
                  PillarScoreBar(label: 'Santé', score: dash.scores.health, color: LifeHelmColors.health, icon: Icons.favorite, onTap: () => context.push('/health')),
                  PillarScoreBar(label: 'Routines', score: dash.scores.routines, color: LifeHelmColors.routines, icon: Icons.today, onTap: () => context.push('/routines')),
                  PillarScoreBar(label: 'Objectifs', score: dash.scores.goals, color: LifeHelmColors.goals, icon: Icons.flag, onTap: () => context.push('/goals')),
                  PillarScoreBar(label: 'Carrière', score: dash.scores.career, color: LifeHelmColors.career, icon: Icons.work, onTap: () {}),
                  PillarScoreBar(label: 'Relations', score: dash.scores.relations, color: LifeHelmColors.relations, icon: Icons.people, onTap: () {}),
                ],
              ),
              const SizedBox(height: 24),

              // Résumé financier
              _FinancialSummaryCard(dashboard: dash)
                  .animate(delay: 200.ms)
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),

              // Habitudes du jour
              _HabitsCard(doneToday: dash.habits.doneToday)
                  .animate(delay: 300.ms)
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),

              // Top priorités
              if (dash.goals.topPriorities.isNotEmpty) ...[
                _TopPrioritiesCard(priorities: dash.goals.topPriorities)
                    .animate(delay: 400.ms)
                    .fade(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0),
                const SizedBox(height: 16),
              ],

              // Alertes
              if (dash.alerts.isNotEmpty) ...[
                _AlertsCard(alerts: dash.alerts)
                    .animate(delay: 500.ms)
                    .fade(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0),
                const SizedBox(height: 16),
              ],

              // HELM AI insights
              _HelmAICard(unreadInsights: dash.unreadInsights)
                  .animate(delay: 600.ms)
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour 👋';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }
}

class _GlobalScoreCard extends StatelessWidget {
  const _GlobalScoreCard({required this.dashboard});
  final HomeDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            ScoreGauge(score: dashboard.globalScore, size: 130, label: 'Score de vie'),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FormatUtils.scoreLabel(dashboard.globalScore),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: LifeHelmColors.primary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ta vie globale combinée',
                    style: TextStyle(color: LifeHelmColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.trending_up, color: LifeHelmColors.success, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Mise à jour maintenant',
                        style: TextStyle(color: LifeHelmColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  const _FinancialSummaryCard({required this.dashboard});
  final HomeDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.push('/finance'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: LifeHelmColors.finance, size: 20),
                  const SizedBox(width: 8),
                  const Text('Finance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  Text(
                    '${dashboard.financial.accountsCount} comptes',
                    style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Solde global',
                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                FormatUtils.formatFCFA(dashboard.financial.totalBalance),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: LifeHelmColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Revenus',
                      value: FormatUtils.formatCompact(dashboard.financial.income),
                      color: LifeHelmColors.success,
                      change: dashboard.financial.savingsRate > 0 ? '+${dashboard.financial.savingsRate}%' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'Dépenses',
                      value: FormatUtils.formatCompact(dashboard.financial.expenses),
                      color: LifeHelmColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'Épargne',
                      value: FormatUtils.formatCompact(dashboard.financial.savings),
                      color: LifeHelmColors.info,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color, this.change});
  final String label;
  final String value;
  final Color color;
  final String? change;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
        if (change != null)
          Text(change!, style: TextStyle(color: LifeHelmColors.success, fontSize: 10)),
      ],
    );
  }
}

class _HabitsCard extends StatelessWidget {
  const _HabitsCard({required this.doneToday});
  final int doneToday;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.push('/routines'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: LifeHelmColors.routines.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle, color: LifeHelmColors.routines),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Habitudes du jour', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      doneToday == 0 ? 'Aucune habitude cochée aujourd\'hui' : '$doneToday habitude(s) accomplie(s) aujourd\'hui',
                      style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: LifeHelmColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopPrioritiesCard extends StatelessWidget {
  const _TopPrioritiesCard({required this.priorities});
  final List<TopPriority> priorities;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: LifeHelmColors.goals, size: 20),
                const SizedBox(width: 8),
                const Text('Top priorités', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...priorities.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: LifeHelmColors.danger, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/goals'),
                      child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alerts});
  final List<HomeAlert> alerts;

  Color _color(String type) {
    switch (type) {
      case 'BILL': return LifeHelmColors.warning;
      case 'DEBT': return LifeHelmColors.danger;
      case 'SLEEP': return LifeHelmColors.info;
      case 'FINANCE': return LifeHelmColors.danger;
      default: return LifeHelmColors.textSecondary;
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'BILL': return Icons.receipt_long;
      case 'DEBT': return Icons.money_off;
      case 'SLEEP': return Icons.bedtime;
      case 'FINANCE': return Icons.trending_down;
      default: return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: LifeHelmColors.warning, size: 20),
                const SizedBox(width: 8),
                const Text('Alertes intelligentes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...alerts.map((a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(a.type), color: _color(a.type), size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a.message, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _HelmAICard extends ConsumerWidget {
  const _HelmAICard({required this.unreadInsights});
  final int unreadInsights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: LifeHelmColors.primary,
      child: InkWell(
        onTap: () => context.push('/ai'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HELM AI', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16)),
                    Text(
                      unreadInsights > 0
                          ? '$unreadInsights nouveau(x) insight(s) à découvrir'
                          : 'Ton conseiller de vie holistique',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
        const SizedBox(height: 16),
        const Text('Impossible de charger les données', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      ],
    );
  }
}
