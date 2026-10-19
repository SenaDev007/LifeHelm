import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import 'finance.dart';

// ═══════════════════════════ ÉCRAN : OPÉRATION ═══════════════════════════

enum _OpType { expense, income, transfer }

/// Saisie d'une opération : dépense, revenu ou transfert interne (D05).
/// Les transferts entre devises conservent les deux montants, le taux et
/// les frais ; les dépenses peuvent être réparties sur plusieurs budgets.
class TransactionEditScreen extends ConsumerStatefulWidget {
  const TransactionEditScreen({super.key, this.initialType, this.initialAccountId});

  final String? initialType;
  final String? initialAccountId;

  @override
  ConsumerState<TransactionEditScreen> createState() =>
      _TransactionEditScreenState();
}

class _TransactionEditScreenState extends ConsumerState<TransactionEditScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _toAmountCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _allocCtrls = <String, TextEditingController>{};

  _OpType _type = _OpType.expense;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  String _status = 'POSTED';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = switch (widget.initialType) {
      'income' => _OpType.income,
      'transfer' => _OpType.transfer,
      _ => _OpType.expense,
    };
    _accountId = widget.initialAccountId;
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _toAmountCtrl.dispose();
    _feeCtrl.dispose();
    for (final c in _allocCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final accounts =
        ref.read(accountsProvider(spaceId)).valueOrNull ?? [];
    if (accounts.isEmpty) {
      lhToast(context, 'Créez d\'abord un compte.');
      return;
    }
    final account = accounts.firstWhere((a) => a.id == _accountId,
        orElse: () => accounts.first);

    if (_type == _OpType.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) {
        lhToast(context, 'Choisissez deux comptes différents.');
        return;
      }
      final from = Money.tryParse(_amountCtrl.text, Currency.byCode(account.currency));
      if (from == null || from.isZero) {
        lhToast(context, 'Montant invalide.');
        return;
      }
      final toAccount = accounts.firstWhere((a) => a.id == _toAccountId);
      final toCur = Currency.byCode(toAccount.currency);
      Money to;
      if (toCur.code == from.currency.code) {
        to = from;
      } else {
        final parsed = Money.tryParse(_toAmountCtrl.text, toCur);
        if (parsed == null) {
          lhToast(context, 'Saisissez le montant reçu dans la devise cible.');
          return;
        }
        to = parsed;
      }
      final fee = _feeCtrl.text.trim().isEmpty
          ? null
          : Money.tryParse(_feeCtrl.text, from.currency)?.minor;
      final rate = from.currency.code == 'XOF'
          ? (toCur.code == 'XOF'
              ? 1.0
              : 1.0 / (Currency.tauxVersXof[toCur.code] ?? 1))
          : Currency.tauxVersXof[from.currency.code] ?? 1.0;

      setState(() => _saving = true);
      await db.saveTransfer(
        spaceId: spaceId,
        fromAccountId: account.id,
        toAccountId: toAccount.id,
        fromAmount: from.minor,
        fromCurrency: from.currency.code,
        toAmount: to.minor,
        toCurrency: to.currency.code,
        rate: rate,
        fee: fee,
        occurredAt: _date,
      );
      if (mounted) context.pop();
      return;
    }

    final money = Money.tryParse(_amountCtrl.text, Currency.byCode(account.currency));
    if (money == null || money.isZero) {
      lhToast(context, 'Saisissez un montant valide.');
      return;
    }

    // Allocations budgétaires (dépenses uniquement) — répartition explicite.
    final allocations = <({String budgetId, int amount})>[];
    if (_type == _OpType.expense) {
      for (final entry in _allocCtrls.entries) {
        final m = Money.tryParse(entry.value.text, Currency.xof);
        if (m != null && !m.isZero) {
          allocations.add((budgetId: entry.key, amount: m.minor));
        }
      }
      final total = allocations.fold<int>(0, (s, a) => s + a.amount);
      if (allocations.isNotEmpty && total > money.minor) {
        lhToast(context,
            'La répartition (${total} FCFA) dépasse le montant de l\'opération.');
        return;
      }
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final tx = FinancialTransaction(
      id: 'tx_${now.microsecondsSinceEpoch}',
      spaceId: spaceId,
      accountId: account.id,
      kind: _type == _OpType.income ? 'INCOME' : 'EXPENSE',
      amount: money.minor,
      currency: money.currency.code,
      status: _status,
      categoryId: _categoryId,
      occurredAt: _date,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      createdAt: now,
    );
    await db.saveTransaction(tx, allocations: allocations);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final accounts = ref.watch(accountsProvider(spaceId)).valueOrNull ?? [];
    final categories =
        ref.watch(categoriesProvider(spaceId)).valueOrNull ?? [];
    final budgets = ref.watch(budgetStatsProvider(spaceId)).valueOrNull ?? [];

    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    if (_toAccountId == null && accounts.length > 1) {
      _toAccountId =
          accounts.firstWhere((a) => a.id != _accountId).id;
    }
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final currency = Currency.byCode(account?.currency ?? 'XOF');
    final relevantCategories = _type == _OpType.income
        ? categories.where((c) => c.kind == 'INCOME')
        : categories.where((c) => c.kind == 'EXPENSE');
    final currentPeriod = fmt.dateKey(DateTime(_date.year, _date.month, 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle opération'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Enregistrer')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(LHSpacing.screen),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LhSegmented<_OpType>(
            value: _type,
            items: const {
              _OpType.expense: 'Dépense',
              _OpType.income: 'Revenu',
              _OpType.transfer: 'Transfert',
            },
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: LHSpacing.xl),
          // Montant
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0 ${currency.symbol}',
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: LHSpacing.lg),
          if (_type == _OpType.transfer) ...[
            LabeledField(
              label: 'Depuis le compte',
              child: DropdownButtonFormField<String>(
                value: _accountId,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${a.currency})')),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Vers le compte',
              child: DropdownButtonFormField<String>(
                value: _toAccountId,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${a.currency})')),
                ],
                onChanged: (v) => setState(() => _toAccountId = v),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            if (account != null &&
                _toAccountId != null &&
                accounts
                        .where((a) => a.id == _toAccountId)
                        .firstOrNull
                        ?.currency !=
                    account.currency) ...[
              LabeledField(
                label:
                    'Montant reçu (${accounts.where((a) => a.id == _toAccountId).first.currency}) — conversion explicite',
                child: TextField(
                  controller: _toAmountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'Montant dans la devise cible'),
                ),
              ),
              const SizedBox(height: LHSpacing.md),
            ],
            LabeledField(
              label: 'Frais de transfert (optionnel)',
              child: TextField(
                controller: _feeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    hintText: '0 ${currency.symbol} — opération distincte'),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LHColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(LHRadius.md),
                border:
                    Border.all(color: LHColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: LHColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Un transfert interne n\'est ni un revenu ni une dépense dans les totaux consolidés (CDC D05).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(height: 1.4),
                  ),
                ),
              ]),
            ),
          ] else ...[
            LabeledField(
              label: 'Compte',
              child: DropdownButtonFormField<String>(
                value: _accountId,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${a.currency})')),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Catégorie',
              child: DropdownButtonFormField<String>(
                value: _categoryId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sans catégorie')),
                  ...relevantCategories.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: _hex(c.colorHex),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ]))),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            if (_type == _OpType.expense) ...[
              LabeledField(
                label: 'Répartition budgétaire (optionnelle)',
                child: Column(children: [
                  for (final s in budgets.where((s) =>
                      s.budget.periodStart == currentPeriod))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text(s.budget.name,
                                style: theme.textTheme.bodyMedium)),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _allocCtrls.putIfAbsent(
                                s.budget.id, TextEditingController.new),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                hintText: '0', isDense: true),
                          ),
                        ),
                      ]),
                    ),
                  if (budgets
                      .where((s) => s.budget.periodStart == currentPeriod)
                      .isEmpty)
                    Text('Aucun budget sur la période — répartition inactive.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(height: LHSpacing.md),
            ],
          ],
          // Date + statut
          Row(children: [
            Expanded(
              child: LabeledField(
                label: 'Date',
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      locale: const Locale('fr'),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(fmt.formatLong(_date)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: LHSpacing.md),
            Expanded(
              child: LabeledField(
                label: 'Statut',
                child: DropdownButtonFormField<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'POSTED', child: Text('Comptabilisée')),
                    DropdownMenuItem(value: 'PENDING', child: Text('En attente')),
                  ],
                  onChanged: (v) =>
                      setState(() => _status = v ?? 'POSTED'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: LHSpacing.md),
          LabeledField(
            label: 'Note (optionnel)',
            child: TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(hintText: 'Ex. : Marché d\'Adjara'),
            ),
          ),
          const SizedBox(height: LHSpacing.xxl),
        ]),
      ),
    );
  }

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return LHColors.neutre;
    return Color(int.parse('FF$h', radix: 16));
  }
}

