import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(billsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures récurrentes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Nouvelle facture',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(billsProvider),
        child: billsAsync.when(
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
                    onPressed: () => ref.invalidate(billsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (bills) {
            if (bills.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 64, color: LifeHelmColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text('Aucune facture enregistrée', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter une facture'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final total = bills.fold<num>(0, (s, b) => s + b.amount);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total mensuel', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                              Text(
                                FormatUtils.formatFCFA(total),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: LifeHelmColors.warning),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: LifeHelmColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${bills.length} facture(s)',
                            style: const TextStyle(color: LifeHelmColors.warning, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...bills.map((b) => _BillCard(bill: b)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddBillDialog());
  }
}

class _BillCard extends ConsumerWidget {
  const _BillCard({required this.bill});
  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final days = bill.nextDueDate.difference(now).inDays;
    final isUrgent = days <= 3 && days >= 0;
    final isOverdue = days < 0;
    final color = isOverdue
        ? LifeHelmColors.danger
        : isUrgent
            ? LifeHelmColors.danger
            : days <= 7
                ? LifeHelmColors.warning
                : LifeHelmColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bill.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        'Jour ${bill.dueDay} • ${_recurrenceLabel(bill.recurrence)}',
                        style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  FormatUtils.formatCompact(bill.amount),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    isOverdue
                        ? 'En retard de ${days.abs()} jour(s)'
                        : days == 0
                            ? 'À payer aujourd\'hui'
                            : 'Dans $days jour(s) — ${FormatUtils.formatDate(bill.nextDueDate)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(financeRepositoryProvider).payBill(bill.id);
                        ref.invalidate(billsProvider);
                        ref.invalidate(financeDashboardProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Facture marquée comme payée'),
                              backgroundColor: LifeHelmColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Marquer payée'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LifeHelmColors.success,
                      side: const BorderSide(color: LifeHelmColors.success),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: LifeHelmColors.danger),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer ?'),
                        content: Text('Supprimer la facture « ${bill.name} » ?'),
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
                    if (confirm != true) return;
                    try {
                      await ref.read(financeRepositoryProvider).deleteBill(bill.id);
                      ref.invalidate(billsProvider);
                      ref.invalidate(financeDashboardProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Facture supprimée'), backgroundColor: LifeHelmColors.success),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _recurrenceLabel(String r) {
    switch (r) {
      case 'WEEKLY': return 'Hebdo';
      case 'DAILY': return 'Quotidienne';
      case 'YEARLY': return 'Annuelle';
      default: return 'Mensuelle';
    }
  }
}

class _AddBillDialog extends ConsumerStatefulWidget {
  const _AddBillDialog();

  @override
  ConsumerState<_AddBillDialog> createState() => _AddBillDialogState();
}

class _AddBillDialogState extends ConsumerState<_AddBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _dueDayCtrl = TextEditingController(text: '1');
  String _recurrence = 'MONTHLY';
  DateTime _nextDue = DateTime.now().add(const Duration(days: 7));
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _dueDayCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(financeRepositoryProvider).createBill({
        'name': _nameCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text),
        'dueDay': int.tryParse(_dueDayCtrl.text) ?? 1,
        'recurrence': _recurrence,
        'nextDueDate': _nextDue.toIso8601String(),
      });
      ref.invalidate(billsProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facture ajoutée'), backgroundColor: LifeHelmColors.success),
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
      title: const Text('Nouvelle facture'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LifeHelmTextField(
                controller: _nameCtrl,
                label: 'Nom de la facture',
                hint: 'Ex: Électricité SBEE, Loyer...',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _amountCtrl,
                label: 'Montant (FCFA)',
                hint: '15000',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Montant requis';
                  if (double.tryParse(v) == null) return 'Invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _recurrence,
                decoration: const InputDecoration(labelText: 'Récurrence'),
                items: const [
                  DropdownMenuItem(value: 'DAILY', child: Text('Quotidienne')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Hebdomadaire')),
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Mensuelle')),
                  DropdownMenuItem(value: 'YEARLY', child: Text('Annuelle')),
                ],
                onChanged: (v) => setState(() => _recurrence = v ?? 'MONTHLY'),
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _dueDayCtrl,
                label: 'Jour d\'échéance (1-31)',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 31) return 'Jour 1-31';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _nextDue,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _nextDue = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Prochaine échéance'),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text(FormatUtils.formatDate(_nextDue)),
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
