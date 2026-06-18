import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class TontinesScreen extends ConsumerWidget {
  const TontinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tontinesAsync = ref.watch(tontinesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes tontines'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => _showAddDialog(context, ref),
            tooltip: 'Nouvelle tontine',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tontinesProvider),
        child: tontinesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
                  const SizedBox(height: 16),
                  Text('Erreur: $e', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(tontinesProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (tontines) {
            if (tontines.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.groups, size: 64, color: LifeHelmColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text('Aucune tontine', style: TextStyle(color: LifeHelmColors.textSecondary)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Créer une tontine'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final totalPot = tontines.fold<num>(0, (s, t) => s + t.totalPot);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: LifeHelmColors.accent,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pot total cumulé', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          FormatUtils.formatFCFA(totalPot),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...tontines.map((t) => _TontineCard(tontine: t)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: LifeHelmColors.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddTontineDialog());
  }
}

class _TontineCard extends ConsumerWidget {
  const _TontineCard({required this.tontine});
  final Tontine tontine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTurn = tontine.myRank == 1; // simple heuristic
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showMembersSheet(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: LifeHelmColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups, color: LifeHelmColors.accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tontine.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          '${tontine.totalMembers} membres • ${_frequencyLabel(tontine.frequency)}',
                          style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (myTurn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: LifeHelmColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'À toi !',
                        style: TextStyle(color: LifeHelmColors.success, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatBlock(
                      label: 'Mise',
                      value: FormatUtils.formatCompact(tontine.contributionAmount),
                      color: LifeHelmColors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: _StatBlock(
                      label: 'Ton rang',
                      value: '${tontine.myRank}/${tontine.totalMembers}',
                      color: LifeHelmColors.info,
                    ),
                  ),
                  Expanded(
                    child: _StatBlock(
                      label: 'Pot total',
                      value: FormatUtils.formatCompact(tontine.totalPot),
                      color: LifeHelmColors.accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _frequencyLabel(String f) {
    switch (f) {
      case 'WEEKLY': return 'Hebdomadaire';
      case 'DAILY': return 'Quotidienne';
      default: return 'Mensuelle';
    }
  }

  void _showMembersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MembersSheet(tontine: tontine),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LifeHelmColors.textTertiary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
      ],
    );
  }
}

class _MembersSheet extends StatelessWidget {
  const _MembersSheet({required this.tontine});
  final Tontine tontine;

  @override
  Widget build(BuildContext context) {
    final members = tontine.members;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LifeHelmColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tontine.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Pot: ${FormatUtils.formatFCFA(tontine.totalPot)}',
                    style: const TextStyle(color: LifeHelmColors.accent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Mise: ${FormatUtils.formatFCFA(tontine.contributionAmount)} • ${tontine.totalMembers} membres',
                style: const TextStyle(color: LifeHelmColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text('Membres', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Aucun membre enregistré', style: TextStyle(color: LifeHelmColors.textSecondary))),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (ctx, i) {
                      final m = members[i];
                      final isMe = m.rank == tontine.myRank;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: LifeHelmColors.accent.withValues(alpha: 0.15),
                            child: Text('${m.rank}', style: const TextStyle(color: LifeHelmColors.accent, fontWeight: FontWeight.w800)),
                          ),
                          title: Text(
                            m.name + (isMe ? ' (toi)' : ''),
                            style: TextStyle(fontWeight: isMe ? FontWeight.w800 : FontWeight.w600),
                          ),
                          subtitle: m.phone != null ? Text(m.phone!) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: m.paid ? 'A payé' : 'Pas encore payé',
                                child: Icon(
                                  m.paid ? Icons.check_circle : Icons.cancel,
                                  color: m.paid ? LifeHelmColors.success : LifeHelmColors.danger,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Tooltip(
                                message: m.received ? 'A reçu' : 'Pas encore reçu',
                                child: Icon(
                                  m.received ? Icons.savings : Icons.hourglass_empty,
                                  color: m.received ? LifeHelmColors.info : LifeHelmColors.textTertiary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTontineDialog extends ConsumerStatefulWidget {
  const _AddTontineDialog();

  @override
  ConsumerState<_AddTontineDialog> createState() => _AddTontineDialogState();
}

class _AddTontineDialogState extends ConsumerState<_AddTontineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _miseCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _rankCtrl = TextEditingController();
  String _frequency = 'MONTHLY';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _miseCtrl.dispose();
    _totalCtrl.dispose();
    _rankCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final total = int.tryParse(_totalCtrl.text) ?? 0;
    final rank = int.tryParse(_rankCtrl.text) ?? 1;
    if (rank < 1 || rank > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ton rang doit être entre 1 et le nombre de membres'), backgroundColor: LifeHelmColors.danger),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(financeRepositoryProvider).createTontine({
        'name': _nameCtrl.text.trim(),
        'contributionAmount': double.parse(_miseCtrl.text),
        'frequency': _frequency,
        'totalMembers': total,
        'myRank': rank,
      });
      ref.invalidate(tontinesProvider);
      ref.invalidate(financeDashboardProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tontine créée'), backgroundColor: LifeHelmColors.success),
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
      title: const Text('Nouvelle tontine'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LifeHelmTextField(
                controller: _nameCtrl,
                label: 'Nom de la tontine',
                hint: 'Ex: Tontine famille',
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              LifeHelmTextField(
                controller: _miseCtrl,
                label: 'Mise (FCFA)',
                hint: '10000',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Mise requise';
                  if (double.tryParse(v) == null) return 'Invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _frequency,
                decoration: const InputDecoration(labelText: 'Fréquence'),
                items: const [
                  DropdownMenuItem(value: 'DAILY', child: Text('Quotidienne')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Hebdomadaire')),
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Mensuelle')),
                ],
                onChanged: (v) => setState(() => _frequency = v ?? 'MONTHLY'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LifeHelmTextField(
                      controller: _totalCtrl,
                      label: 'Nb membres',
                      hint: '10',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requis';
                        if (int.tryParse(v) == null) return 'Invalide';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LifeHelmTextField(
                      controller: _rankCtrl,
                      label: 'Ton rang',
                      hint: '1',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requis';
                        if (int.tryParse(v) == null) return 'Invalide';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        LifeHelmButton(
          label: 'Créer',
          isLoading: _isLoading,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }
}
