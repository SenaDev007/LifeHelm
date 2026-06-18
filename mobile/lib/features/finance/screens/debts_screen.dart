import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(debtsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dettes & créances'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Ajouter',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(debtsProvider),
        child: debtsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
                  const SizedBox(height: 16),
                  Text('Erreur: $e', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(debtsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (debts) {
            final owing = debts.where((d) => d.isOwing && !d.settled).toList();
            final owed = debts.where((d) => !d.isOwing && !d.settled).toList();
            final settled = debts.where((d) => d.settled).toList();
            final totalOwing = owing.fold<num>(0, (s, d) => s + d.amount);
            final totalOwed = owed.fold<num>(0, (s, d) => s + d.amount);
            final net = totalOwed - totalOwing;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Bilan net
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('Bilan net', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          FormatUtils.formatFCFA(net),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: net >= 0 ? LifeHelmColors.success : LifeHelmColors.danger,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                label: 'Tu dois',
                                value: FormatUtils.formatCompact(totalOwing),
                                color: LifeHelmColors.danger,
                              ),
                            ),
                            Expanded(
                              child: _MiniStat(
                                label: 'On te doit',
                                value: FormatUtils.formatCompact(totalOwed),
                                color: LifeHelmColors.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tu dois
                if (owing.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(width: 4, height: 16, color: LifeHelmColors.danger),
                      const SizedBox(width: 8),
                      const Text('Tu dois', style: TextStyle(fontWeight: FontWeight.w700, color: LifeHelmColors.danger)),
                      const Spacer(),
                      Text(FormatUtils.formatFCFA(totalOwing), style: const TextStyle(color: LifeHelmColors.danger, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...owing.map((d) => _DebtCard(debt: d)),
                  const SizedBox(height: 16),
                ],

                // On te doit
                if (owed.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(width: 4, height: 16, color: LifeHelmColors.success),
                      const SizedBox(width: 8),
                      const Text('On te doit', style: TextStyle(fontWeight: FontWeight.w700, color: LifeHelmColors.success)),
                      const Spacer(),
                      Text(FormatUtils.formatFCFA(totalOwed), style: const TextStyle(color: LifeHelmColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...owed.map((d) => _DebtCard(debt: d)),
                  const SizedBox(height: 16),
                ],

                // Réglées
                if (settled.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: LifeHelmColors.textTertiary, size: 16),
                      SizedBox(width: 8),
                      Text('Réglées', style: TextStyle(fontWeight: FontWeight.w700, color: LifeHelmColors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...settled.map((d) => _DebtCard(debt: d, dimmed: true)),
                ],

                if (debts.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 64, color: LifeHelmColors.textTertiary),
                          const SizedBox(height: 16),
                          const Text('Aucune dette en cours', style: TextStyle(color: LifeHelmColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.warning,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddDebtDialog());
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
      ],
    );
  }
}

class _DebtCard extends ConsumerWidget {
  const _DebtCard({required this.debt, this.dimmed = false});
  final Debt debt;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwing = debt.isOwing;
    final color = isOwing ? LifeHelmColors.danger : LifeHelmColors.success;
    return Dismissible(
      key: ValueKey(debt.id),
      direction: dimmed ? DismissDirection.endToStart : DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: LifeHelmColors.success,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: LifeHelmColors.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Settle
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Marquer comme réglée ?'),
              content: Text('${debt.personName} — ${FormatUtils.formatFCFA(debt.amount)}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: LifeHelmColors.success),
                  child: const Text('Régler'),
                ),
              ],
            ),
          );
        } else {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Supprimer ?'),
              content: Text('Supprimer cette dette ?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          );
        }
      },
      onDismissed: (direction) async {
        try {
          if (direction == DismissDirection.startToEnd) {
            await ref.read(financeRepositoryProvider).settleDebt(debt.id);
          } else {
            await ref.read(financeRepositoryProvider).deleteDebt(debt.id);
          }
          ref.invalidate(debtsProvider);
          ref.invalidate(financeDashboardProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(direction == DismissDirection.startToEnd ? 'Dette réglée' : 'Dette supprimée'),
                backgroundColor: LifeHelmColors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
            );
            ref.invalidate(debtsProvider);
          }
        }
      },
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(isOwing ? Icons.arrow_upward : Icons.arrow_downward, color: color),
            ),
            title: Text(
              debt.personName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOwing ? 'Tu dois' : 'On te doit',
                  style: TextStyle(color: color, fontSize: 12),
                ),
                if (debt.dueDate != null)
                  Text(
                    'Échéance: ${FormatUtils.formatDate(debt.dueDate!)}',
                    style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11),
                  ),
                if (debt.settled)
                  const Text('Réglée', style: TextStyle(color: LifeHelmColors.success, fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ),
            trailing: Text(
              FormatUtils.formatCompact(debt.amount),
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddDebtDialog extends ConsumerStatefulWidget {
  const _AddDebtDialog();

  @override
  ConsumerState<_AddDebtDialog> createState() => _AddDebtDialogState();
}

class _AddDebtDialogState extends ConsumerState<_AddDebtDialog> {
  final _formKey = GlobalKey<FormState>();
  final _personCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _direction = 'OWING';
  DateTime? _dueDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _personCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(financeRepositoryProvider).createDebt({
        'direction': _direction,
        'personName': _personCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text),
        if (_dueDate != null) 'dueDate': _dueDate!.toIso8601String(),
      });
      ref.invalidate(debtsProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dette enregistrée'), backgroundColor: LifeHelmColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle dette'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Direction toggle
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _direction = 'OWING'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _direction == 'OWING' ? LifeHelmColors.danger.withValues(alpha: 0.1) : Colors.white,
                          border: Border.all(color: _direction == 'OWING' ? LifeHelmColors.danger : LifeHelmColors.textTertiary, width: _direction == 'OWING' ? 2 : 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.arrow_upward, color: LifeHelmColors.danger),
                            const SizedBox(height: 4),
                            Text('Tu dois', style: TextStyle(color: LifeHelmColors.danger, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _direction = 'OWED'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _direction == 'OWED' ? LifeHelmColors.success.withValues(alpha: 0.1) : Colors.white,
                          border: Border.all(color: _direction == 'OWED' ? LifeHelmColors.success : LifeHelmColors.textTertiary, width: _direction == 'OWED' ? 2 : 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.arrow_downward, color: LifeHelmColors.success),
                            const SizedBox(height: 4),
                            Text('On te doit', style: TextStyle(color: LifeHelmColors.success, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _personCtrl,
                label: 'Personne',
                hint: 'Ex: Koffi, Maman...',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _amountCtrl,
                label: 'Montant (FCFA)',
                hint: '10000',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Montant requis';
                  if (double.tryParse(v) == null) return 'Invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  );
                  if (d != null) setState(() => _dueDate = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Échéance (optionnelle)'),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text(_dueDate == null ? 'Aucune' : FormatUtils.formatDate(_dueDate!)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        LifeHelmButton(
          label: 'Enregistrer',
          isLoading: _isLoading,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }
}
