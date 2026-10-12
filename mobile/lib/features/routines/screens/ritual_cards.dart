import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../providers/routines_providers.dart';

class MorningRitualCard extends ConsumerWidget {
  const MorningRitualCard({super.key});
  static const _defaults = <(String, String)>[
    ('prayer', 'Prière ou méditation'),
    ('water', 'Boire un verre d’eau'),
    ('movement', 'Bouger 10 minutes'),
    ('plan', 'Choisir mes 3 priorités'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ritual = ref.watch(morningRitualProvider);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF3FF), child: Icon(Icons.wb_sunny_outlined, color: LifeHelmColors.routines)),
        title: const Text('Rituel du matin', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: ritual.when(
          loading: () => const Text('Prépare un démarrage intentionnel'),
          error: (_, __) => const Text('Prépare un démarrage intentionnel'),
          data: (value) => Text(value.total == 0 ? '4 petites étapes pour lancer ta journée' : '${value.completed}/${value.total} étapes faites aujourd’hui'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ref),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final saved = ref.read(morningRitualProvider).valueOrNull;
    final initial = _defaults.map((item) {
      for (final old in saved?.steps ?? const <RitualStep>[]) {
        if (old.id == item.$1) return old.done;
      }
      return false;
    }).toList();
    final result = await showDialog<List<bool>>(
      context: context,
      builder: (dialogContext) {
        var checked = List<bool>.from(initial);
        return StatefulBuilder(builder: (context, setState) => AlertDialog(
          title: const Text('Mon rituel du matin'),
          content: Column(mainAxisSize: MainAxisSize.min, children: List.generate(_defaults.length, (index) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: checked[index],
            title: Text(_defaults[index].$2),
            onChanged: (value) => setState(() => checked[index] = value ?? false),
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, checked), child: const Text('Enregistrer')),
          ],
        ));
      },
    );
    if (result == null) return;
    final steps = List.generate(_defaults.length, (index) => RitualStep(
      id: _defaults[index].$1,
      label: _defaults[index].$2,
      done: result[index],
    ));
    try {
      await ref.read(routinesRepositoryProvider).saveMorningRitual(steps);
      ref.invalidate(morningRitualProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rituel du matin enregistré')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible d’enregistrer le rituel : $error')));
    }
  }
}

class EveningReviewCard extends ConsumerWidget {
  const EveningReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(eveningReviewProvider);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFF3E5), child: Icon(Icons.nightlight_outlined, color: LifeHelmColors.accent)),
        title: const Text('Revue de soirée', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: review.when(
          loading: () => const Text('Note tes victoires et prépare demain'),
          error: (_, __) => const Text('Note tes victoires et prépare demain'),
          data: (value) => Text(value.gratitude.isEmpty ? '3 gratitudes, une réflexion, les priorités de demain' : '${value.gratitude.length} gratitude(s) notée(s) aujourd’hui'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ref),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final gratitude = List.generate(3, (i) => TextEditingController(
      text: (ref.read(eveningReviewProvider).valueOrNull?.gratitude ?? const <String>[]).length > i
          ? ref.read(eveningReviewProvider).valueOrNull!.gratitude[i]
          : '',
    ));
    final reflection = TextEditingController(text: ref.read(eveningReviewProvider).valueOrNull?.reflection ?? '');
    final priorities = List.generate(3, (i) => TextEditingController());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ma revue de soirée'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < gratitude.length; i++) ...[
            TextField(controller: gratitude[i], decoration: InputDecoration(labelText: 'Gratitude ${i + 1}')),
            const SizedBox(height: 8),
          ],
          TextField(controller: reflection, maxLines: 2, decoration: const InputDecoration(labelText: 'Comment s’est passée ta journée ?')),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('Mes priorités pour demain', style: TextStyle(fontWeight: FontWeight.w600))),
          for (var i = 0; i < priorities.length; i++) TextField(controller: priorities[i], decoration: InputDecoration(labelText: 'Priorité ${i + 1}')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (saved == true) {
      final gratitudeItems = gratitude.map((controller) => controller.text.trim()).where((item) => item.isNotEmpty).toList();
      if (gratitudeItems.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note au moins une chose positive de ta journée.')));
      } else {
       try {
        await ref.read(routinesRepositoryProvider).saveEveningReview(
          gratitude: gratitudeItems,
          reflection: reflection.text.trim().isEmpty ? null : reflection.text.trim(),
          topPriorities: priorities.map((controller) => controller.text.trim()).toList(),
        );
        ref.invalidate(eveningReviewProvider);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revue de soirée enregistrée')));
       } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible d’enregistrer la revue : $error')));
       }
      }
    }
    for (final controller in gratitude) { controller.dispose(); }
    for (final controller in priorities) { controller.dispose(); }
    reflection.dispose();
  }
}