// ═══════════════════════════ ÉCRAN : BUDGETS ═══════════════════════════

/// Budgets — enveloppe E = B + A + R, dépenses D, solde S = E − D (D05 §10.5).
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final statsAsync = ref.watch(budgetStatsProvider(spaceId));
    final theme = Theme.of(context);
    final threshold = (double.tryParse(
            ref.watch(settingsProvider).valueOrNull?['budgetAlertThreshold'] ??
                '') ??
        0.8);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createDialog(context, ref, spaceId),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau budget'),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: '$e'),
        data: (stats) {
          if (stats.isEmpty) {
            return const EmptyState(
              icon: Icons.donut_small_outlined,
              message: 'Aucun budget',
              hint: 'Créez une enveloppe mensuelle pour piloter vos dépenses.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            itemCount: stats.length,
            itemBuilder: (context, i) {
              final s = stats[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                child: LHCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(s.budget.name,
                                  style: theme.textTheme.titleMedium)),
                          PopupMenuButton<String>(
                            onSelected: (v) =>
                                _budgetAction(context, ref, s, v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'adjust', child: Text('Ajuster (+/−)')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Supprimer')),
                            ],
                          ),
                        ]),
                        Text(
                          '${fmt.formatShort(fmt.parseKey(s.budget.periodStart))} → ${fmt.formatShort(fmt.parseKey(s.budget.periodEnd))}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: LHSpacing.md),
                        BudgetBar(ratio: s.ratio, alertRatio: threshold),
                        const SizedBox(height: LHSpacing.sm),
                        Row(children: [
                          Expanded(
                            child: StatTile(
                                label: 'Dépensé (D)',
                                value: Money(s.spent, s.currency)
                                    .format(withCode: false),
                                color: s.ratio >= threshold
                                    ? LHColors.alerte
                                    : LHColors.financePositif),
                          ),
                          Expanded(
                            child: StatTile(
                                label: 'Reste (S)',
                                value: Money(s.available, s.currency)
                                    .format(withCode: false),
                                color: s.available < 0
                                    ? LHColors.erreur
                                    : LHColors.emeraudeClair),
                          ),
                          Expanded(
                            child: StatTile(
                                label: 'Enveloppe (E)',
                                value: Money(s.envelope, s.currency)
                                    .format(withCode: false)),
                          ),
                        ]),
                        if (s.adjustments != 0 || s.carryover != 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Base ${Money(s.budget.initialAmount, s.currency).format(withCode: false)}'
                              '${s.adjustments != 0 ? ' · ajustement ${Money(s.adjustments, s.currency).format(withCode: false)}' : ''}'
                              '${s.carryover != 0 ? ' · report ${Money(s.carryover, s.currency).format(withCode: false)}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _budgetAction(
      BuildContext context, WidgetRef ref, BudgetStat s, String action) async {
    final db = ref.read(dbProvider);
    if (action == 'delete') {
      final ok = await lhConfirm(context,
          title: 'Supprimer le budget ?',
          message: '« ${s.budget.name} » sera supprimé. Les opérations restent intactes.',
          confirmLabel: 'Supprimer',
          destructive: true);
      if (ok) {
        // Journalise la disparition des enfants (ajustements, allocations)
        // avant la suppression — la sync propagera la cascade.
        final adjustments = await (db.select(db.budgetAdjustments)
              ..where((a) => a.budgetId.equals(s.budget.id)))
            .get();
        final allocs = await (db.select(db.transactionAllocations)
              ..where((a) => a.budgetId.equals(s.budget.id)))
            .get();
        await (db.delete(db.budgetAdjustments)
              ..where((a) => a.budgetId.equals(s.budget.id)))
            .go();
        await (db.delete(db.transactionAllocations)
              ..where((a) => a.budgetId.equals(s.budget.id)))
            .go();
        for (final a in adjustments) {
          db.logOp('BudgetAdjustment', a.id, 'DELETE', {});
        }
        for (final a in allocs) {
          db.logOp('TransactionAllocation', a.id, 'DELETE', {});
        }
        await (db.delete(db.budgets)..where((b) => b.id.equals(s.budget.id))).go();
        db.logOp('Budget', s.budget.id, 'DELETE', {'name': s.budget.name});
      }
      return;
    }
    final ctrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajuster l\'enveloppe'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Budget « ${s.budget.name} » — enveloppe actuelle ${Money(s.envelope, s.currency).format()}'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                hintText: 'Montant signé, ex. : 10000 ou -5000'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(hintText: 'Motif (optionnel)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final m = Money.tryParse(ctrl.text, Currency.xof);
              if (m == null || m.isZero) return;
              final adjId = 'adj_${DateTime.now().microsecondsSinceEpoch}';
              await db.into(db.budgetAdjustments).insert(BudgetAdjustment(
                  id: adjId,
                  budgetId: s.budget.id,
                  amount: m.minor,
                  reason: reasonCtrl.text.trim().isEmpty
                      ? null
                      : reasonCtrl.text.trim(),
                  createdAt: DateTime.now()));
              db.logOp('BudgetAdjustment', adjId, 'CREATE',
                  {'amount': m.minor});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Ajuster'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDialog(
      BuildContext context, WidgetRef ref, String spaceId) async {
    final db = ref.read(dbProvider);
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final now = DateTime.now();
    final mStart = DateTime(now.year, now.month, 1);
    final mEnd = DateTime(now.year, now.month + 1, 0);
    final categories =
        ref.read(categoriesProvider(spaceId)).valueOrNull ?? [];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau budget'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: 'Nom, ex. : Marché')),
          const SizedBox(height: 10),
          TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Montant (FCFA)')),
          const SizedBox(height: 10),
          StatefulBuilder(builder: (ctx, setInner) {
            String? catId;
            return StatefulBuilder(
              builder: (ctx, setInner2) => DropdownButtonFormField<String>(
                value: catId,
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Sans catégorie')),
                  ...categories
                      .where((c) => c.kind == 'EXPENSE')
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setInner2(() => catId = v),
              ),
            );
          }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final m = Money.tryParse(amountCtrl.text, Currency.xof);
              if (nameCtrl.text.trim().isEmpty || m == null) return;
              final id = 'bud_${DateTime.now().microsecondsSinceEpoch}';
              await db.into(db.budgets).insert(Budget(
                  id: id,
                  spaceId: spaceId,
                  name: nameCtrl.text.trim(),
                  periodStart: fmt.dateKey(mStart),
                  periodEnd: fmt.dateKey(mEnd),
                  initialAmount: m.minor,
                  carryoverEnabled: false,
                  createdAt: DateTime.now()));
              db.logOp('Budget', id, 'CREATE', {'name': nameCtrl.text.trim()});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : ÉCHÉANCES ═══════════════════════════

/// Échéances financières — prévues, réglées, void ; une échéance ne
/// diminue jamais le solde avant la transaction réelle (D05 §10.6).
class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final duesAsync = ref.watch(duesProvider(spaceId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Échéances')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createDialog(context, ref, spaceId),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle échéance'),
      ),
      body: duesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: '$e'),
        data: (dues) {
          final open = dues.where((d) => d.status == 'OPEN').toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final settled = dues.where((d) => d.status != 'OPEN').toList()
            ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
          if (dues.isEmpty) {
            return const EmptyState(
              icon: Icons.event_repeat_outlined,
              message: 'Aucune échéance',
              hint: 'Suivez vos loyers, écolages et abonnements ici.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            children: [
              if (open.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text('À régler',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ...open.map((d) => _dueTile(context, ref, d)),
              if (settled.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text('Réglées & annulées',
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ...settled.map((d) => _dueTile(context, ref, d, settledMode: true)),
            ],
          );
        },
      ),
    );
  }

  Widget _dueTile(BuildContext context, WidgetRef ref, FinancialDueItem d,
      {bool settledMode = false}) {
    final theme = Theme.of(context);
    final todayKey = fmt.dateKey(fmt.today());
    final late = d.status == 'OPEN' && d.dueDate.compareTo(todayKey) < 0;
    final money = Money(d.expectedAmount, Currency.byCode(d.currency));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LHCard(
        accent: settledMode
            ? LHColors.neutre
            : late
                ? LHColors.erreur
                : LHColors.or,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(d.label, style: theme.textTheme.titleSmall)),
                if (d.status == 'PAID')
                  const StatusChip(
                      label: 'Réglée', color: LHColors.emeraudeClair, small: true)
                else if (d.status == 'VOID')
                  const StatusChip(
                      label: 'Annulée', color: LHColors.neutre, small: true),
              ]),
              Text(
                d.status == 'OPEN'
                    ? (late
                        ? 'En retard — prévu le ${fmt.formatShort(fmt.parseKey(d.dueDate))}'
                        : 'Prévu le ${fmt.formatLong(fmt.parseKey(d.dueDate))}')
                    : fmt.formatShort(fmt.parseKey(d.dueDate)),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: late ? LHColors.erreur : null),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(money.format(withCode: false),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (d.status == 'OPEN')
            PopupMenuButton<String>(
              onSelected: (v) => _dueAction(context, ref, d, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pay', child: Text('Régler maintenant')),
                PopupMenuItem(value: 'void', child: Text('Annuler')),
              ],
            ),
        ]),
      ),
    );
  }

  Future<void> _dueAction(
      BuildContext context, WidgetRef ref, FinancialDueItem d, String action) async {
    final db = ref.read(dbProvider);
    if (action == 'void') {
      await (db.update(db.financialDueItems)..where((x) => x.id.equals(d.id)))
          .write(const FinancialDueItemsCompanion(status: Value('VOID')));
      db.logOp('FinancialDueItem', d.id, 'UPDATE', {'status': 'VOID'});
      return;
    }
    final spaceId = ref.read(activeSpaceIdProvider);
    final accounts =
        ref.read(accountsProvider(spaceId)).valueOrNull ?? [];
    if (accounts.isEmpty) {
      lhToast(context, 'Aucun compte disponible.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Régler « ${d.label} » — ${Money(d.expectedAmount, Currency.byCode(d.currency)).format()}',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          ...accounts.map((a) => ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text('${a.name} (${a.currency})'),
                onTap: () async {
                  await db.payDue(d, a);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              )),
        ]),
      ),
    );
  }

  Future<void> _createDialog(
      BuildContext context, WidgetRef ref, String spaceId) async {
    final db = ref.read(dbProvider);
    final labelCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    var dueDate = fmt.addDays(fmt.today(), 7);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Nouvelle échéance'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                    hintText: 'Libellé, ex. : Loyer de novembre')),
            const SizedBox(height: 10),
            TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Montant attendu (FCFA)')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: dueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  locale: const Locale('fr'),
                );
                if (picked != null) setInner(() => dueDate = picked);
              },
              child: Text('Échéance : ${fmt.formatLong(dueDate)}'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                final m = Money.tryParse(amountCtrl.text, Currency.xof);
                if (labelCtrl.text.trim().isEmpty || m == null) return;
                final id = 'due_${DateTime.now().microsecondsSinceEpoch}';
                await db.into(db.financialDueItems).insert(FinancialDueItem(
                    id: id,
                    spaceId: spaceId,
                    label: labelCtrl.text.trim(),
                    expectedAmount: m.minor,
                    currency: 'XOF',
                    dueDate: fmt.dateKey(dueDate),
                    status: 'OPEN',
                    createdAt: DateTime.now()));
                db.logOp('FinancialDueItem', id, 'CREATE',
                    {'label': labelCtrl.text.trim()});
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}
