import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../../finance/providers/finance_providers.dart';
import '../providers/sms_import_providers.dart';

class SmsImportScreen extends ConsumerStatefulWidget {
  const SmsImportScreen({super.key});

  @override
  ConsumerState<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends ConsumerState<SmsImportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _smsCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  Map<String, dynamic>? _preview;
  bool _parsing = false;
  bool _saving = false;
  bool _importedOnly = false;

  @override
  void dispose() {
    _tab.dispose();
    _smsCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final sms = _smsCtrl.text.trim();
    if (sms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Colle d\'abord un SMS'),
          backgroundColor: LifeHelmColors.danger,
        ),
      );
      return;
    }
    setState(() {
      _parsing = true;
      _preview = null;
    });
    try {
      final result = await ref.read(smsImportRepositoryProvider).preview(
            rawSms: sms,
            sender: _senderCtrl.text.trim().isEmpty ? 'INCONNU' : _senderCtrl.text.trim(),
          );
      setState(() => _preview = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _saveAndConvert() async {
    final sms = _smsCtrl.text.trim();
    if (sms.isEmpty) return;
    setState(() => _saving = true);
    try {
      final sender = _senderCtrl.text.trim().isEmpty ? 'INCONNU' : _senderCtrl.text.trim();
      final saved = await ref.read(smsImportRepositoryProvider).save(rawSms: sms, sender: sender);

      if (!mounted) return;
      // Demander le compte
      final accounts = await ref.read(accountsProvider.future);
      if (!mounted) return;
      final accountId = await _pickAccountDialog(accounts.map((a) => (a.id, a.name)).toList());
      if (accountId == null) {
        // SMS sauvé mais pas converti
        ref.invalidate(smsImportsProvider(false));
        ref.invalidate(smsImportsProvider(true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS sauvegardé (non converti). Tu pourras le convertir plus tard.'),
              backgroundColor: LifeHelmColors.info,
            ),
          );
          _smsCtrl.clear();
          setState(() => _preview = null);
        }
        return;
      }
      final tx = await ref.read(smsImportRepositoryProvider).convert(saved.id, accountId);
      ref.invalidate(smsImportsProvider(false));
      ref.invalidate(smsImportsProvider(true));
      if (mounted) {
        final txLabel = tx['label'] as String? ?? 'Transaction';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction créée: $txLabel'),
            backgroundColor: LifeHelmColors.success,
          ),
        );
        _smsCtrl.clear();
        setState(() => _preview = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: LifeHelmColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _pickAccountDialog(List<(String, String)> accounts) async {
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun compte disponible. Crée d\'abord un compte.'),
          backgroundColor: LifeHelmColors.warning,
        ),
      );
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choisir un compte'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: accounts.length,
            itemBuilder: (ctx, i) {
              final a = accounts[i];
              return ListTile(
                leading: const Icon(Icons.account_balance, color: LifeHelmColors.finance),
                title: Text(a.$2),
                onTap: () => Navigator.pop(ctx, a.$1),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import SMS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Nouveau', icon: Icon(Icons.sms)),
            Tab(text: 'Historique', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ImporterTab(
            smsCtrl: _smsCtrl,
            senderCtrl: _senderCtrl,
            preview: _preview,
            parsing: _parsing,
            saving: _saving,
            onParse: _parse,
            onSaveConvert: _saveAndConvert,
            onClear: () {
              _smsCtrl.clear();
              _senderCtrl.clear();
              setState(() => _preview = null);
            },
          ),
          _HistoryTab(
            importedOnly: _importedOnly,
            onToggle: (v) => setState(() => _importedOnly = v),
          ),
        ],
      ),
    );
  }
}

// ---------- IMPORTER TAB ----------

class _ImporterTab extends StatelessWidget {
  const _ImporterTab({
    required this.smsCtrl,
    required this.senderCtrl,
    required this.preview,
    required this.parsing,
    required this.saving,
    required this.onParse,
    required this.onSaveConvert,
    required this.onClear,
  });

