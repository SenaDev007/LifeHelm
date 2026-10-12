import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';

final careerDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authProvider);
  final response = await ref.watch(dioProvider).get('/career');
  return Map<String, dynamic>.from(response.data as Map);
});

class CareerScreen extends ConsumerStatefulWidget {
  const CareerScreen({super.key});
  @override
  ConsumerState<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends ConsumerState<CareerScreen> {
  final _job = TextEditingController();
  final _company = TextEditingController();
  final _sector = TextEditingController();
  final _skills = TextEditingController();
  final _goal = TextEditingController();
  String _type = 'EMPLOYEE';
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _job.dispose(); _company.dispose(); _sector.dispose(); _skills.dispose(); _goal.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> data) {
    if (_loaded) return;
    final profile = data['profile'] as Map<String, dynamic>? ?? {};
    _job.text = profile['jobTitle'] as String? ?? '';
    _company.text = profile['company'] as String? ?? '';
    _sector.text = profile['sector'] as String? ?? '';
    _type = profile['employmentType'] as String? ?? 'EMPLOYEE';
    final skills = profile['skills'] as List? ?? [];
    _skills.text = skills.map((skill) => skill is Map ? skill['name'] : skill).whereType<String>().join(', ');
    _goal.text = (data['annualRevenueGoal'] ?? profile['annualRevenueGoal'] ?? '').toString();
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).patch('/career', data: {
        'jobTitle': _job.text.trim().isEmpty ? null : _job.text.trim(),
        'company': _company.text.trim().isEmpty ? null : _company.text.trim(),
        'sector': _sector.text.trim().isEmpty ? null : _sector.text.trim(),
        'employmentType': _type,
        'skills': _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).map((name) => {'name': name, 'level': 1}).toList(),
        'annualRevenueGoal': num.tryParse(_goal.text.replaceAll(' ', '')),
      });
      ref.invalidate(careerDashboardProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil carrière enregistré')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careerDashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Carrière & revenus')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Impossible de charger le profil : $error'), TextButton(onPressed: () => ref.invalidate(careerDashboardProvider), child: const Text('Réessayer'))])),
        data: (data) {
          _hydrate(data);
          final earned = data['earnedThisYear'] as num? ?? 0;
          final target = data['annualRevenueGoal'] as num? ?? 0;
          final progress = target > 0 ? (earned / target).clamp(0.0, 1.0).toDouble() : 0.0;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(color: LifeHelmColors.career, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Revenus suivis cette année', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(FormatUtils.formatFCFA(earned), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              if (target > 0) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(value: progress, backgroundColor: Colors.white30, color: Colors.white),
                const SizedBox(height: 5),
                Text('${(progress * 100).round()} % de l’objectif annuel', style: const TextStyle(color: Colors.white)),
              ] else const Text('Ajoute un objectif annuel ci-dessous pour suivre ta progression.', style: TextStyle(color: Colors.white)),
            ]))),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mon profil professionnel', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: _job, decoration: const InputDecoration(labelText: 'Poste / activité', hintText: 'Ex. Consultante, commerçant…')),
              TextField(controller: _company, decoration: const InputDecoration(labelText: 'Entreprise (facultatif)')),
              TextField(controller: _sector, decoration: const InputDecoration(labelText: 'Secteur')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'Situation'), items: const [
                DropdownMenuItem(value: 'EMPLOYEE', child: Text('Salarié(e)')),
                DropdownMenuItem(value: 'FREELANCE', child: Text('Freelance')),
                DropdownMenuItem(value: 'ENTREPRENEUR', child: Text('Entrepreneur(e)')),
                DropdownMenuItem(value: 'STUDENT', child: Text('Étudiant(e)')),
                DropdownMenuItem(value: 'OTHER', child: Text('Autre')),
              ], onChanged: (value) => setState(() => _type = value ?? 'EMPLOYEE')),
              TextField(controller: _skills, decoration: const InputDecoration(labelText: 'Compétences', hintText: 'Sépare-les par des virgules')),
              TextField(controller: _goal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Objectif de revenus annuel (FCFA)')),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Enregistrement…' : 'Enregistrer mon profil')),
            ]))),
            const SizedBox(height: 12),
            const Text('Les revenus sont calculés à partir des transactions de type « revenu » saisies dans le module Finance.', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
