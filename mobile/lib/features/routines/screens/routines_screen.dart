import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/routines_providers.dart';

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes habitudes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Nouvelle habitude',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(habitsProvider),
        child: habitsAsync.when(
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
                    onPressed: () => ref.invalidate(habitsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (habits) {
            if (habits.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.today, size: 64, color: LifeHelmColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text('Aucune habitude', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Créer une habitude'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final doneToday = habits.where((h) => h.completedToday).length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: LifeHelmColors.routines,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Aujourd\'hui', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                '$doneToday/${habits.length} habitudes',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: habits.isEmpty ? 0 : doneToday / habits.length,
                                  backgroundColor: Colors.white24,
                                  color: Colors.white,
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle, color: Colors.white, size: 48),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...habits.map((h) => _HabitCard(habit: h)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.routines,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddHabitDialog());
  }
}

class _HabitCard extends ConsumerWidget {
  const _HabitCard({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    color: LifeHelmColors.routines.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(habit.icon, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      if (habit.description != null)
                        Text(habit.description!, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                // Toggle today
                InkWell(
                  onTap: () async {
                    try {
                      await ref.read(routinesRepositoryProvider).logHabit(
                        habit.id,
                        date: DateTime.now(),
                        done: !habit.completedToday,
                      );
                      ref.invalidate(habitsProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: habit.completedToday ? LifeHelmColors.success : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: habit.completedToday ? LifeHelmColors.success : LifeHelmColors.textTertiary,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      habit.completedToday ? Icons.check : Icons.check_box_outline_blank,
                      color: habit.completedToday ? Colors.white : LifeHelmColors.textTertiary,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Streak
            Row(
              children: [
                Icon(Icons.local_fire_department, color: habit.streak > 0 ? LifeHelmColors.accent : LifeHelmColors.textTertiary, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${habit.streak} jour(s)',
                  style: TextStyle(
                    color: habit.streak > 0 ? LifeHelmColors.accent : LifeHelmColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.emoji_events, color: LifeHelmColors.textTertiary, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Record: ${habit.bestStreak}',
                  style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Heatmap (30 derniers jours) — simulée à partir de lastSevenDays répétés
            _Heatmap(habit: habit),
          ],
        ),
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    // Génère 30 cases en se basant sur lastSevenDays (si dispo) sinon faux data
    final List<bool> days = List.generate(30, (i) {
      if (habit.lastSevenDays.isEmpty) return false;
      // On réplique la dernière semaine sur 4 semaines (approximation UI)
      return habit.lastSevenDays[i % habit.lastSevenDays.length];
    });
    // Marque aujourd'hui comme complété si completedToday
    if (habit.completedToday) days[29] = true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('30 derniers jours', style: TextStyle(fontSize: 11, color: LifeHelmColors.textTertiary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: List.generate(30, (i) {
            final done = days[i];
            final isToday = i == 29;
            return Tooltip(
              message: isToday ? 'Aujourd\'hui' : 'Jour ${i + 1}',
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: done
                      ? LifeHelmColors.routines
                      : LifeHelmColors.routines.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: isToday ? Border.all(color: LifeHelmColors.primary, width: 2) : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _AddHabitDialog extends ConsumerStatefulWidget {
  const _AddHabitDialog();

  @override
  ConsumerState<_AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends ConsumerState<_AddHabitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _icon = '✅';
  String _frequency = 'DAILY';
  bool _isLoading = false;

  static const _iconChoices = ['✅', '💧', '🏃', '📚', '🧘', '💊', '🥗', '😴', '🙏', '✍️', '🎯', '💪'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(routinesRepositoryProvider).createHabit({
        'name': _nameCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        'icon': _icon,
        'frequency': _frequency,
      });
      ref.invalidate(habitsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habitude créée'), backgroundColor: LifeHelmColors.success),
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
      title: const Text('Nouvelle habitude'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LifeHelmTextField(
                controller: _nameCtrl,
                label: 'Nom de l\'habitude',
                hint: 'Ex: Boire 1L d\'eau, Lire 10 pages...',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _descCtrl,
                label: 'Description (optionnelle)',
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Text('Icône'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _iconChoices.map((emoji) {
                  final selected = _icon == emoji;
                  return InkWell(
                    onTap: () => setState(() => _icon = emoji),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected ? LifeHelmColors.routines.withValues(alpha: 0.15) : Colors.white,
                        border: Border.all(color: selected ? LifeHelmColors.routines : LifeHelmColors.textTertiary, width: selected ? 2 : 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _frequency,
                decoration: const InputDecoration(labelText: 'Fréquence'),
                items: const [
                  DropdownMenuItem(value: 'DAILY', child: Text('Quotidienne')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Hebdomadaire')),
                ],
                onChanged: (v) => setState(() => _frequency = v ?? 'DAILY'),
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
