import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/goals_providers.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes objectifs de vie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Nouvel objectif',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(goalsProvider),
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
                    onPressed: () => ref.invalidate(goalsProvider),
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
                      const Icon(Icons.flag_outlined, size: 64, color: LifeHelmColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text('Aucun objectif de vie', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      const SizedBox(height: 8),
                      const Text('Définis ce qui compte vraiment pour toi', style: TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12)),
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
            final activeCount = goals.where((g) => !g.completed).length;
            final completedCount = goals.where((g) => g.completed).length;
            final sorted = [...goals]..sort((a, b) {
                if (a.completed != b.completed) return a.completed ? 1 : -1;
                return a.priority.compareTo(b.priority);
              });
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(child: _StatBox(label: 'En cours', value: '$activeCount', color: LifeHelmColors.goals)),
                    const SizedBox(width: 8),
                    Expanded(child: _StatBox(label: 'Atteints', value: '$completedCount', color: LifeHelmColors.success)),
                    const SizedBox(width: 8),
                    Expanded(child: _StatBox(label: 'Total', value: '${goals.length}', color: LifeHelmColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 16),
                ...sorted.map((g) => _GoalCard(goal: g)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.goals,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddGoalDialog());
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final LifeGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = GoalDomains.colorOf(goal.domain);
    final emoji = GoalDomains.domainEmojis[goal.domain] ?? '🎯';
    final domainLabel = GoalDomains.domainLabels[goal.domain] ?? goal.domain;
    final typeLabel = GoalTypes.typeLabels[goal.type] ?? goal.type;
    final daysLeft = goal.deadline?.difference(DateTime.now()).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showActionsSheet(context, ref),
        borderRadius: BorderRadius.circular(16),
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
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                goal.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  decoration: goal.completed ? TextDecoration.lineThrough : null,
                                  color: goal.completed ? LifeHelmColors.textTertiary : LifeHelmColors.textPrimary,
                                ),
                              ),
                            ),
                            if (goal.completed)
                              const Icon(Icons.check_circle, color: LifeHelmColors.success, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            _Chip(text: domainLabel, color: color),
                            _Chip(text: typeLabel, color: LifeHelmColors.textSecondary),
                            if (goal.priority == 1 || goal.priority == 2)
                              const _Chip(text: 'Priorité haute', color: LifeHelmColors.danger),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (goal.type == 'NUMERIC' && goal.targetValue != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: goal.progress,
                    backgroundColor: color.withValues(alpha: 0.15),
                    color: color,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${goal.currentValue}${goal.unit != null ? ' ${goal.unit}' : ''} / ${goal.targetValue}${goal.unit != null ? ' ${goal.unit}' : ''}',
                      style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                    ),
                    Text('${(goal.progress * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 12)),
                  ],
                ),
              ],
              if (goal.type == 'MILESTONE' && goal.milestones.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: goal.progress,
                    backgroundColor: color.withValues(alpha: 0.15),
                    color: color,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${goal.completedMilestones}/${goal.milestones.length} étapes',
                  style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                ),
              ],
              if (goal.deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event, size: 14, color: daysLeft != null && daysLeft < 7 ? LifeHelmColors.danger : LifeHelmColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      daysLeft == null
                          ? 'Échéance: ${FormatUtils.formatDate(goal.deadline!)}'
                          : daysLeft < 0
                              ? 'En retard de ${daysLeft.abs()} jour(s)'
                              : daysLeft == 0
                                  ? 'Échéance aujourd\'hui'
                                  : 'Dans $daysLeft jour(s) — ${FormatUtils.formatDate(goal.deadline!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: daysLeft != null && daysLeft < 7 ? LifeHelmColors.danger : LifeHelmColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: LifeHelmColors.textTertiary, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(goal.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (goal.description != null) ...[
                const SizedBox(height: 4),
                Text(goal.description!, style: const TextStyle(color: LifeHelmColors.textSecondary)),
              ],
              const SizedBox(height: 16),
              if (goal.type == 'NUMERIC')
                LifeHelmButton(
                  label: 'Ajouter progression',
                  icon: Icons.trending_up,
                  onPressed: () async {
                    Navigator.pop(ctx);
                    _showProgressDialog(context, ref);
                  },
                ),
              if (!goal.completed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LifeHelmButton(
                    label: 'Marquer comme atteint',
                    icon: Icons.check_circle,
                    variant: LifeHelmButtonVariant.accent,
                    onPressed: () async {
                      try {
                        await ref.read(goalsRepositoryProvider).toggleComplete(goal.id);
                        ref.invalidate(goalsProvider);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Objectif marqué comme atteint 🎉'), backgroundColor: LifeHelmColors.success),
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
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Supprimer ?'),
                        content: Text('Supprimer l\'objectif « ${goal.title} » ?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    try {
                      await ref.read(goalsRepositoryProvider).deleteGoal(goal.id);
                      ref.invalidate(goalsProvider);
                      if (context.mounted) {
                        Navigator.pop(ctx);
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
                  child: const Text('Supprimer l\'objectif'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProgressDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter progression'),
        content: LifeHelmTextField(
          controller: ctrl,
          label: 'Incrément${goal.unit != null ? " (${goal.unit})" : ""}',
          hint: '1',
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final inc = num.tryParse(ctrl.text);
              if (inc == null) return;
              try {
                await ref.read(goalsRepositoryProvider).addProgress(goal.id, inc);
                ref.invalidate(goalsProvider);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Progression mise à jour'), backgroundColor: LifeHelmColors.success),
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
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
  final _titleCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  String _domain = 'HEALTH';
  String _type = 'BINARY';
  int _priority = 3;
  DateTime? _deadline;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'NUMERIC' && (double.tryParse(_targetCtrl.text) == null || double.parse(_targetCtrl.text) <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cible numérique requise'), backgroundColor: LifeHelmColors.danger),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(goalsRepositoryProvider).createGoal({
        'title': _titleCtrl.text.trim(),
        'domain': _domain,
        'type': _type,
        'priority': _priority,
        if (_type == 'NUMERIC') 'targetValue': double.parse(_targetCtrl.text),
        if (_deadline != null) 'deadline': _deadline!.toIso8601String(),
      });
      ref.invalidate(goalsProvider);
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
                controller: _titleCtrl,
                label: 'Titre',
                hint: 'Ex: Courir un semi-marathon',
                validator: (v) => (v == null || v.isEmpty) ? 'Titre requis' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _domain,
                decoration: const InputDecoration(labelText: 'Domaine'),
                items: GoalDomains.domainLabels.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Row(
                      children: [
                        Text(GoalDomains.domainEmojis[e.key]!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(e.value),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _domain = v ?? 'HEALTH'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: GoalTypes.typeLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'BINARY'),
              ),
              const SizedBox(height: 16),
              if (_type == 'NUMERIC')
                LifeHelmTextField(
                  controller: _targetCtrl,
                  label: 'Valeur cible',
                  hint: '21',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Requis';
                    if (double.tryParse(v) == null) return 'Invalide';
                    return null;
                  },
                ),
              if (_type == 'NUMERIC') const SizedBox(height: 16),
              // Priority
              Row(
                children: [
                  const Text('Priorité: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _priority.toDouble(),
                      min: 1, max: 5, divisions: 4,
                      label: _priority == 1 ? 'Très haute' : _priority == 5 ? 'Basse' : '$_priority',
                      activeColor: _priority <= 2 ? LifeHelmColors.danger : LifeHelmColors.primary,
                      onChanged: (v) => setState(() => _priority = v.toInt()),
                    ),
                  ),
                ],
              ),
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
                  decoration: const InputDecoration(labelText: 'Échéance (optionnelle)'),
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
