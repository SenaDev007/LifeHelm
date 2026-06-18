import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/api_service.dart';
import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.accessible = false});

  final bool accessible;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  String? _selectedMode;
  String? _selectedLang;
  final List<String> _selectedPillars = [];
  final _morningCapitalCtrl = TextEditingController();

  @override
  void dispose() {
    _morningCapitalCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final dio = ref.read(dioProvider);
    try {
      await dio.patch('/profile', data: {
        'onboarded': true,
        if (_selectedMode != null) 'appMode': _selectedMode,
        if (_selectedLang != null) 'language': _selectedLang,
      });
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) {
        if (_selectedMode == 'ACCESSIBLE') {
          context.go('/accessible-onboarding');
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.accessible ? _accessibleSteps() : _standardSteps();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accessible ? 'Bienvenue' : 'Configuration'),
        leading: _step > 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step--)) : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / steps.length,
              backgroundColor: LifeHelmColors.primary.withValues(alpha: 0.15),
              color: LifeHelmColors.primary,
              minHeight: 4,
            ),
            Expanded(child: steps[_step]),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('Précédent'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    child: LifeHelmButton(
                      label: _step == steps.length - 1 ? 'Terminer' : 'Continuer',
                      onPressed: () {
                        if (_step == steps.length - 1) {
                          _finish();
                        } else {
                          setState(() => _step++);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _standardSteps() {
    return [
      // Step 1 : Welcome
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: LifeHelmColors.primary, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.explore, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Bienvenue dans LifeHelm',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'LifeHelm est ton système d\'exploitation de vie. Tu vas configurer ton profil en quelques étapes, et l\'app s\'adaptera à tes besoins.',
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _InfoCard(icon: Icons.account_balance_wallet, title: '6 piliers de vie', desc: 'Finance, Objectifs, Routines, Santé, Carrière, Relations'),
            _InfoCard(icon: Icons.offline_bolt, title: 'Offline-first', desc: 'Fonctionne 100% sans internet'),
            _InfoCard(icon: Icons.auto_awesome, title: 'HELM AI', desc: 'Ton conseiller de vie holistique'),
          ],
        ),
      ),
      // Step 2 : Choix du mode
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quel mode te correspond ?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Tu pourras changer plus tard dans les paramètres.', style: TextStyle(color: LifeHelmColors.textSecondary)),
            const SizedBox(height: 24),
            _ModeCard(
              icon: Icons.dashboard_outlined,
              title: 'Mode Standard',
              desc: 'Interface complète avec tous les modules. Idéal pour les salariés, freelances et entrepreneurs.',
              selected: _selectedMode == 'STANDARD',
              onTap: () => setState(() => _selectedMode = 'STANDARD'),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.store_outlined,
              title: 'Mode Accessible',
              desc: 'Interface simplifiée avec gros boutons. Idéal pour les vendeurs et vendeuses de l\'économie informelle.',
              selected: _selectedMode == 'ACCESSIBLE',
              onTap: () => setState(() => _selectedMode = 'ACCESSIBLE'),
            ),
          ],
        ),
      ),
      // Step 3 : Langue
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ta langue', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Choisis la langue principale de l\'app.', style: TextStyle(color: LifeHelmColors.textSecondary)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _LangChip(code: 'FR', name: 'Français', flag: '🇫🇷', selected: _selectedLang == 'FR', onTap: () => setState(() => _selectedLang = 'FR')),
                _LangChip(code: 'FON', name: 'Fon (Fongbé)', flag: '🇧🇯', selected: _selectedLang == 'FON', onTap: () => setState(() => _selectedLang = 'FON')),
                _LangChip(code: 'BARIBA', name: 'Bariba', flag: '🇧🇯', selected: _selectedLang == 'BARIBA', onTap: () => setState(() => _selectedLang = 'BARIBA')),
                _LangChip(code: 'YORUBA', name: 'Yoruba', flag: '🇳🇬', selected: _selectedLang == 'YORUBA', onTap: () => setState(() => _selectedLang = 'YORUBA')),
              ],
            ),
          ],
        ),
      ),
      // Step 4 : Piliers prioritaires
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quels piliers te tiennent à cœur ?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Sélectionne 1 à 3 priorités (tu pourras en ajouter d\'autres).', style: TextStyle(color: LifeHelmColors.textSecondary)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _PillarCheckbox(label: 'Finance', color: LifeHelmColors.finance, icon: Icons.account_balance_wallet, selected: _selectedPillars.contains('FINANCE'), onTap: () => _togglePillar('FINANCE')),
                  _PillarCheckbox(label: 'Objectifs', color: LifeHelmColors.goals, icon: Icons.flag, selected: _selectedPillars.contains('GOALS'), onTap: () => _togglePillar('GOALS')),
                  _PillarCheckbox(label: 'Routines', color: LifeHelmColors.routines, icon: Icons.today, selected: _selectedPillars.contains('ROUTINES'), onTap: () => _togglePillar('ROUTINES')),
                  _PillarCheckbox(label: 'Santé', color: LifeHelmColors.health, icon: Icons.favorite, selected: _selectedPillars.contains('HEALTH'), onTap: () => _togglePillar('HEALTH')),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  void _togglePillar(String pillar) {
    setState(() {
      if (_selectedPillars.contains(pillar)) {
        _selectedPillars.remove(pillar);
      } else if (_selectedPillars.length < 3) {
        _selectedPillars.add(pillar);
      }
    });
  }

  List<Widget> _accessibleSteps() {
    return [
      // Step 1 : Mise du matin
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.store, size: 64, color: LifeHelmColors.accent),
            const SizedBox(height: 16),
            Text('Combien tu as pris ce matin ?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Ta mise du matin = le capital que tu as pour démarrer la journée.', style: TextStyle(color: LifeHelmColors.textSecondary)),
            const SizedBox(height: 24),
            TextField(
              controller: _morningCapitalCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: '0 FCFA',
                prefixText: 'FCFA ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: LifeHelmColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: LifeHelmColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.desc, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? LifeHelmColors.primary.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(color: selected ? LifeHelmColors.primary : LifeHelmColors.textTertiary, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (selected ? LifeHelmColors.primary : LifeHelmColors.textTertiary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: selected ? LifeHelmColors.primary : LifeHelmColors.textSecondary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(desc, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: LifeHelmColors.primary),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.code, required this.name, required this.flag, required this.selected, required this.onTap});
  final String code;
  final String name;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? LifeHelmColors.primary : Colors.white,
          border: Border.all(color: selected ? LifeHelmColors.primary : LifeHelmColors.textTertiary),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(name, style: TextStyle(color: selected ? Colors.white : LifeHelmColors.textPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PillarCheckbox extends StatelessWidget {
  const _PillarCheckbox({required this.label, required this.color, required this.icon, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(color: selected ? color : LifeHelmColors.textTertiary, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? color : LifeHelmColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
