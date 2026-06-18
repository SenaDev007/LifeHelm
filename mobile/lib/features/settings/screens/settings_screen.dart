import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
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
                  onPressed: () => ref.invalidate(settingsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (settings) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              Future<void> saveField(Map<String, dynamic> data) async {
                setState(() => _isSaving = true);
                try {
                  await ref.read(settingsRepositoryProvider).update(data);
                  ref.invalidate(settingsProvider);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              }

              Future<void> pickTime(String current, String label, void Function(String) onPicked) async {
                final parts = current.split(':');
                final init = TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
                final t = await showTimePicker(
                  context: context,
                  initialTime: init,
                  helpText: label,
                );
                if (t != null) {
                  final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                  onPicked(v);
                }
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionTitle(text: 'Notifications'),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Activer les notifications'),
                          subtitle: const Text('Rappels quotidiens et alertes'),
                          value: settings.notificationsEnabled,
                          onChanged: (v) {
                            saveField({'notificationsEnabled': v});
                            ref.invalidate(settingsProvider);
                          },
                          activeColor: LifeHelmColors.success,
                        ),
                        ListTile(
                          leading: const Icon(Icons.alarm),
                          title: const Text('Rappel quotidien'),
                          trailing: Text(settings.dailyReminderTime, style: const TextStyle(fontWeight: FontWeight.w700, color: LifeHelmColors.primary)),
                          onTap: () => pickTime(
                            settings.dailyReminderTime,
                            'Heure du rappel quotidien',
                            (v) => saveField({'dailyReminderTime': v}),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.calendar_today),
                          title: const Text('Jour du rapport hebdo'),
                          trailing: DropdownButton<String>(
                            value: settings.weeklyReportDay,
                            underline: const SizedBox.shrink(),
                            items: WeekDays.dayLabels.entries
                                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) saveField({'weeklyReportDay': v});
                            },
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.alarm_on),
                          title: const Text('Heure du rapport'),
                          trailing: Text(settings.weeklyReportTime, style: const TextStyle(fontWeight: FontWeight.w700, color: LifeHelmColors.primary)),
                          onTap: () => pickTime(
                            settings.weeklyReportTime,
                            'Heure du rapport hebdo',
                            (v) => saveField({'weeklyReportTime': v}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionTitle(text: 'Objectifs de santé'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.bedtime, color: LifeHelmColors.info),
                          title: Text('Sommeil: ${settings.sleepGoalHours.toStringAsFixed(1)}h / nuit'),
                          subtitle: Slider(
                            value: settings.sleepGoalHours,
                            min: 4, max: 12, divisions: 16,
                            label: '${settings.sleepGoalHours.toStringAsFixed(1)}h',
                            activeColor: LifeHelmColors.info,
                            onChanged: (v) {
                              // Mise à jour locale via invalidate puis patch au release
                            },
                            onChangeEnd: (v) => saveField({'sleepGoalHours': v}),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.water_drop, color: Colors.blue),
                          title: Text('Hydratation: ${settings.hydrationGoalMl}ml / jour'),
                          subtitle: Slider(
                            value: settings.hydrationGoalMl.toDouble(),
                            min: 500, max: 5000, divisions: 18,
                            label: '${settings.hydrationGoalMl}ml',
                            activeColor: Colors.blue,
                            onChanged: (v) {},
                            onChangeEnd: (v) => saveField({'hydrationGoalMl': v.toInt()}),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.fitness_center, color: LifeHelmColors.success),
                          title: Text('Activités: ${settings.weeklyWorkoutsGoal} / semaine'),
                          subtitle: Slider(
                            value: settings.weeklyWorkoutsGoal.toDouble(),
                            min: 0, max: 14, divisions: 14,
                            label: '${settings.weeklyWorkoutsGoal}',
                            activeColor: LifeHelmColors.success,
                            onChanged: (v) {},
                            onChangeEnd: (v) => saveField({'weeklyWorkoutsGoal': v.toInt()}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionTitle(text: 'Finance'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.savings, color: LifeHelmColors.finance),
                      title: Text('Taux d\'épargne mensuel: ${settings.monthlySavingsRate}%'),
                      subtitle: Slider(
                        value: settings.monthlySavingsRate.toDouble(),
                        min: 0, max: 80, divisions: 16,
                        label: '${settings.monthlySavingsRate}%',
                        activeColor: LifeHelmColors.finance,
                        onChanged: (v) {},
                        onChangeEnd: (v) => saveField({'monthlySavingsRate': v.toInt()}),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionTitle(text: 'Langue & région'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.language),
                      title: const Text('Langue'),
                      trailing: const Text('Français 🇫🇷', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Autres langues bientôt')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  LifeHelmButton(
                    label: 'Enregistrer',
                    icon: Icons.check,
                    isLoading: _isSaving,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Paramètres sauvegardés automatiquement'), backgroundColor: LifeHelmColors.success),
                      );
                      context.pop();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: LifeHelmColors.textSecondary,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