  final TextEditingController smsCtrl;
  final TextEditingController senderCtrl;
  final Map<String, dynamic>? preview;
  final bool parsing;
  final bool saving;
  final VoidCallback onParse;
  final VoidCallback onSaveConvert;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LifeHelmColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: LifeHelmColors.info, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Colle un SMS de notification Mobile Money (MTN, Moov, Wave) ou de ta banque. LifeHelm extraira le montant, le tiers et la date pour créer une transaction.',
                    style: TextStyle(color: LifeHelmColors.info, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LifeHelmTextField(
            controller: senderCtrl,
            label: 'Expéditeur (optionnel)',
            hint: 'Ex: MTN, Moov, Wave, BANK',
            prefixIcon: const Icon(Icons.person),
          ),
          const SizedBox(height: 12),
          LifeHelmTextField(
            controller: smsCtrl,
            label: 'Contenu du SMS *',
            hint: 'Colle ici le texte du SMS reçu...',
            maxLines: 6,
            minLines: 4,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LifeHelmButton(
                  label: parsing ? 'Analyse...' : 'Parser',
                  icon: Icons.search,
                  isLoading: parsing,
                  variant: LifeHelmButtonVariant.outline,
                  onPressed: parsing ? null : onParse,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                tooltip: 'Effacer',
                style: IconButton.styleFrom(
                  backgroundColor: LifeHelmColors.bg,
                  minimumSize: const Size(52, 52),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (preview != null) _PreviewCard(data: preview!),
          if (preview != null) ...[
            const SizedBox(height: 16),
            LifeHelmButton(
              label: saving ? 'Sauvegarde...' : 'Sauver + convertir en transaction',
              icon: Icons.save,
              isLoading: saving,
              onPressed: saving ? null : onSaveConvert,
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final provider = (data['provider'] as String?) ?? (data['bank'] as String?) ?? '—';
    final type = (data['type'] as String?) ?? (data['transactionType'] as String?) ?? '—';
    final amount = data['amount'];
    final counterparty = (data['counterparty'] as String?) ??
        (data['recipient'] as String?) ??
        (data['senderName'] as String?) ??
        '—';
    final dateStr = (data['date'] as String?) ?? (data['timestamp'] as String?) ?? '';
    final reference = (data['reference'] as String?) ?? (data['transactionId'] as String?) ?? '';
    final fee = data['fee'];

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LifeHelmColors.info, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: LifeHelmColors.info.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: LifeHelmColors.info, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Données extraites',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: LifeHelmColors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    provider,
                    style: const TextStyle(
                      color: LifeHelmColors.info,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _PreviewRow(
              label: 'Type',
              value: _typeLabel(type),
              icon: _typeIcon(type),
              color: _typeColor(type),
            ),
            if (amount != null) ...[
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Montant',
                value: FormatUtils.formatFCFA(amount is num ? amount : num.tryParse(amount.toString()) ?? 0),
                icon: Icons.payments,
                color: LifeHelmColors.finance,
              ),
            ],
            const SizedBox(height: 8),
            _PreviewRow(
              label: 'Tiers',
              value: counterparty,
              icon: Icons.person,
              color: LifeHelmColors.primary,
            ),
            if (dateStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Date',
                value: _formatDate(dateStr),
                icon: Icons.calendar_today,
                color: LifeHelmColors.textSecondary,
              ),
            ],
            if (reference.isNotEmpty) ...[
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Référence',
                value: reference,
                icon: Icons.tag,
                color: LifeHelmColors.textSecondary,
              ),
            ],
            if (fee != null) ...[
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Frais',
                value: FormatUtils.formatFCFA(fee is num ? fee : num.tryParse(fee.toString()) ?? 0),
                icon: Icons.receipt,
                color: LifeHelmColors.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'INCOME':
      case 'CREDIT':
      case 'DEPOSIT': return 'Revenu / Crédit';
      case 'EXPENSE':
      case 'DEBIT':
      case 'PAYMENT':
      case 'WITHDRAWAL': return 'Dépense / Débit';
      case 'TRANSFER': return 'Transfert';
      default: return type;
    }
  }

  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'INCOME':
      case 'CREDIT':
      case 'DEPOSIT': return Icons.arrow_downward;
      case 'EXPENSE':
      case 'DEBIT':
      case 'PAYMENT':
      case 'WITHDRAWAL': return Icons.arrow_upward;
      case 'TRANSFER': return Icons.swap_horiz;
      default: return Icons.help;
    }
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'INCOME':
      case 'CREDIT':
      case 'DEPOSIT': return LifeHelmColors.success;
      case 'EXPENSE':
      case 'DEBIT':
      case 'PAYMENT':
      case 'WITHDRAWAL': return LifeHelmColors.danger;
      case 'TRANSFER': return LifeHelmColors.info;
      default: return LifeHelmColors.textSecondary;
    }
  }

