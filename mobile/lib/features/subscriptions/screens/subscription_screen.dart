import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/subscription_providers.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String _selectedPlan = 'PRO';
  String _period = 'MONTHLY';

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansProvider);
    final currentAsync = ref.watch(currentSubscriptionProvider);
    final paymentsAsync = ref.watch(paymentsHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonnements'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(plansProvider);
          ref.invalidate(currentSubscriptionProvider);
          ref.invalidate(paymentsHistoryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Abonnement actuel
            currentAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Erreur: $e', style: const TextStyle(color: LifeHelmColors.danger)),
                ),
              ),
              data: (sub) => _CurrentPlanCard(sub: sub),
            ),
            const SizedBox(height: 20),

            // Choix de période
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choisissez une formule',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                _PeriodToggle(
                  value: _period,
                  onChanged: (v) => setState(() => _period = v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plans
            plansAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erreur plans: $e'),
              data: (plans) => Column(
                children: [
                  _PlanCard(
                    planId: 'FREE',
                    title: 'Free',
                    description: 'Pour démarrer : finances de base, objectifs personnels, routines simples.',
                    pricing: plans.free,
                    period: _period,
                    selected: _selectedPlan == 'FREE',
                    isCurrent: currentAsync.valueOrNull?.plan == 'FREE',
                    onTap: () => setState(() => _selectedPlan = 'FREE'),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    planId: 'PRO',
                    title: 'Pro',
                    description: 'Tout LifeHelm : 360°, HELM AI illimité, rapports PDF, exports CSV.',
                    pricing: plans.pro,
                    period: _period,
                    selected: _selectedPlan == 'PRO',
                    isCurrent: currentAsync.valueOrNull?.plan == 'PRO',
                    onTap: () => setState(() => _selectedPlan = 'PRO'),
                    highlight: true,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    planId: 'FAMILY',
                    title: 'Family',
                    description: 'Pro + Mode Famille : budget partagé, objectifs communs, jusqu\'à 6 membres.',
                    pricing: plans.family,
                    period: _period,
                    selected: _selectedPlan == 'FAMILY',
                    isCurrent: currentAsync.valueOrNull?.plan == 'FAMILY',
                    onTap: () => setState(() => _selectedPlan = 'FAMILY'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Bouton principal
            LifeHelmButton(
              label: _selectedPlan == 'FREE'
                  ? 'Plan gratuit par défaut'
                  : (currentAsync.valueOrNull?.plan == _selectedPlan
                      ? 'Plan actuel'
                      : 'S\'abonner à $_selectedPlan'),
              icon: Icons.star,
              onPressed: (_selectedPlan == 'FREE' ||
                      currentAsync.valueOrNull?.plan == _selectedPlan)
                  ? null
                  : () => _showPaymentSheet(context),
            ),
            const SizedBox(height: 24),

            // Historique des paiements
            const Text(
              'Historique des paiements',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erreur: $e', style: const TextStyle(color: LifeHelmColors.danger)),
              data: (payments) {
                if (payments.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_outlined, size: 40, color: LifeHelmColors.textTertiary),
                          const SizedBox(height: 8),
                          const Text('Aucun paiement enregistré'),
                          const SizedBox(height: 4),
                          const Text(
                            'Vos paiements apparaîtront ici',
                            style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: payments.map((p) => _PaymentTile(payment: p)).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showPaymentSheet(BuildContext context) {
    String method = 'MTN';
    final phoneCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: LifeHelmColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.payment, color: LifeHelmColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Souscrire à $_selectedPlan (${_period == 'MONTHLY' ? 'Mensuel' : 'Annuel'})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez un moyen de paiement',
                style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PaymentMethods.all.map((m) {
                  final selected = method == m;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PaymentMethods.icons[m], size: 16),
                        const SizedBox(width: 6),
                        Text(PaymentMethods.labels[m] ?? m),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => method = m),
                    backgroundColor: LifeHelmColors.bg,
                    side: BorderSide(
                      color: selected ? LifeHelmColors.primary : LifeHelmColors.textTertiary,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : LifeHelmColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (PaymentMethods.isMoMo(method)) ...[
                LifeHelmTextField(
                  controller: phoneCtrl,
                  label: 'Numéro de téléphone',
                  hint: 'Ex: 96123456',
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone_android),
                ),
                const SizedBox(height: 16),
              ],
              LifeHelmButton(
                label: 'Payer',
                icon: Icons.lock_outline,
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _initiatePayment(
                    context: context,
                    plan: _selectedPlan,
                    period: _period,
                    method: method,
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, size: 12, color: LifeHelmColors.textTertiary),
                  const SizedBox(width: 4),
                  const Text(
                    'Paiement sécurisé via FedaPay',
                    style: TextStyle(fontSize: 11, color: LifeHelmColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initiatePayment({
    required BuildContext context,
    required String plan,
    required String period,
    required String method,
    String? phone,
  }) async {
    try {
      final init = await ref.read(subscriptionRepositoryProvider).initiatePayment(
            plan: plan,
            period: period,
            method: method,
            phone: phone,
          );
      if (!context.mounted) return;

      // Ouvrir l'URL de checkout (WebView si disponible, sinon navigateur)
      if (init.checkoutUrl != null && init.checkoutUrl!.isNotEmpty) {
        // Tentative d'ouverture dans le navigateur système (FedaPay checkout compatible)
        final uri = Uri.parse(init.checkoutUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          // Polling simple pour vérifier le statut après retour
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Paiement initié (ID: ${init.paymentId}). Une fois le paiement terminé, revenez vérifier le statut.'),
                backgroundColor: LifeHelmColors.info,
                duration: const Duration(seconds: 5),
              ),
            );
            _showVerifyDialog(context, init.paymentId);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Impossible d\'ouvrir la page de paiement'),
                backgroundColor: LifeHelmColors.danger,
              ),
            );
          }
        }
      } else {
        // Pas d'URL, on vérifie directement
        _showVerifyDialog(context, init.paymentId);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    }
  }

  void _showVerifyDialog(BuildContext context, String paymentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VerifyPaymentDialog(paymentId: paymentId),
    ).then((_) {
      // Rafraîchir après fermeture
      ref.invalidate(currentSubscriptionProvider);
      ref.invalidate(paymentsHistoryProvider);
    });
  }
}

class _CurrentPlanCard extends ConsumerWidget {
  const _CurrentPlanCard({required this.sub});
  final CurrentSubscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color planColor;
    String planLabel;
    switch (sub.plan) {
      case 'PRO':
        planColor = LifeHelmColors.accent;
        planLabel = 'Pro';
        break;
      case 'FAMILY':
        planColor = LifeHelmColors.goals;
        planLabel = 'Family';
        break;
      default:
        planColor = LifeHelmColors.textTertiary;
        planLabel = 'Free';
    }

    Color statusColor;
    String statusLabel;
    switch (sub.status) {
      case 'ACTIVE':
        statusColor = LifeHelmColors.success;
        statusLabel = 'Actif';
        break;
      case 'EXPIRED':
        statusColor = LifeHelmColors.danger;
        statusLabel = 'Expiré';
        break;
      case 'CANCELLED':
        statusColor = LifeHelmColors.warning;
        statusLabel = 'Annulé';
        break;
      case 'PENDING':
        statusColor = LifeHelmColors.info;
        statusLabel = 'En attente';
        break;
      default:
        statusColor = LifeHelmColors.textTertiary;
        statusLabel = 'Inactif';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: planColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.star, color: planColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Abonnement actuel',
                        style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'LifeHelm $planLabel',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sub.expiresAt != null) ...[
              Row(
                children: [
                  const Icon(Icons.event, size: 16, color: LifeHelmColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Expire le ${FormatUtils.formatDate(sub.expiresAt!)}',
                    style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
            if (sub.method != null && sub.method!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.payment, size: 16, color: LifeHelmColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Paiement: ${PaymentMethods.labels[sub.method] ?? sub.method}',
                    style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
            if (sub.autoRenew && sub.isActive) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.autorenew, size: 16, color: LifeHelmColors.textSecondary),
                  const SizedBox(width: 6),
                  const Text(
                    'Renouvellement automatique activé',
                    style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
            if (sub.isActive && sub.autoRenew) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Annuler l\'abonnement'),
                      content: const Text(
                        'L\'abonnement restera actif jusqu\'à la fin de la période en cours, mais ne sera pas renouvelé. Tu pourras te réabonner à tout moment.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                          child: const Text('Annuler l\'abonnement'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await ref.read(subscriptionRepositoryProvider).cancelSubscription();
                    ref.invalidate(currentSubscriptionProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Abonnement annulé (fin de période)'),
                          backgroundColor: LifeHelmColors.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.cancel, size: 18, color: LifeHelmColors.danger),
                label: const Text('Annuler l\'abonnement', style: TextStyle(color: LifeHelmColors.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: LifeHelmColors.danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LifeHelmColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn('MONTHLY', 'Mensuel'),
          _toggleBtn('ANNUAL', 'Annuel'),
        ],
      ),
    );
  }

  Widget _toggleBtn(String key, String label) {
    final selected = value == key;
    return GestureDetector(
      onTap: () => onChanged(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? LifeHelmColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : LifeHelmColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.planId,
    required this.title,
    required this.description,
    required this.pricing,
    required this.period,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
    this.highlight = false,
  });

  final String planId;
  final String title;
  final String description;
  final PlanPricing pricing;
  final String period;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final price = period == 'ANNUAL' ? pricing.annual : pricing.monthly;
    final priceLabel = price > 0 ? FormatUtils.formatFCFA(price) : 'Gratuit';
    final periodLabel = period == 'ANNUAL' ? '/an' : '/mois';

    Color accentColor;
    switch (planId) {
      case 'PRO':
        accentColor = LifeHelmColors.accent;
        break;
      case 'FAMILY':
        accentColor = LifeHelmColors.goals;
        break;
      default:
        accentColor = LifeHelmColors.textSecondary;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? accentColor : LifeHelmColors.textTertiary.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (highlight)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'POPULAIRE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.star, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: LifeHelmColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'ACTUEL',
                                  style: TextStyle(
                                    color: LifeHelmColors.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              priceLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                            if (price > 0) ...[
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  periodLabel,
                                  style: const TextStyle(
                                    color: LifeHelmColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (period == 'ANNUAL' && price > 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              '🎁 2 mois offerts',
                              style: TextStyle(
                                color: LifeHelmColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? accentColor : LifeHelmColors.textTertiary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    switch (payment.status) {
      case 'SUCCESS':
        statusColor = LifeHelmColors.success;
        statusLabel = 'Réussi';
        break;
      case 'FAILED':
        statusColor = LifeHelmColors.danger;
        statusLabel = 'Échoué';
        break;
      case 'CANCELLED':
        statusColor = LifeHelmColors.warning;
        statusLabel = 'Annulé';
        break;
      default:
        statusColor = LifeHelmColors.info;
        statusLabel = 'En attente';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(PaymentMethods.icons[payment.method] ?? Icons.payment, color: statusColor, size: 20),
      ),
      title: Text(
        '${PaymentMethods.labels[payment.method] ?? payment.method} • ${payment.plan ?? ''}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        payment.createdAt != null
            ? '${FormatUtils.formatDate(payment.createdAt!)} • $statusLabel'
            : statusLabel,
        style: TextStyle(color: statusColor, fontSize: 12),
      ),
      trailing: Text(
        FormatUtils.formatCompact(payment.amount),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }
}

class _VerifyPaymentDialog extends ConsumerStatefulWidget {
  const _VerifyPaymentDialog({required this.paymentId});
  final String paymentId;

  @override
  ConsumerState<_VerifyPaymentDialog> createState() => _VerifyPaymentDialogState();
}

class _VerifyPaymentDialogState extends ConsumerState<_VerifyPaymentDialog> {
  bool _verifying = false;
  String? _result;
  bool _success = false;

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _result = null;
    });
    try {
      final result = await ref.read(subscriptionRepositoryProvider).verifyPayment(widget.paymentId);
      final status = (result['status'] as String?) ?? 'PENDING';
      setState(() {
        _success = status == 'SUCCESS' || status == 'ACTIVE';
        _result = _success
            ? 'Paiement confirmé ! Votre abonnement est actif.'
            : (status == 'PENDING'
                ? 'Paiement en cours de traitement. Vous pourrez vérifier à nouveau plus tard.'
                : 'Paiement non abouti. Statut: $status');
      });
    } catch (e) {
      setState(() {
        _success = false;
        _result = 'Erreur: $e';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vérifier le paiement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Une fois le paiement effectué sur la page FedaPay, cliquez sur "Vérifier" pour confirmer.'),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_success ? LifeHelmColors.success : LifeHelmColors.warning).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _success ? Icons.check_circle : Icons.info,
                    color: _success ? LifeHelmColors.success : LifeHelmColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _result!,
                      style: TextStyle(
                        color: _success ? LifeHelmColors.success : LifeHelmColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        ElevatedButton.icon(
          onPressed: _verifying ? null : _verify,
          icon: _verifying
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh, size: 18),
          label: const Text('Vérifier'),
        ),
      ],
    );
  }
}
