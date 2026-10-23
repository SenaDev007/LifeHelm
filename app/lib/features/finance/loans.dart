import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import 'finance.dart';

// ═══════════════════════════ PRÊTS & EMPRUNTS (D05) ═══════════════════════════

/// Prêts accordés et emprunts reçus. Chaque mouvement génère automatiquement
/// une opération en « Épargne et dettes » : le prêt accordé sort du
/// patrimoine, l'emprunt reçu y entre, les remboursements reviennent dans
/// l'autre sens — tout communique avec le module Finances.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final loansAsync = ref.watch(loansProvider(spaceId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Prêts & emprunts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newLoanSheet(context, ref, spaceId),
        icon: const Icon(Icons.handshake_outlined),
        label: const Text('Nouveau'),
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: '$e'),
        data: (loans) {
          if (loans.isEmpty) {
            return const EmptyState(
              icon: Icons.handshake_outlined,
              message: 'Aucun prêt ni emprunt',
              hint: 'Enregistrez l\'argent prêté ou emprunté et suivez les '
                  'remboursements au fil de l\'eau.',
              illustration: 'assets/illustrations/finance.png',
            );
          }
          final lent = loans.where((l) => l.direction == 'LENT').toList();
          final borrowed =
              loans.where((l) => l.direction == 'BORROWED').toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            children: [
              if (lent.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text('Prêts accordés',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final l in lent) _LoanCard(loan: l),
              ],
              if (borrowed.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text('Emprunts reçus',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final l in borrowed) _LoanCard(loan: l),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _newLoanSheet(
      BuildContext context, WidgetRef ref, String spaceId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LoanEditSheet(spaceId: spaceId),
    );
  }
}

/// Fournisseur des prêts de l'espace actif.
final loansProvider = StreamProvider.family<List<Loan>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchLoans(spaceId));

/// Fournisseur des mouvements liés à un prêt.
final loanTransactionsProvider =
    StreamProvider.family<List<FinancialTransaction>, String>(
        (ref, loanId) => ref.watch(dbProvider).watchLoanTransactions(loanId));

// ═══════════════════════════ CARTE PRÊT ═══════════════════════════

