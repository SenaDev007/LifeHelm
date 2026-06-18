import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../providers/accessible_providers.dart';

class AccessibleHomeScreen extends ConsumerWidget {
  const AccessibleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(accessibleDashboardProvider);

    return Scaffold(
      backgroundColor: LifeHelmColors.bg,
      appBar: AppBar(
        title: const Text('LifeHelm', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        backgroundColor: LifeHelmColors.bg,
        elevation: 0,
        centerTitle: false,
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(accessibleDashboardProvider),
                icon: const Icon(Icons.refresh, size: 28),
                label: const Text('Réessayer', style: TextStyle(fontSize: 20)),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
              ),
            ],
          ),
          data: (dash) {
            final today = dash.today;
            final todayProfit = today?.netProfit ?? 0;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Solde du jour en gros
                Card(
                  color: todayProfit >= 0 ? LifeHelmColors.accessibleGreen : LifeHelmColors.accessibleRed,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text(
                          'Bénéfice du jour',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          FormatUtils.formatFCFA(todayProfit),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 3 BOUTONS GÉANTS
                _GiantButton(
                  label: 'VENTE',
                  emoji: '💰',
                  color: LifeHelmColors.accessibleGreen,
                  onTap: () => context.push('/accessible/vente'),
                ),
                const SizedBox(height: 16),
                _GiantButton(
                  label: 'DÉPENSE',
                  emoji: '🛒',
                  color: LifeHelmColors.accessibleRed,
                  onTap: () => context.push('/accessible/depense'),
                ),
                const SizedBox(height: 16),
                _GiantButton(
                  label: 'BILAN',
                  emoji: '📊',
                  color: LifeHelmColors.accessibleBlue,
                  onTap: () => context.push('/accessible/bilan'),
                ),
                const SizedBox(height: 32),
                // Semaine
                if (dash.recent.isNotEmpty) ...[
                  const Text(
                    '7 derniers jours',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  ...dash.recent.take(7).map((b) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          title: Text(
                            FormatUtils.formatDate(b.date),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          trailing: Text(
                            FormatUtils.formatFCFA(b.netProfit),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: b.netProfit >= 0 ? LifeHelmColors.accessibleGreen : LifeHelmColors.accessibleRed,
                            ),
                          ),
                        ),
                      )),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GiantButton extends StatelessWidget {
  const _GiantButton({
    required this.label,
    required this.emoji,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
