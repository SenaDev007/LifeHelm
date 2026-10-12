import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../../../theme/theme.dart';

final contactsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authProvider);
  final response = await ref.watch(dioProvider).get('/relationships');
  return (response.data['contacts'] as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
});

const _circles = <String, String>{
  'FAMILY_CLOSE': 'Famille proche', 'FAMILY_EXTENDED': 'Famille élargie', 'FRIEND': 'Ami(e)',
  'COLLEAGUE': 'Collègue', 'MENTOR': 'Mentor', 'NETWORK': 'Réseau',
};

class RelationshipsScreen extends ConsumerWidget {
  const RelationshipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Relations importantes'), actions: [IconButton(onPressed: () => _showAddContact(context, ref), icon: const Icon(Icons.person_add_alt_1), tooltip: 'Ajouter une personne')]),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Impossible de charger les contacts : $error'), TextButton(onPressed: () => ref.invalidate(contactsProvider), child: const Text('Réessayer'))])),
        data: (contacts) {
          if (contacts.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.people_outline, size: 64, color: LifeHelmColors.relations),
            const SizedBox(height: 12), const Text('Commence par ajouter les personnes qui comptent.', textAlign: TextAlign.center),
            const SizedBox(height: 16), FilledButton.icon(onPressed: () => _showAddContact(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter une personne')),
          ])));
          final birthdays = contacts.where((person) => person['daysUntilBirthday'] is num && (person['daysUntilBirthday'] as num) <= 7).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (birthdays.isNotEmpty) Card(color: LifeHelmColors.relations.withValues(alpha: .12), child: Padding(padding: const EdgeInsets.all(16), child: Text('Anniversaire bientôt : ${birthdays.map((p) => '${p['firstName']} (${p['daysUntilBirthday'] == 0 ? 'aujourd’hui' : 'dans ${p['daysUntilBirthday']} j'})').join(', ')}'))),
            Row(children: [Expanded(child: _CountCard(label: 'Personnes', value: '${contacts.length}')), const SizedBox(width: 8), Expanded(child: _CountCard(label: 'Contactées ce mois', value: '${contacts.where((p) => _recent(p['lastContactAt'])).length}'))]),
            const SizedBox(height: 12),
            ...contacts.map((person) => _ContactCard(person: person)),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showAddContact(context, ref), icon: const Icon(Icons.person_add), label: const Text('Ajouter')),
    );
  }

  static bool _recent(dynamic raw) {
    if (raw is! String) return false;
    final date = DateTime.tryParse(raw);
    return date != null && DateTime.now().difference(date).inDays < 30;
  }

  static Future<void> _showAddContact(BuildContext context, WidgetRef ref) async {
    final first = TextEditingController(); final last = TextEditingController(); final phone = TextEditingController(); final city = TextEditingController(); final birthday = TextEditingController();
    var circle = 'FAMILY_CLOSE';
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: const Text('Ajouter une personne'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: first, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Prénom *')),
        TextField(controller: last, decoration: const InputDecoration(labelText: 'Nom')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
        TextField(controller: city, decoration: const InputDecoration(labelText: 'Ville')),
        TextField(controller: birthday, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Anniversaire (AAAA-MM-JJ)')),
        DropdownButtonFormField<String>(value: circle, decoration: const InputDecoration(labelText: 'Cercle'), items: _circles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => circle = v ?? circle)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')), FilledButton(onPressed: first.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer'))],
    )));
    if (saved == true) {
      try {
        await ref.read(dioProvider).post('/relationships', data: {
          'firstName': first.text.trim(), 'lastName': last.text.trim().isEmpty ? null : last.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(), 'city': city.text.trim().isEmpty ? null : city.text.trim(),
          'circle': circle, 'birthday': birthday.text.trim().isEmpty ? null : birthday.text.trim(),
        });
        ref.invalidate(contactsProvider);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact ajouté')));
      } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $error'))); }
    }
    for (final controller in [first, last, phone, city, birthday]) { controller.dispose(); }
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: LifeHelmColors.relations)), Text(label, style: const TextStyle(fontSize: 11, color: LifeHelmColors.textSecondary))])));
}

class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.person});
  final Map<String, dynamic> person;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = '${person['firstName'] ?? ''} ${person['lastName'] ?? ''}'.trim();
    final days = person['daysUntilBirthday'] as num?;
    return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
      leading: CircleAvatar(backgroundColor: LifeHelmColors.relations.withValues(alpha: .15), child: Text((person['firstName'] as String? ?? '?').substring(0, 1).toUpperCase(), style: const TextStyle(color: LifeHelmColors.relations, fontWeight: FontWeight.bold))),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${_circles[person['circle']] ?? 'Relation'}${person['city'] == null ? '' : ' • ${person['city']}'}${days == null ? '' : '\n${days == 0 ? 'Anniversaire aujourd’hui' : 'Anniversaire dans ${days.toInt()} jour(s)'}'}'),
      isThreeLine: days != null,
      trailing: IconButton(tooltip: 'Noter une prise de contact aujourd’hui', icon: const Icon(Icons.call_outlined, color: LifeHelmColors.relations), onPressed: () async {
        try {
          await ref.read(dioProvider).patch('/relationships/${person['id']}', data: {'lastContactAt': DateTime.now().toIso8601String()});
          ref.invalidate(contactsProvider);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prise de contact avec $name enregistrée')));
        } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $error'))); }
      }),
    ));
  }
}
