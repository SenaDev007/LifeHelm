import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/family_providers.dart' as fam;

class FamilyListScreen extends ConsumerWidget {
  const FamilyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familiesAsync = ref.watch(fam.familiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mode Famille'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Rejoindre',
            onPressed: () => context.push('/family/join'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(fam.familiesProvider),
        child: familiesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 16),
              Text('Erreur: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(fam.familiesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
          data: (families) {
            if (families.isEmpty) {
              return _EmptyState(
                onCreate: () => context.push('/family/create'),
                onJoin: () => context.push('/family/join'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: families.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final f = families[i];
                return _FamilyCard(
                  family: f,
                  onTap: () => context.push('/family/${f.id}'),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/family/create'),
        backgroundColor: LifeHelmColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Créer'),
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family, required this.onTap});
  final fam.Family family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: LifeHelmColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.family_restroom, color: LifeHelmColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            family.name,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        if (family.isAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: LifeHelmColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                color: LifeHelmColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 14, color: LifeHelmColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${family.membersCount} membre(s)',
                          style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    if (family.inviteCode.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: family.inviteCode));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code d\'invitation copié'),
                                backgroundColor: LifeHelmColors.success,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: LifeHelmColors.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: LifeHelmColors.textTertiary.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy, size: 12, color: LifeHelmColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                family.inviteCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: LifeHelmColors.primary,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: LifeHelmColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onJoin});
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: LifeHelmColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.family_restroom, color: LifeHelmColors.primary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune famille pour le moment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crée une famille pour partager budget, objectifs et avancées avec tes proches, ou rejoins-en une avec un code d\'invitation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            LifeHelmButton(
              label: 'Créer une famille',
              icon: Icons.add,
              onPressed: onCreate,
            ),
            const SizedBox(height: 8),
            LifeHelmButton(
              label: 'Rejoindre avec un code',
              icon: Icons.group_add,
              variant: LifeHelmButtonVariant.outline,
              onPressed: onJoin,
            ),
          ],
        ),
      ),
    );
  }
}
