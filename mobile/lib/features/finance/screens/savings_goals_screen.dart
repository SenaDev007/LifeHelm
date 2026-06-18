import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(savingsGoalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Objectifs d\'épargne'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Nouvel objectif',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(savingsGoalsProvider),
        child: goalsAsync.when(
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
                    onPressed: () => ref.invalidate(savingsGoalsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (goals) {
            if (goals.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.savings, size: 64, color: LifeHelmColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text('Aucun objectif d\'épargne', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Créer un objectif'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final totalSaved = goals.fold<num>(0, (s, g) => s + g.currentAmount);
            final totalTarget = goals.fold<num>(0, (s, g) => s + g.targetAmount);
            final overallPct = totalTarget > 0 ? (totalSaved / totalTarget * 100).clamp(0, 100).toDouble() : 0.0;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total épargné', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          FormatUtils.formatFCFA(totalSaved),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: LifeHelmColors.info,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: overallPct / 100,
                            backgroundColor: LifeHelmColors.info.withValues(alpha: 0.15),
                            color: LifeHelmColors.info,
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${overallPct.toStringAsFixed(0)}% de ${FormatUtils.formatCompact(totalTarget)}',
                          style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...goals.map((g) => _SavingsGoalCard(goal: g)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.info,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddGoalDialog());
  }
}

class _SavingsGoalCard extends ConsumerWidget {
  const _SavingsGoalCard({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = (goal.progress * 100).toInt();
    final isDone = goal.progress >= 1;
    final remaining = goal.targetAmount - goal.currentAmount;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showContributionDialog(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        if (goal.description != null)
                          Text(goal.description!, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDone ? LifeHelmColors.success : LifeHelmColors.info).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$pct%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isDone ? LifeHelmColors.success : LifeHelmColors.info,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  backgroundColor: LifeHelmColors.info.withValues(alpha: 0.15),
                  color: isDone ? LifeHelmColors.success : LifeHelmColors.info,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${FormatUtils.formatCompact(goal.currentAmount)} / ${FormatUtils.formatCompact(goal.targetAmount)}',
                    style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                  ),
                  if (goal.deadline != null)
                    Text(
                      'Avant le ${FormatUtils.formatDate(goal.deadline!)}',
                      style: const TextStyle(fontSize: 12, color: LifeHelmColors.textTertiary),
                    )
                  else if (!isDone)
                    Text(
                      'Reste ${FormatUtils.formatCompact(remaining)}',
                      style: const TextStyle(fontSize: 12, color: LifeHelmColors.textTertiary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showContributionDialog(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Ajouter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LifeHelmColors.info,
                        side: const BorderSide(color: LifeHelmColors.info),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: LifeHelmColors.danger),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Supprimer ?'),
                          content: Text('Supprimer l\'objectif « ${goal.name} » ?'),
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
                        await ref.read(financeRepositoryProvider).deleteSavingsGoal(goal.id);
                        ref.invalidate(savingsGoalsProvider);
                        ref.invalidate(financeDashboardProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Objectif supprimé'), backgroundColor: LifeHelmColors.success),
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
      ),
    );
  }

  void _showContributionDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _ContributionDialog(goal: goal),
    );
  }
}

class _AddGoalDialog extends ConsumerStatefulWidget {
  const _AddGoalDialog();

  @override
  ConsumerState<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends ConsumerState<_AddGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  DateTime? _deadline;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(financeRepositoryProvider).createSavingsGoal({
        'name': _nameCtrl.text.trim(),
        'targetAmount': double.parse(_targetCtrl.text),
        if (_deadline != null) 'deadline': _deadline!.toIso8601String(),
      });
      ref.invalidate(savingsGoalsProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Objectif créé'), backgroundColor: LifeHelmColors.success),
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
      title: const Text('Nouvel objectif'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LifeHelmTextField(
                controller: _nameCtrl,
                label: 'Nom de l\'objectif',
                hint: 'Ex: Moto, Voyage, Mariage',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _targetCtrl,
                label: 'Montant cible (FCFA)',
                hint: '100000',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Montant requis';
                  if (double.tryParse(v) == null) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (d != null) setState(() => _deadline = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date limite (optionnelle)'),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text(_deadline == null ? 'Aucune' : FormatUtils.formatDate(_deadline!)),
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
          label: 'Créer',
          isLoading: _isLoading,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }
}

class _ContributionDialog extends ConsumerStatefulWidget {
  const _ContributionDialog({required this.goal});
  final SavingsGoal goal;

  @override
  ConsumerState<_ContributionDialog> createState() => _ContributionDialogState();
}

class _ContributionDialogState extends ConsumerState<_ContributionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.contributeToSavingsGoal(
        widget.goal.id,
        double.parse(_amountCtrl.text),
      );
      ref.invalidate(savingsGoalsProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contribution ajoutée'), backgroundColor: LifeHelmColors.success),
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
      title: Text('Ajouter à « ${widget.goal.name} »'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Actuellement : ${FormatUtils.formatFCFA(widget.goal.currentAmount)} / ${FormatUtils.formatFCFA(widget.goal.targetAmount)}',
              style: const TextStyle(color: LifeHelmColors.textSecondary),
            ),
            const SizedBox(height: 16),
            LifeHelmTextField(
              controller: _amountCtrl,
              label: 'Montant (FCFA)',
              hint: '5000',
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Montant requis';
                if (double.tryParse(v) == null) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        LifeHelmButton(
          label: 'Épargner',
          isLoading: _isLoading,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }
}
