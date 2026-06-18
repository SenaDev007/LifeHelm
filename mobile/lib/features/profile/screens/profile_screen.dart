import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/api_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../finance/providers/finance_providers.dart';
import '../../settings/providers/settings_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final dashAsync = ref.watch(homeDashboardProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final firstName = user?['firstName'] as String? ?? 'Utilisateur';
    final lastName = user?['lastName'] as String? ?? '';
    final email = user?['email'] as String? ?? '';
    final plan = user?['plan'] as String? ?? 'FREE';
    final createdAt = user?['createdAt'] != null
        ? DateTime.tryParse(user!['createdAt'] as String)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'Paramètres',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeDashboardProvider);
          ref.invalidate(settingsProvider);
          await ref.read(authProvider.notifier).refreshUser();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Avatar + nom + email
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: LifeHelmColors.primary,
                      child: Text(
                        '${firstName.isNotEmpty ? firstName[0] : '?'}${lastName.isNotEmpty ? lastName[0] : ''}',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$firstName $lastName'.trim(),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(email, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 8),
                          _PlanBadge(plan: plan),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats
            dashAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (dash) {
                final d = dash;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Statistiques', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 12),
                        if (createdAt != null)
                          _StatRow(
                            icon: Icons.calendar_today,
                            label: 'Membre depuis',
                            value: FormatUtils.formatDate(createdAt),
                          ),
                        _StatRow(
                          icon: Icons.account_balance,
                          label: 'Comptes',
                          value: '${d.financial.accountsCount}',
                        ),
                        _StatRow(
                          icon: Icons.trending_up,
                          label: 'Score global',
                          value: '${d.globalScore}/100',
                        ),
                        _StatRow(
                          icon: Icons.today,
                          label: 'Habitudes (semaine)',
                          value: '${d.habits.doneThisWeek}',
                        ),
                        _StatRow(
                          icon: Icons.fitness_center,
                          label: 'Activités (semaine)',
                          value: '${d.health.weekWorkouts}',
                        ),
                        _StatRow(
                          icon: Icons.savings,
                          label: 'Taux d\'épargne',
                          value: '${d.financial.savingsRate}%',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Menu
            _MenuTile(
              icon: Icons.edit,
              label: 'Modifier le profil',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bientôt disponible')),
                );
              },
            ),
            _MenuTile(
              icon: Icons.settings,
              label: 'Paramètres',
              onTap: () => context.push('/settings'),
            ),
            // Mode accessible toggle
            settingsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (s) => _ToggleTile(
                icon: Icons.accessibility_new,
                label: 'Mode Accessible',
                subtitle: 'Interface simplifiée pour boutiques',
                value: s.appMode == 'ACCESSIBLE',
                onChanged: (v) async {
                  try {
                    final newMode = v ? 'ACCESSIBLE' : 'STANDARD';
                    await ref.read(settingsRepositoryProvider).update({'appMode': newMode});
                    ref.invalidate(settingsProvider);
                    await ref.read(authProvider.notifier).refreshUser();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v ? 'Mode Accessible activé' : 'Mode standard activé'),
                          backgroundColor: LifeHelmColors.success,
                        ),
                      );
                      if (v) {
                        context.go('/accessible');
                      }
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
            _MenuTile(
              icon: Icons.language,
              label: 'Langue',
              trailing: const Text('Français', style: TextStyle(color: LifeHelmColors.textSecondary)),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Autres langues bientôt disponibles')),
                );
              },
            ),
            _MenuTile(
              icon: Icons.help_outline,
              label: 'Aide & support',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact: support@lifehelm.app')),
                );
              },
            ),
            const SizedBox(height: 16),

            // Déconnexion
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: LifeHelmColors.danger),
                title: const Text('Déconnexion', style: TextStyle(color: LifeHelmColors.danger, fontWeight: FontWeight.w700)),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Déconnexion'),
                      content: const Text('Tu veux te déconnecter ?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                          child: const Text('Déconnexion'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  await ref.read(authProvider.notifier).logout();
                },
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'LifeHelm v1.0.0',
                style: TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.plan});
  final String plan;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (plan) {
      case 'PRO':
        color = LifeHelmColors.accent;
        label = 'PRO';
        break;
      case 'FAMILY':
        color = LifeHelmColors.goals;
        label = 'FAMILY';
        break;
      default:
        color = LifeHelmColors.textTertiary;
        label = 'FREE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: LifeHelmColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 14)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: LifeHelmColors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: LifeHelmColors.textTertiary),
        onTap: onTap,
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(icon, color: LifeHelmColors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary)),
        value: value,
        onChanged: onChanged,
        activeColor: LifeHelmColors.success,
      ),
    );
  }
}