class _LoanCard extends ConsumerWidget {
  const _LoanCard({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final txs = ref.watch(loanTransactionsProvider(loan.id)).valueOrNull ??
        const <FinancialTransaction>[];
    final currency = Currency.byCode(loan.currency);

    // Remboursé = mouvements dans le sens du retour de l'argent.
    var repaid = 0;
    for (final t in txs) {
      final isReturn = loan.direction == 'LENT'
          ? t.kind == 'INCOME' // prêt accordé → il revient
          : t.kind == 'EXPENSE'; // emprunt reçu → on rembourse
      if (isReturn && t.status == 'POSTED') repaid += t.amount;
    }
    final remaining = loan.principalAmount - repaid;
    final ratio =
        loan.principalAmount == 0 ? 0.0 : repaid / loan.principalAmount;
    final settled = loan.status == 'SETTLED' || remaining <= 0;
    final isLent = loan.direction == 'LENT';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LHCard(
        accent: loan.status == 'CANCELLED'
            ? LHColors.neutre
            : isLent
                ? LHColors.info
                : LHColors.or,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (isLent ? LHColors.info : LHColors.or)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(LHRadius.md),
                ),
                child: Icon(
                  isLent ? Icons.outbox_outlined : Icons.inbox_outlined,
                  size: 20,
                  color: isLent ? LHColors.info : LHColors.or,
                ),
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(loan.counterparty,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                      ),
                      if (settled)
                        const StatusChip(
                            label: 'Soldé',
                            color: LHColors.emeraudeClair,
                            small: true)
                      else if (loan.status == 'CANCELLED')
                        const StatusChip(
                            label: 'Annulé',
                            color: LHColors.neutre,
                            small: true)
                      else
                        StatusChip(
                            label: isLent ? 'En cours' : 'À rembourser',
                            color: LHColors.alerte,
                            small: true),
                    ]),
                    Text(
                      '${isLent ? 'Prêt accordé' : 'Emprunt reçu'} le '
                      '${fmt.formatShort(fmt.parseKey(loan.startedAt))}'
                      '${loan.expectedAt != null ? ' · retour attendu le ${fmt.formatShort(fmt.parseKey(loan.expectedAt!))}' : ''}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _action(context, ref, v),
                itemBuilder: (_) => [
                  if (loan.status == 'ACTIVE' && !settled)
                    const PopupMenuItem(
                        value: 'repay',
                        child: Text('Enregistrer un remboursement')),
                  if (loan.status == 'ACTIVE' && !settled)
                    const PopupMenuItem(
                        value: 'settle', child: Text('Marquer soldé')),
                  if (loan.status == 'ACTIVE')
                    const PopupMenuItem(
                        value: 'cancel', child: Text('Annuler')),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ]),
            const SizedBox(height: LHSpacing.md),
            BudgetBar(
                ratio: ratio, alertRatio: 2.0), // toujours émeraude < 100 %
            const SizedBox(height: LHSpacing.sm),
            Row(children: [
              Expanded(
                child: StatTile(
                  label: isLent ? 'Remboursé' : 'Remboursé (par vous)',
                  value: Money(repaid, currency).format(withCode: false),
                  color: LHColors.emeraudeClair,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Reste',
                  value: Money(remaining < 0 ? 0 : remaining, currency)
                      .format(withCode: false),
                  color: remaining > 0 ? LHColors.alerte : LHColors.neutre,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Capital',
                  value: Money(loan.principalAmount, currency)
                      .format(withCode: false),
                ),
              ),
            ]),
            if (loan.note != null && loan.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(loan.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(
      BuildContext context, WidgetRef ref, String action) async {
    final db = ref.read(dbProvider);
    switch (action) {
      case 'repay':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => _RepaySheet(loan: loan),
        );
        break;
      case 'settle':
        await (db.update(db.loans)..where((l) => l.id.equals(loan.id)))
            .write(const LoansCompanion(status: Value('SETTLED')));
        db.logOp('Loan', loan.id, 'UPDATE', {'status': 'SETTLED'});
        break;
      case 'cancel':
        await (db.update(db.loans)..where((l) => l.id.equals(loan.id)))
            .write(const LoansCompanion(status: Value('CANCELLED')));
        db.logOp('Loan', loan.id, 'UPDATE', {'status': 'CANCELLED'});
        break;
      case 'delete':
        final ok = await lhConfirm(context,
            title: 'Supprimer ce prêt ?',
            message: '« ${loan.counterparty} » sera supprimé. Les opérations '
                'déjà enregistrées restent intactes (simplement déliées).',
            confirmLabel: 'Supprimer',
            destructive: true);
        if (ok) {
          await (db.update(db.financialTransactions)
                ..where((t) => t.loanId.equals(loan.id)))
              .write(const FinancialTransactionsCompanion(loanId: Value(null)));
          await (db.delete(db.loans)..where((l) => l.id.equals(loan.id))).go();
          db.logOp('Loan', loan.id, 'DELETE', {});
        }
        break;
    }
  }
}

// ═══════════════════════════ CRÉATION D'UN PRÊT ═══════════════════════════

class _LoanEditSheet extends ConsumerStatefulWidget {
  const _LoanEditSheet({required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<_LoanEditSheet> createState() => _LoanEditSheetState();
}

class _LoanEditSheetState extends ConsumerState<_LoanEditSheet> {
  final _counterpartyCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _isLent = true; // true = prêt accordé, false = emprunt reçu
  String? _accountId;
  DateTime _startedAt = DateTime.now();
  DateTime? _expectedAt;
  bool _recordMovement = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _counterpartyCtrl.dispose();
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(dbProvider);
    final accounts =
        ref.read(accountsProvider(widget.spaceId)).valueOrNull ?? [];
    if (_counterpartyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Qui est votre contrepartie ?');
      return;
    }
    final money = Money.tryParse(_amountCtrl.text, Currency.xof);
    if (money == null || money.isZero) {
      setState(() => _error = 'Saisissez un montant valide.');
      return;
    }
    if (_recordMovement && accounts.isEmpty) {
      setState(() => _error =
          'Aucun compte : créez-en un via « Nouveau compte… » ci-dessous, '
              'ou décochez l\'enregistrement du mouvement.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final loanId = 'loan_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.loans).insert(Loan(
        id: loanId,
        spaceId: widget.spaceId,
        direction: _isLent ? 'LENT' : 'BORROWED',
        counterparty: _counterpartyCtrl.text.trim(),
        principalAmount: money.minor,
        currency: 'XOF',
        interestRate:
            double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.')),
        startedAt: fmt.dateKey(_startedAt),
        expectedAt: _expectedAt == null ? null : fmt.dateKey(_expectedAt!),
        status: 'ACTIVE',
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        createdAt: DateTime.now()));
    db.logOp('Loan', loanId, 'CREATE',
        {'counterparty': _counterpartyCtrl.text.trim()});

    // Mouvement financier automatique : catégories dédiées de la taxonomie
    // (« Prêt accordé » en dépense, « Emprunt reçu » en recette…).
    if (_recordMovement) {
      final account = accounts.firstWhere((a) => a.id == _accountId,
          orElse: () => accounts.first);
      final category = await _findCategory(db, widget.spaceId,
          _isLent ? 'Prêt accordé' : 'Emprunt reçu (capital emprunté)');
      final now = DateTime.now();
      final tx = FinancialTransaction(
        id: 'tx_${now.microsecondsSinceEpoch}',
        spaceId: widget.spaceId,
        accountId: account.id,
        kind: _isLent ? 'EXPENSE' : 'INCOME',
        amount: money.minor,
        currency: 'XOF',
        status: 'POSTED',
        categoryId: category?.id,
        loanId: loanId,
        occurredAt: _startedAt,
        note: _isLent
            ? 'Prêt accordé à ${_counterpartyCtrl.text.trim()}'
            : 'Emprunt reçu de ${_counterpartyCtrl.text.trim()}',
        createdAt: now,
      );
      await db.saveTransaction(tx);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Résout une sous-catégorie de la taxonomie par son nom unique
  /// (« Prêt accordé », « Emprunt reçu (capital emprunté) », etc.).
  Future<FinancialCategory?> _findCategory(
      AppDatabase db, String spaceId, String name) async {
    final cats = await db.getCategoriesOnce(spaceId);
    return cats.where((c) => c.name == name).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts =
        ref.watch(accountsProvider(widget.spaceId)).valueOrNull ?? [];
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau prêt ou emprunt',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              'Le mouvement est classé automatiquement en « Épargne et '
              'dettes » et communique avec vos comptes.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            LhSegmented<bool>(
              value: _isLent,
              items: const {
                true: 'Prêt accordé',
                false: 'Emprunt reçu',
              },
              onChanged: (v) => setState(() => _isLent = v),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: _isLent
                  ? 'À qui avez-vous prêté ?'
                  : 'De qui avez-vous emprunté ?',
              child: TextField(
                controller: _counterpartyCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: _isLent ? 'Ex. : Koffi Adjoua' : 'Ex. : MFI Espoir',
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Montant (FCFA)',
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    hintText: 'Ex. : 50000',
                    prefixIcon: Icon(Icons.payments_outlined)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            Row(children: [
              Expanded(
                child: LabeledField(
                  label: 'Date du prêt',
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startedAt,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('fr'),
                      );
                      if (picked != null) {
                        setState(() => _startedAt = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(),
                      child: Text(fmt.formatShort(_startedAt)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: LHSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'Retour attendu',
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expectedAt ??
                            _startedAt.add(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('fr'),
                      );
                      if (picked != null) setState(() => _expectedAt = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(),
                      child: Text(_expectedAt == null
                          ? 'Non défini'
                          : fmt.formatShort(_expectedAt!)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Taux d\'intérêt annuel (optionnel, %)',
              child: TextField(
                controller: _rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    hintText: 'Ex. : 10',
                    prefixIcon: Icon(Icons.percent_outlined)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            AccountPickerField(
              label: 'Compte du mouvement',
              value: _accountId,
              onChanged: (v) => setState(() => _accountId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.swap_vert_rounded),
              title: Text(_isLent
                  ? 'Enregistrer la sortie d\'argent maintenant'
                  : 'Enregistrer l\'entrée d\'argent maintenant'),
              subtitle: Text(
                  _isLent
                      ? 'Dépense « Épargne et dettes · Prêt accordé »'
                      : 'Recette « Épargne et dettes · Emprunt reçu »',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              value: _recordMovement,
              onChanged: (v) => setState(() => _recordMovement = v),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Note (optionnel)',
              child: TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                    hintText: 'Ex. : remboursement en 3 tranches'),
              ),
            ),
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ REMBOURSEMENT ═══════════════════════════

class _RepaySheet extends ConsumerStatefulWidget {
  const _RepaySheet({required this.loan});
  final Loan loan;

  @override
  ConsumerState<_RepaySheet> createState() => _RepaySheetState();
}

class _RepaySheetState extends ConsumerState<_RepaySheet> {
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String? _accountId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loan = widget.loan;
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final accounts = ref.read(accountsProvider(spaceId)).valueOrNull ?? [];
    final money = Money.tryParse(_amountCtrl.text, Currency.xof);
    if (money == null || money.isZero) {
      setState(() => _error = 'Saisissez un montant valide.');
      return;
    }
    if (accounts.isEmpty) {
      setState(() => _error = 'Aucun compte disponible.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final account = accounts.firstWhere((a) => a.id == _accountId,
        orElse: () => accounts.first);
    final cats = await db.getCategoriesOnce(spaceId);
    final isLent = loan.direction == 'LENT';
    // Prêt accordé → l'argent REVIENT (recette « Prêt accordé remboursé ») ;
    // Emprunt reçu → on REMBOURSE (dépense « Remboursement d'emprunt »).
    final subName =
        isLent ? 'Prêt accordé remboursé' : 'Remboursement d\'emprunt';
    final category = cats.where((c) => c.name == subName).firstOrNull;

    final now = DateTime.now();
    final tx = FinancialTransaction(
      id: 'tx_${now.microsecondsSinceEpoch}',
      spaceId: spaceId,
      accountId: account.id,
      // Prêt accordé → l'argent REVIENT (revenu) ;
      // Emprunt reçu → on REMBOURSE (dépense).
      kind: isLent ? 'INCOME' : 'EXPENSE',
      amount: money.minor,
      currency: loan.currency,
      status: 'POSTED',
      categoryId: category?.id,
      loanId: loan.id,
      occurredAt: _date,
      note: isLent
          ? 'Remboursement de ${loan.counterparty}'
          : 'Remboursement à ${loan.counterparty}',
      createdAt: now,
    );
    await db.saveTransaction(tx);

    // Solde atteint → prêt soldé automatiquement.
    final txs = await db.loanTransactions(loan.id);
    var repaid = 0;
    for (final t in txs) {
      final isReturn = isLent ? t.kind == 'INCOME' : t.kind == 'EXPENSE';
      if (isReturn && t.status == 'POSTED') repaid += t.amount;
    }
    if (repaid >= loan.principalAmount) {
      await (db.update(db.loans)..where((l) => l.id.equals(loan.id)))
          .write(const LoansCompanion(status: Value('SETTLED')));
      db.logOp('Loan', loan.id, 'UPDATE', {'status': 'SETTLED'});
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final accounts = ref.watch(accountsProvider(spaceId)).valueOrNull ?? [];
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    final isLent = widget.loan.direction == 'LENT';

    return Padding(
      padding: EdgeInsets.only(
          left: LHSpacing.screen,
          right: LHSpacing.screen,
          top: LHSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + LHSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Remboursement',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: LHSpacing.sm),
            Text(
              isLent
                  ? '${widget.loan.counterparty} vous rembourse — recette '
                      '« Épargne et dettes · Prêt accordé remboursé ».'
                  : 'Vous remboursez ${widget.loan.counterparty} — dépense '
                      '« Épargne et dettes · Remboursement d\'emprunt ».',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: LHSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: LHSpacing.md),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: LHColors.erreur)),
              ),
            LabeledField(
              label: 'Montant reçu (FCFA)',
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                    hintText: 'Ex. : ${widget.loan.principalAmount ~/ 100}',
                    prefixIcon: const Icon(Icons.payments_outlined)),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
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
                  child: Text(fmt.formatShort(_date)),
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Compte',
              child: AccountPickerField(
                value: _accountId,
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer le remboursement'),
            ),
          ],
        ),
      ),
    );
  }
}
