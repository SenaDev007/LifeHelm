import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../providers/accessible_providers.dart';

class AccessibleVenteScreen extends ConsumerStatefulWidget {
  const AccessibleVenteScreen({super.key});

  @override
  ConsumerState<AccessibleVenteScreen> createState() => _AccessibleVenteScreenState();
}

class _AccessibleVenteScreenState extends ConsumerState<AccessibleVenteScreen> {
  final _amountCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  num get _amount => num.tryParse(_amountCtrl.text) ?? 0;

  Future<void> _save() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entre un montant'),
          backgroundColor: LifeHelmColors.accessibleRed,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(accessibleRepositoryProvider);
      final dash = await ref.read(accessibleDashboardProvider.future);
      final today = dash.today;

      final openingCapital = today?.openingCapital ?? 0;
      final restockCost = today?.restockCost ?? 0;
      final totalSales = _amount;
      final netProfit = totalSales - restockCost - openingCapital;

      if (today != null) {
        await repo.updateBoutiqueLog(today.id, {
          'openingCapital': openingCapital,
          'restockCost': restockCost,
          'totalSales': totalSales,
          'netProfit': netProfit,
        });
      } else {
        await repo.createBoutiqueLog({
          'date': DateTime.now().toIso8601String(),
          'openingCapital': openingCapital,
          'restockCost': restockCost,
          'totalSales': totalSales,
          'netProfit': netProfit,
        });
      }
      ref.invalidate(accessibleDashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vente de ${FormatUtils.formatFCFA(_amount)} enregistrée'),
            backgroundColor: LifeHelmColors.accessibleGreen,
            duration: const Duration(seconds: 2),
          ),
        );
        context.go('/accessible');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.accessibleRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LifeHelmColors.bg,
      appBar: AppBar(
        title: const Text('💰 VENTE', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32),
          onPressed: () => context.go('/accessible'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Combien as-tu vendu aujourd\'hui ?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Champ montant géant
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: LifeHelmColors.accessibleGreen),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: LifeHelmColors.textTertiary),
                  suffixText: 'FCFA',
                  suffixStyle: const TextStyle(fontSize: 24, color: LifeHelmColors.textSecondary, fontWeight: FontWeight.w600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleGreen, width: 3),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleGreen, width: 3),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleGreen, width: 4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              // Calcul bénéfice
              if (_amount > 0)
                Card(
                  color: LifeHelmColors.accessibleGreen.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'Bénéfice estimé',
                          style: TextStyle(fontSize: 18, color: LifeHelmColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          FormatUtils.formatFCFA(_amount),
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: LifeHelmColors.accessibleGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              // Bouton géant
              SizedBox(
                width: double.infinity,
                height: 100,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LifeHelmColors.accessibleGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 36, height: 36,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 4),
                        )
                      : const Text(
                          'ENREGISTRER LA VENTE',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