  String _formatDate(String s) {
    final d = DateTime.tryParse(s);
    if (d != null) return FormatUtils.formatDate(d);
    return s;
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ---------- HISTORY TAB ----------

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.importedOnly, required this.onToggle});
  final bool importedOnly;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(smsImportsProvider(importedOnly));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 18, color: LifeHelmColors.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Non convertis seulement', style: TextStyle(fontSize: 13)),
              ),
              Switch(
                value: importedOnly,
                onChanged: onToggle,
                activeColor: LifeHelmColors.primary,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(smsImportsProvider(importedOnly)),
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
                  const SizedBox(height: 16),
                  Text('Erreur: $e', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(smsImportsProvider(importedOnly)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sms_outlined, size: 64, color: LifeHelmColors.textTertiary),
                          const SizedBox(height: 16),
                          const Text(
                            'Aucun SMS importé',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Colle un SMS dans l\'onglet « Nouveau » pour démarrer.',
                            style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _SmsImportTile(item: list[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SmsImportTile extends ConsumerWidget {
  const _SmsImportTile({required this.item});
  final SmsImport item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = item.imported ? LifeHelmColors.success : LifeHelmColors.warning;
    final statusLabel = item.imported ? 'Converti' : 'En attente';

    final parsed = item.parsedData;
    final amount = parsed?['amount'];
    final type = (parsed?['type'] as String?) ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sms, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.sender,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: LifeHelmColors.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.rawSms,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: LifeHelmColors.textSecondary),
              ),
            ),
            if (parsed != null && amount != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (type.isNotEmpty)
                    Text(
                      type,
                      style: TextStyle(
                        color: _typeColor(type),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (type.isNotEmpty) const SizedBox(width: 8),
                  Text(
                    FormatUtils.formatFCFA(amount is num ? amount : num.tryParse(amount.toString()) ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  if (item.createdAt != null) ...[
                    const Spacer(),
                    Text(
                      FormatUtils.formatRelative(item.createdAt!),
                      style: const TextStyle(fontSize: 11, color: LifeHelmColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ],
            if (!item.imported) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // Demander un compte puis convertir
                    final accounts = await ref.read(accountsProvider.future);
                    if (!context.mounted) return;
                    String? accountId;
                    if (accounts.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Aucun compte disponible'),
                          backgroundColor: LifeHelmColors.warning,
                        ),
                      );
                      return;
                    }
                    accountId = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Choisir un compte'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: accounts.length,
                            itemBuilder: (ctx, i) {
                              final a = accounts[i];
                              return ListTile(
                                leading: const Icon(Icons.account_balance, color: LifeHelmColors.finance),
                                title: Text(a.name),
                                onTap: () => Navigator.pop(ctx, a.id),
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                        ],
                      ),
                    );
                    if (accountId == null) return;
                    try {
                      await ref.read(smsImportRepositoryProvider).convert(item.id, accountId);
                      ref.invalidate(smsImportsProvider(false));
                      ref.invalidate(smsImportsProvider(true));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transaction créée'),
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
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Convertir en transaction'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LifeHelmColors.primary,
                    side: const BorderSide(color: LifeHelmColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'INCOME':
      case 'CREDIT':
      case 'DEPOSIT': return LifeHelmColors.success;
      case 'EXPENSE':
      case 'DEBIT':
      case 'PAYMENT':
      case 'WITHDRAWAL': return LifeHelmColors.danger;
      case 'TRANSFER': return LifeHelmColors.info;
      default: return LifeHelmColors.textSecondary;
    }
  }
}
