import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../theme/theme.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/lifehelm_button.dart';
import '../../../widgets/lifehelm_text_field.dart';
import '../providers/finance_providers.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, required this.type});
  final String type;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _accountId;
  String? _category;
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final isExpense = widget.type == 'EXPENSE';
    final categories = isExpense
        ? AppCategories.expenseCategories
        : widget.type == 'INCOME'
            ? AppCategories.incomeCategories
            : <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (_accountId != null)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _submit,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Type selector
                Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Dépense',
                        icon: Icons.remove_circle,
                        color: LifeHelmColors.danger,
                        selected: widget.type == 'EXPENSE',
                        onTap: () => context.replace('/finance/transactions/add?type=EXPENSE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeButton(
                        label: 'Revenu',
                        icon: Icons.add_circle,
                        color: LifeHelmColors.success,
                        selected: widget.type == 'INCOME',
                        onTap: () => context.replace('/finance/transactions/add?type=INCOME'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Amount
                Text('Montant', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '0 FCFA',
                    suffixText: 'FCFA',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Montant requis';
                    if (double.tryParse(v) == null) return 'Montant invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Compte
                accountsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erreur: $e'),
                  data: (accounts) => DropdownButtonFormField<String>(
                    value: _accountId,
                    decoration: const InputDecoration(labelText: 'Compte'),
                    items: accounts.map((a) {
                      return DropdownMenuItem(value: a.id, child: Text('${AppCategories.accountTypes[a.type]} ${a.name}'));
                    }).toList(),
                    onChanged: (v) => setState(() => _accountId = v),
                    validator: (v) => v == null ? 'Choisis un compte' : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Catégorie
                if (categories.isNotEmpty) ...[
                  Text('Catégorie', style: TextStyle(color: LifeHelmColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.entries.map((e) {
                      final selected = _category == e.key;
                      return InkWell(
                        onTap: () => setState(() => _category = e.key),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? LifeHelmColors.primary : Colors.white,
                            border: Border.all(color: selected ? LifeHelmColors.primary : LifeHelmColors.textTertiary),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e.value, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Text(e.key, style: TextStyle(color: selected ? Colors.white : LifeHelmColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Label
                LifeHelmTextField(
                  controller: _labelCtrl,
                  label: 'Libellé',
                  hint: 'Ex: Marché Dantokpa',
                  validator: (v) => (v == null || v.isEmpty) ? 'Libellé requis' : null,
                ),
                const SizedBox(height: 16),

                // Date
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(FormatUtils.formatDate(_date)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Note
                LifeHelmTextField(
                  controller: _noteCtrl,
                  label: 'Note (optionnel)',
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                LifeHelmButton(
                  label: 'Enregistrer',
                  isLoading: _isLoading,
                  onPressed: _submit,
                  icon: Icons.check,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title() {
    switch (widget.type) {
      case 'INCOME': return 'Nouveau revenu';
      case 'TRANSFER': return 'Nouveau transfert';
      default: return 'Nouvelle dépense';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.createTransaction({
        'accountId': _accountId,
        'type': widget.type,
        'amount': double.parse(_amountCtrl.text),
        'category': _category,
        'label': _labelCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'date': _date.toIso8601String(),
      });
      if (mounted) {
        ref.invalidate(financeDashboardProvider);
        ref.invalidate(transactionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction enregistrée'), backgroundColor: LifeHelmColors.success),
        );
        context.go('/finance/transactions');
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
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.label, required this.icon, required this.color, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          border: Border.all(color: selected ? color : LifeHelmColors.textTertiary, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
