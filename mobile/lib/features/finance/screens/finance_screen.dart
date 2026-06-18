import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/score_gauge.dart';
import '../providers/finance_providers.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(financeDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance),
            onPressed: () => context.push('/finance/accounts'),
            tooltip: 'Comptes',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => context.push('/finance/transactions/add'),
            tooltip: 'Transaction',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(financeDashboardProvider),
        child: dashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (dash) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Score de santé financière + solde global
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ScoreGauge(score: dash.score, size: 110, label: 'Santé'),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Solde global', style: TextStyle(color: LifeHelmColors.textSecondary)),
                                const SizedBox(height: 4),
                                Text(
                                  FormatUtils.formatFCFA(dash.totalBalance),
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: LifeHelmColors.finance),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  children: dash.accounts.map((a) {
                                    return Chip(
                                      label: Text(
                                        '${a.name}: ${FormatUtils.formatCompact(a.balance)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ).animate().fade(duration: 400.ms),
              const SizedBox(height: 16),

              // Résumé du mois
              _MonthSummaryCard(dash: dash),
              const SizedBox(height: 16),

              // Catégories de dépenses
              if (dash.byCategory.isNotEmpty) ...[
                _CategoriesCard(categories: dash.byCategory),
                const SizedBox(height: 16),
              ],

              // Actions rapides
              const Text('Actions rapides', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: [
                  _QuickAction(icon: Icons.add_circle, label: 'Dépense', color: LifeHelmColors.danger, onTap: () => context.push('/finance/transactions/add?type=EXPENSE')),
                  _QuickAction(icon: Icons.add_circle_outline, label: 'Revenu', color: LifeHelmColors.success, onTap: () => context.push('/finance/transactions/add?type=INCOME')),
                  _QuickAction(icon: Icons.savings, label: 'Épargne', color: LifeHelmColors.info, onTap: () => context.push('/finance/savings')),
                  _QuickAction(icon: Icons.people, label: 'Tontine', color: LifeHelmColors.accent, onTap: () => context.push('/finance/tontines')),
                  _QuickAction(icon: Icons.money_off, label: 'Dettes', color: LifeHelmColors.warning, onTap: () => context.push('/finance/debts')),
                  _QuickAction(icon: Icons.receipt_long, label: 'Factures', color: LifeHelmColors.primary, onTap: () => context.push('/finance/bills')),
                  _QuickAction(icon: Icons.swap_horiz, label: 'Transfert', color: LifeHelmColors.textSecondary, onTap: () => context.push('/finance/transactions/add?type=TRANSFER')),
                  _QuickAction(icon: Icons.list, label: 'Historique', color: LifeHelmColors.goals, onTap: () => context.push('/finance/transactions')),
                ],
              ),
              const SizedBox(height: 24),

              // Objectifs d'épargne
              if (dash.savingsGoals.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Objectifs d\'épargne', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(onPressed: () => context.push('/finance/savings'), child: const Text('Voir tout')),
                  ],
                ),
                ...dash.savingsGoals.take(3).map((g) => _SavingsGoalTile(goal: g)),
                const SizedBox(height: 16),
              ],

              // Dettes
              if (dash.debts.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dettes & créances', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(onPressed: () => context.push('/finance/debts'), child: const Text('Voir tout')),
                  ],
                ),
                ...dash.debts.take(3).map((d) => _DebtTile(debt: d)),
                const SizedBox(height: 16),
              ],

              // Factures à venir
              if (dash.bills.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Factures à venir', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(onPressed: () => context.push('/finance/bills'), child: const Text('Voir tout')),
                  ],
                ),
                ...dash.bills.take(3).map((b) => _BillTile(bill: b)),
                const SizedBox(height: 16),
              ],

              // Tontines
              if (dash.tontines.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mes tontines', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(onPressed: () => context.push('/finance/tontines'), child: const Text('Voir tout')),
                  ],
                ),
                ...dash.tontines.take(2).map((t) => _TontineTile(tontine: t)),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({required this.dash});
  final FinanceDashboard dash;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Ce mois-ci', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: dash.savingsRate >= 20 ? LifeHelmColors.success.withValues(alpha: 0.1) : LifeHelmColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Taux épargne: ${dash.savingsRate}%',
                    style: TextStyle(
                      color: dash.savingsRate >= 20 ? LifeHelmColors.success : LifeHelmColors.warning,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryBox(
                    label: 'Revenus',
                    amount: dash.monthIncome,
                    color: LifeHelmColors.success,
                    change: dash.incomeChange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    label: 'Dépenses',
                    amount: dash.monthExpenses,
                    color: LifeHelmColors.danger,
                    change: dash.expensesChange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    label: 'Épargne',
                    amount: dash.monthSavings,
                    color: LifeHelmColors.info,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.label, required this.amount, required this.color, this.change});
  final String label;
  final num amount;
  final Color color;
  final int? change;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          FormatUtils.formatCompact(amount),
          style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16),
        ),
        if (change != null && change != 0)
          Row(
            children: [
              Icon(
                change! > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 10,
                color: change! > 0 ? LifeHelmColors.success : LifeHelmColors.danger,
              ),
              const SizedBox(width: 2),
              Text(
                '${change!.abs()}%',
                style: TextStyle(
                  color: change! > 0 ? LifeHelmColors.success : LifeHelmColors.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.categories});
  final List<CategoryAmount> categories;

  @override
  Widget build(BuildContext context) {
    final max = categories.first.amount.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dépenses par catégorie', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            ...categories.take(6).map((c) {
              final pct = (c.amount / max * 100).clamp(0.0, 100.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 100, child: Text(c.category, style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: LifeHelmColors.textTertiary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: pct / 100,
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: LifeHelmColors.finance,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        FormatUtils.formatCompact(c.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SavingsGoalTile extends StatelessWidget {
  const _SavingsGoalTile({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: goal.progress,
                backgroundColor: LifeHelmColors.info.withValues(alpha: 0.15),
                color: LifeHelmColors.info,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${FormatUtils.formatCompact(goal.currentAmount)} / ${FormatUtils.formatCompact(goal.targetAmount)}',
              style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
            ),
          ],
        ),
        trailing: Text(
          '${(goal.progress * 100).toInt()}%',
          style: const TextStyle(fontWeight: FontWeight.w800, color: LifeHelmColors.info),
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt});
  final Debt debt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (debt.isOwing ? LifeHelmColors.danger : LifeHelmColors.success).withValues(alpha: 0.15),
          child: Icon(debt.isOwing ? Icons.arrow_upward : Icons.arrow_downward, color: debt.isOwing ? LifeHelmColors.danger : LifeHelmColors.success),
        ),
        title: Text(debt.personName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          debt.isOwing ? 'Tu dois' : 'On te doit',
          style: TextStyle(color: debt.isOwing ? LifeHelmColors.danger : LifeHelmColors.success),
        ),
        trailing: Text(
          FormatUtils.formatCompact(debt.amount),
          style: TextStyle(fontWeight: FontWeight.w700, color: debt.isOwing ? LifeHelmColors.danger : LifeHelmColors.success),
        ),
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill});
  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final days = bill.nextDueDate.difference(DateTime.now()).inDays;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (days <= 3 ? LifeHelmColors.danger : LifeHelmColors.warning).withValues(alpha: 0.15),
          child: Icon(Icons.receipt, color: days <= 3 ? LifeHelmColors.danger : LifeHelmColors.warning),
        ),
        title: Text(bill.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(days <= 0 ? 'À payer aujourd\'hui' : 'Dans $days jour(s)'),
        trailing: Text(FormatUtils.formatCompact(bill.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _TontineTile extends StatelessWidget {
  const _TontineTile({required this.tontine});
  final Tontine tontine;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFCE4CF),
          child: Icon(Icons.people, color: LifeHelmColors.accent),
        ),
        title: Text(tontine.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Mise: ${FormatUtils.formatCompact(tontine.contributionAmount)} • Ton rang: ${tontine.myRank}/${tontine.totalMembers}'),
        trailing: Text(
          'Pot:\n${FormatUtils.formatCompact(tontine.totalPot)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
