import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../providers/accessible_providers.dart';

class AccessibleBilanScreen extends ConsumerWidget {
  const AccessibleBilanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(accessibleDashboardProvider);

    return Scaffold(
      backgroundColor: LifeHelmColors.bg,
      appBar: AppBar(
        title: const Text('📊 BILAN DU JOUR', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32),
          onPressed: () => context.go('/accessible'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accessibleDashboardProvider),
        child: dashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 3)),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.cloud_off, size: 80, color: LifeHelmColors.textTertiary),
              const SizedBox(height: 16),
              Text('Erreur: $e', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            ],
          ),
          data: (dash) {
            final t = dash.today;
            final openingCapital = t?.openingCapital ?? 0;
            final totalSales = t?.totalSales ?? 0;
            final restockCost = t?.restockCost ?? 0;
            final netProfit = t?.netProfit ?? 0;
            final netColor = netProfit >= 0 ? LifeHelmColors.accessibleGreen : LifeHelmColors.accessibleRed;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // En-tête date
                Center(
                  child: Text(
                    t != null ? FormatUtils.formatDate(t.date) : FormatUtils.formatDate(DateTime.now()),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: LifeHelmColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 24),
                // 4 cards géantes
                _BigStat(
                  label: 'MISE DU MATIN',
                  value: FormatUtils.formatFCFA(openingCapital),
                  color: LifeHelmColors.accessibleBlue,
                  emoji: '🏦',
                ),
                const SizedBox(height: 16),
                _BigStat(
                  label: 'RECETTES (VENTES)',
                  value: FormatUtils.formatFCFA(totalSales),
                  color: LifeHelmColors.accessibleGreen,
                  emoji: '💰',
                ),
                const SizedBox(height: 16),
                _BigStat(
                  label: 'RÉAPPROVISIONNEMENT',
                  value: FormatUtils.formatFCFA(restockCost),
                  color: LifeHelmColors.accessibleRed,
                  emoji: '🛒',
                ),
                const SizedBox(height: 24),
                // Bénéfice net mis en avant
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: netColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'BÉNÉFICE NET',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        FormatUtils.formatFCFA(netProfit),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // 7 derniers jours
                const Text(
                  '7 derniers jours',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (dash.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Aucun historique', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 18)),
                    ),
                  )
                else
                  ...dash.recent.take(7).map((b) {
                    final c = b.netProfit >= 0 ? LifeHelmColors.accessibleGreen : LifeHelmColors.accessibleRed;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Text(
                          FormatUtils.formatDate(b.date),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        trailing: Text(
                          FormatUtils.formatFCFA(b.netProfit),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: c,
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                // Bouton retour
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: OutlinedButton(
                    onPressed: () => context.go('/accessible'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LifeHelmColors.primary,
                      side: const BorderSide(color: LifeHelmColors.primary, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('← RETOUR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.value,
    required this.color,
    required this.emoji,
  });

  final String label;
  final String value;
  final Color color;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
