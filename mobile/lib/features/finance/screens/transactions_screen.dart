import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../models/models.dart';
import '../providers/finance_providers.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionsProvider(100));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilters(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => context.push('/finance/transactions/add'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(transactionsProvider(100)),
        child: txs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (list) {
            if (list.isEmpty) {
              return _EmptyState(
                icon: Icons.receipt_long,
                title: 'Aucune transaction',
                desc: 'Ajoute ta première transaction pour commencer à suivre tes finances.',
                cta: 'Ajouter',
                onTap: () => context.push('/finance/transactions/add'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = list[i];
                final isIncome = t.type == 'INCOME';
                final cat = t.category != null ? AppCategories.expenseCategories[t.category] ?? AppCategories.incomeCategories[t.category] : null;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isIncome ? LifeHelmColors.success : LifeHelmColors.danger).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isIncome ? LifeHelmColors.success : LifeHelmColors.danger,
                    ),
                  ),
                  title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${cat != null ? '$cat ' : ''}${t.account?.name ?? ''} • ${t.date != null ? FormatUtils.formatDate(t.date!) : ''}',
                    style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                  ),
                  trailing: Text(
                    '${isIncome ? '+' : '-'}${FormatUtils.formatFCFA(t.amount, withSymbol: false)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isIncome ? LifeHelmColors.success : LifeHelmColors.danger,
                    ),
                  ),
                  onLongPress: () => _showActions(context, ref, t),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtrer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(title: const Text('Toutes'), onTap: () => Navigator.pop(context)),
            ListTile(title: const Text('Revenus'), onTap: () => Navigator.pop(context)),
            ListTile(title: const Text('Dépenses'), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, Transaction t) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: LifeHelmColors.danger),
              title: const Text('Supprimer'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(financeRepositoryProvider).deleteTransaction(t.id);
                ref.invalidate(transactionsProvider(100));
                ref.invalidate(financeDashboardProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.desc, required this.cta, required this.onTap});
  final IconData icon;
  final String title;
  final String desc;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: LifeHelmColors.textTertiary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(color: LifeHelmColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: Text(cta)),
          ],
        ),
      ),
    );
  }
}
