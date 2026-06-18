import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes comptes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Ajouter',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accountsProvider),
        child: accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            error: e.toString(),
            onRetry: () => ref.invalidate(accountsProvider),
          ),
          data: (accounts) {
            if (accounts.isEmpty) {
              return _EmptyView(
                icon: Icons.account_balance_wallet,
                message: 'Aucun compte pour le moment',
                cta: 'Ajouter un compte',
                onCta: () => _showAddDialog(context, ref),
              );
            }
            final total = accounts.fold<num>(0, (s, a) => s + a.balance);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Solde total', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          FormatUtils.formatFCFA(total),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: LifeHelmColors.finance,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${accounts.length} compte(s)', style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...accounts.map((a) => _AccountCard(account: a)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.finance,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = AppCategories.accountTypes[account.type] ?? '✨';
    final isPositive = account.balance >= 0;
    return Dismissible(
      key: ValueKey(account.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: LifeHelmColors.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer le compte ?'),
            content: Text('Supprimer « ${account.name} » ? Les transactions associées ne seront pas supprimées.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: LifeHelmColors.danger),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        try {
          await ref.read(financeRepositoryProvider).deleteAccount(account.id);
          ref.invalidate(accountsProvider);
          ref.invalidate(financeDashboardProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compte supprimé'), backgroundColor: LifeHelmColors.success),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
            );
            ref.invalidate(accountsProvider);
          }
        }
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: LifeHelmColors.finance.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      AppCategories.accountTypes[account.type] != null
                          ? account.type.replaceAll('_', ' ')
                          : 'Compte',
                      style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.formatFCFA(account.balance),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isPositive ? LifeHelmColors.finance : LifeHelmColors.danger,
                    ),
                  ),
                  if (account.archived)
                    const Text('Archivé', style: TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAccountDialog extends ConsumerStatefulWidget {
  const _AddAccountDialog();

  @override
  ConsumerState<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<_AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  String _type = 'CASH';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(financeRepositoryProvider).createAccount({
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'balance': double.tryParse(_balanceCtrl.text) ?? 0,
        'currency': 'XOF',
      });
      ref.invalidate(accountsProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte ajouté'), backgroundColor: LifeHelmColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau compte'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LifeHelmTextField(
                controller: _nameCtrl,
                label: 'Nom du compte',
                hint: 'Ex: MTN MoMo principal',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type de compte'),
                items: AppCategories.accountTypes.keys.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Text(AppCategories.accountTypes[t]!, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(t.replaceAll('_', ' ')),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _type = v ?? 'CASH'),
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _balanceCtrl,
                label: 'Solde initial',
                hint: '0',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Solde requis (0 si vide)';
                  if (double.tryParse(v) == null) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        LifeHelmButton(
          label: 'Enregistrer',
          isLoading: _isLoading,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
        const SizedBox(height: 16),
        const Text('Impossible de charger', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error, style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.icon, required this.message, required this.cta, required this.onCta});
  final IconData icon;
  final String message;
  final String cta;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: LifeHelmColors.textTertiary),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: LifeHelmColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(onPressed: onCta, icon: const Icon(Icons.add), label: Text(cta)),
          ],
        ),
      ),
    );
  }
}
