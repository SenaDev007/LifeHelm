import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/health_providers.dart';

class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(healthDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Santé'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(healthDashboardProvider);
              ref.invalidate(sleepProvider);
              ref.invalidate(moodProvider);
              ref.invalidate(workoutsProvider);
              ref.invalidate(hydrationProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(healthDashboardProvider);
          ref.invalidate(sleepProvider);
          ref.invalidate(moodProvider);
          ref.invalidate(workoutsProvider);
          ref.invalidate(hydrationProvider);
        },
        child: dashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 16),
              Text('Erreur: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(healthDashboardProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
          data: (dash) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SleepCard(dashboard: dash),
                const SizedBox(height: 16),
                _MoodCard(),
                const SizedBox(height: 16),
                _WorkoutsCard(dashboard: dash),
                const SizedBox(height: 16),
                _HydrationCard(dashboard: dash),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------- SOMMEIL ----------------
class _SleepCard extends ConsumerWidget {
  const _SleepCard({required this.dashboard});
  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepAsync = ref.watch(sleepProvider);
    final avg = dashboard.avgSleep;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LifeHelmColors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bedtime, color: LifeHelmColors.info),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Sommeil', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (avg >= 7 ? LifeHelmColors.success : LifeHelmColors.warning).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Moy: ${avg.toStringAsFixed(1)}h',
                    style: TextStyle(
                      color: avg >= 7 ? LifeHelmColors.success : LifeHelmColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            sleepAsync.when(
              loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, __) => const Text('—', style: TextStyle(color: LifeHelmColors.textTertiary)),
              data: (logs) {
                if (logs.isEmpty) {
                  return const Text('Aucune nuit enregistrée', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13));
                }
                final recent = logs.take(5).toList().reversed.toList();
                return SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final l = recent[i];
                      final barHeight = (l.hours / 10 * 40).clamp(8.0, 40.0);
                      return Tooltip(
                        message: '${FormatUtils.formatDate(l.date)}: ${l.hours.toStringAsFixed(1)}h',
                        child: Column(
                          children: [
                            Container(
                              width: 16,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: l.hours >= 7 ? LifeHelmColors.success : LifeHelmColors.warning,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${l.date.day}/${l.date.month}',
                              style: const TextStyle(fontSize: 9, color: LifeHelmColors.textTertiary),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            LifeHelmButton(
              label: 'Ajouter une nuit',
              icon: Icons.add,
              variant: LifeHelmButtonVariant.outline,
              onPressed: () => _showAddSleepDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSleepDialog(BuildContext context, WidgetRef ref) {
    final hoursCtrl = TextEditingController(text: '7');
    final quality = ValueNotifier<int>(3);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enregistrer une nuit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LifeHelmTextField(
              controller: hoursCtrl,
              label: 'Heures de sommeil',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Qualité'),
            ValueListenableBuilder<int>(
              valueListenable: quality,
              builder: (_, q, __) => Row(
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    onPressed: () => quality.value = star,
                    icon: Icon(
                      star <= q ? Icons.star : Icons.star_border,
                      color: LifeHelmColors.accent,
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(healthRepositoryProvider).addSleep({
                  'hours': double.tryParse(hoursCtrl.text) ?? 7,
                  'quality': quality.value,
                  'date': DateTime.now().toIso8601String(),
                });
                ref.invalidate(sleepProvider);
                ref.invalidate(healthDashboardProvider);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nuit enregistrée'), backgroundColor: LifeHelmColors.success),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                  );
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

// ---------------- HUMEUR ----------------
class _MoodCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MoodCard> createState() => _MoodCardState();
}

class _MoodCardState extends ConsumerState<_MoodCard> {
  int? _mood;
  double _energy = 5;

  static const _moods = [
    (emoji: '😔', label: 'Très mal', value: 1),
    (emoji: '😕', label: 'Mal', value: 2),
    (emoji: '😐', label: 'Neutre', value: 3),
    (emoji: '🙂', label: 'Bien', value: 4),
    (emoji: '😄', label: 'Très bien', value: 5),
  ];

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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LifeHelmColors.health.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mood, color: LifeHelmColors.health),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Humeur du jour', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _moods.map((m) {
                final selected = _mood == m.value;
                return InkWell(
                  onTap: () => setState(() => _mood = m.value),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected ? LifeHelmColors.health.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? LifeHelmColors.health : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(m.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(m.label, style: TextStyle(
                          fontSize: 10,
                          color: selected ? LifeHelmColors.health : LifeHelmColors.textTertiary,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Énergie: ${_energy.round()}/10', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Slider(
              value: _energy,
              min: 1, max: 10, divisions: 9,
              activeColor: LifeHelmColors.health,
              label: '${_energy.round()}',
              onChanged: (v) => setState(() => _energy = v),
            ),
            const SizedBox(height: 8),
            LifeHelmButton(
              label: 'Enregistrer l\'humeur',
              icon: Icons.check,
              onPressed: _mood == null
                  ? null
                  : () async {
                      try {
                        await ref.read(healthRepositoryProvider).addMood(
                          _mood!,
                          energy: _energy.round(),
                        );
                        ref.invalidate(moodProvider);
                        ref.invalidate(healthDashboardProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Humeur enregistrée'), backgroundColor: LifeHelmColors.success),
                          );
                          setState(() {
                            _mood = null;
                            _energy = 5;
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- ACTIVITÉ ----------------
class _WorkoutsCard extends ConsumerWidget {
  const _WorkoutsCard({required this.dashboard});
  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsAsync = ref.watch(workoutsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LifeHelmColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.fitness_center, color: LifeHelmColors.success),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Activité physique', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LifeHelmColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${dashboard.weekWorkouts} cette semaine',
                    style: const TextStyle(color: LifeHelmColors.success, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            workoutsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const Text('Impossible de charger'),
              data: (logs) {
                if (logs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucune activité récente', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                  );
                }
                return Column(
                  children: logs.take(4).map((w) {
                    final emoji = WorkoutTypes.workoutEmojis[w.type] ?? '🎯';
                    final label = WorkoutTypes.workoutLabels[w.type] ?? w.type;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: LifeHelmColors.success.withValues(alpha: 0.15),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${FormatUtils.formatDate(w.date)} • ${w.durationMin}min'
                        '${w.calories > 0 ? " • ${w.calories}kcal" : ""}',
                        style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            LifeHelmButton(
              label: 'Ajouter une activité',
              icon: Icons.add,
              variant: LifeHelmButtonVariant.outline,
              onPressed: () => _showAddWorkoutDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddWorkoutDialog(BuildContext context, WidgetRef ref) {
    String type = 'WALK';
    final durationCtrl = TextEditingController(text: '30');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nouvelle activité'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: WorkoutTypes.workoutLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text('${WorkoutTypes.workoutEmojis[e.key]} ${e.value}')))
                    .toList(),
                onChanged: (v) => setState(() => type = v ?? 'WALK'),
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: durationCtrl,
                label: 'Durée (minutes)',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(healthRepositoryProvider).addWorkout({
                    'type': type,
                    'durationMin': int.tryParse(durationCtrl.text) ?? 30,
                    'date': DateTime.now().toIso8601String(),
                  });
                  ref.invalidate(workoutsProvider);
                  ref.invalidate(healthDashboardProvider);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Activité enregistrée'), backgroundColor: LifeHelmColors.success),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                    );
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- HYDRATATION ----------------
class _HydrationCard extends ConsumerWidget {
  const _HydrationCard({required this.dashboard});
  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hydrationAsync = ref.watch(hydrationProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.water_drop, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Hydratation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            hydrationAsync.when(
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const Text('Impossible de charger'),
              data: (h) {
                final pct = h.progress;
                final remaining = (h.goalMl - h.todayMl).clamp(0, h.goalMl);
                return Row(
                  children: [
                    // Jauge circulaire
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CustomPaint(
                        painter: _HydrationGauge(progress: pct),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${h.todayMl}ml',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              Text('sur ${h.goalMl}ml', style: const TextStyle(fontSize: 10, color: LifeHelmColors.textTertiary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(pct * 100).toInt()}% de l\'objectif',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pct >= 1 ? LifeHelmColors.success : Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pct >= 1
                                ? 'Bravo, objectif atteint ! 💧'
                                : 'Encore ${remaining}ml à boire',
                            style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ref.read(healthRepositoryProvider).addHydration(250);
                                      ref.invalidate(hydrationProvider);
                                      ref.invalidate(healthDashboardProvider);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Text('+250', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  label: const Text('ml', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ref.read(healthRepositoryProvider).addHydration(500);
                                      ref.invalidate(hydrationProvider);
                                      ref.invalidate(healthDashboardProvider);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Text('+500', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  label: const Text('ml', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HydrationGauge extends CustomPainter {
  _HydrationGauge({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    final bgPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = progress >= 1 ? LifeHelmColors.success : Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final sweep = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HydrationGauge old) => old.progress != progress;
}
