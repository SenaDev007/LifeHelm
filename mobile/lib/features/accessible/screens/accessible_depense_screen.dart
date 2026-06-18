import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../providers/accessible_providers.dart';

class AccessibleDepenseScreen extends ConsumerStatefulWidget {
  const AccessibleDepenseScreen({super.key});

  @override
  ConsumerState<AccessibleDepenseScreen> createState() => _AccessibleDepenseScreenState();
}

class _AccessibleDepenseScreenState extends ConsumerState<AccessibleDepenseScreen> {
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
      final totalSales = today?.totalSales ?? 0;
      final restockCost = _amount;
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
          'netProfit': -restockCost,
        });
      }
      ref.invalidate(accessibleDashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Achat de ${FormatUtils.formatFCFA(_amount)} enregistré'),
            backgroundColor: LifeHelmColors.accessibleRed,
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
        title: const Text('🛒 RÉAPPRO', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
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
                'Combien as-tu dépensé en marchandises ?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Champ montant géant
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: LifeHelmColors.accessibleRed),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: LifeHelmColors.textTertiary),
                  suffixText: 'FCFA',
                  suffixStyle: const TextStyle(fontSize: 24, color: LifeHelmColors.textSecondary, fontWeight: FontWeight.w600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleRed, width: 3),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleRed, width: 3),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: LifeHelmColors.accessibleRed, width: 4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              // Récap achat
              if (_amount > 0)
                Card(
                  color: LifeHelmColors.accessibleRed.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'Achat à déduire',
                          style: TextStyle(fontSize: 18, color: LifeHelmColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '- ${FormatUtils.formatFCFA(_amount)}',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: LifeHelmColors.accessibleRed,
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
                    backgroundColor: LifeHelmColors.accessibleRed,
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
                          'ENREGISTRER L\'ACHAT',
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
