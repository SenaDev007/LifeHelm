import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart' as fmt;
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../shell/widgets.dart' show LhAppBar;

// ═══════════════════════════ LABELS MÉTIER (D05) ═══════════════════════════

String txKindLabel(String k) {
  switch (k) {
    case 'INCOME':
      return 'Revenu';
    case 'EXPENSE':
      return 'Dépense';
    case 'TRANSFER':
      return 'Transfert';
    case 'ADJUSTMENT':
      return 'Ajustement';
    default:
      return k;
  }
}

Color txKindColor(String k) {
  switch (k) {
    case 'INCOME':
      return LHColors.financePositif;
    case 'EXPENSE':
      return LHColors.financeNegatif;
    case 'TRANSFER':
      return LHColors.info;
    default:
      return LHColors.neutre;
  }
}

IconData txKindIcon(String k) {
  switch (k) {
    case 'INCOME':
      return Icons.south_west_rounded;
    case 'EXPENSE':
      return Icons.north_east_rounded;
    case 'TRANSFER':
      return Icons.swap_horiz_rounded;
    default:
      return Icons.tune_rounded;
  }
}

String txStatusLabel(String s) {
  switch (s) {
    case 'POSTED':
      return 'Comptabilisée';
    case 'PENDING':
      return 'En attente';
    case 'REVERSED':
      return 'Contrepassée';
    case 'VOIDED':
      return 'Annulée';
    default:
      return s;
  }
}

Color txStatusColor(String s) {
  switch (s) {
    case 'POSTED':
      return LHColors.financePositif;
    case 'PENDING':
      return LHColors.financeAttente;
    case 'REVERSED':
      return LHColors.info;
    default:
      return LHColors.neutre;
  }
}

// ═══════════════════════════ DONNÉES DÉRIVÉES ═══════════════════════════

/// Solde d'un compte : solde initial + entrées − sorties, transferts
/// et ajustements pris en compte, statuts POSTED uniquement (D05 §10.4).
class AccountBalance {
  AccountBalance(this.account, this.income, this.expense, this.transfersIn,
      this.transfersOut, this.adjustments);

  final FinancialAccount account;
  final int income; // kind INCOME
  final int expense; // kind EXPENSE
  final int transfersIn; // kind TRANSFER créditant ce compte
  final int transfersOut; // kind TRANSFER débitant ce compte
  final int adjustments; // kind ADJUSTMENT signé

  int get current =>
      account.initialAmount +
      income -
      expense +
      transfersIn -
      transfersOut +
      adjustments;

  Currency get currency => Currency.byCode(account.currency);
}

/// Statistiques de budget : E = B + A + R ; S = E − D ; conso = D / E (D05 §10.5).
class BudgetStat {
  BudgetStat(
      this.budget, this.envelope, this.spent, this.adjustments, this.carryover);

  final Budget budget;
  final int envelope; // E
  final int spent; // D (dépenses POSTED allouées)
  final int adjustments; // A
  final int carryover; // R

  int get available => envelope - spent; // S
  double get ratio => envelope > 0 ? spent / envelope : 0;
  bool get overThreshold =>
      envelope > 0 &&
      ratio >= 0.8; // seuil par défaut ; le seuil réel est lu dans les réglages
  Currency get currency => Currency.xof;
}

// ═══════════════════════════ REQUÊTES ═══════════════════════════

extension FinanceQueries on AppDatabase {
  Stream<List<FinancialAccount>> watchAccounts(String spaceId) {
    return (select(financialAccounts)
          ..where((a) => a.spaceId.equals(spaceId) & a.archivedAt.isNull())
          ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]))
        .watch();
  }

  /// Tous les comptes de l'espace, archivés compris (écran de gestion,
  /// libellés des opérations anciennes).
  Stream<List<FinancialAccount>> watchAllAccounts(String spaceId) {
    return (select(financialAccounts)
          ..where((a) => a.spaceId.equals(spaceId))
          ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]))
        .watch();
  }

  Stream<List<FinancialTransaction>> watchTransactions(String spaceId) {
    return (select(financialTransactions)
          ..where((t) => t.spaceId.equals(spaceId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  Stream<List<FinancialTransaction>> watchAccountTransactions(
      String accountId) {
    return (select(financialTransactions)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  Stream<List<FinancialCategory>> watchCategories(String spaceId) {
    return (select(financialCategories)
          ..where((c) => c.spaceId.equals(spaceId))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  /// Lecture unique des catégories (amorçage, dédoublonnage par slug).
  Future<List<FinancialCategory>> getCategoriesOnce(String spaceId) {
    return (select(financialCategories)
          ..where((c) => c.spaceId.equals(spaceId)))
        .get();
  }

  Stream<List<Budget>> watchBudgets(String spaceId) {
    return (select(budgets)
          ..where((b) => b.spaceId.equals(spaceId))
          ..orderBy([(b) => OrderingTerm(expression: b.periodStart)]))
        .watch();
  }

  Stream<List<FinancialDueItem>> watchDues(String spaceId) {
    return (select(financialDueItems)
          ..where((d) => d.spaceId.equals(spaceId))
          ..orderBy([(d) => OrderingTerm(expression: d.dueDate)]))
        .watch();
  }

  Stream<List<TransactionAllocation>> watchAllocations(String spaceId) {
    return (select(transactionAllocations).join([
      innerJoin(
          financialTransactions,
          financialTransactions.id
              .equalsExp(transactionAllocations.transactionId))
    ])
          ..where(financialTransactions.spaceId.equals(spaceId)))
        .watch()
        .map((rows) =>
            rows.map((r) => r.readTable(transactionAllocations)).toList());
  }

  Future<AccountBalance> computeBalance(FinancialAccount account) async {
    final txs = await (select(financialTransactions)
          ..where((t) =>
              t.accountId.equals(account.id) & t.status.equals('POSTED')))
        .get();
    var income = 0, expense = 0, tin = 0, tout = 0, adj = 0;
    for (final t in txs) {
      switch (t.kind) {
        case 'INCOME':
          income += t.amount;
          break;
        case 'EXPENSE':
          expense += t.amount;
          break;
        case 'TRANSFER':
          // Sens : un transfert débite le compte source et crédite le cible.
          final transfer = t.transferId == null
              ? null
              : await (select(transfers)
                    ..where((x) => x.id.equals(t.transferId!)))
                  .getSingleOrNull();
          if (transfer != null) {
            if (transfer.fromAccountId == account.id) {
              tout += t.amount;
            } else if (transfer.toAccountId == account.id) {
              tin += t.amount;
            }
          }
          break;
        case 'ADJUSTMENT':
          adj += t.amount;
          break;
      }
    }
    return AccountBalance(account, income, expense, tin, tout, adj);
  }

  Future<List<AccountBalance>> computeAllBalances(String spaceId) async {
    final accounts = await (select(financialAccounts)
          ..where((a) => a.spaceId.equals(spaceId) & a.archivedAt.isNull()))
        .get();
    final result = <AccountBalance>[];
    for (final a in accounts) {
      result.add(await computeBalance(a));
    }
    return result;
  }

  Future<BudgetStat> computeBudgetStat(
      Budget b, List<TransactionAllocation> allocations) async {
    final adjRows = await (select(budgetAdjustments)
          ..where((a) => a.budgetId.equals(b.id)))
        .get();
    final carryRows = await (select(budgetCarryovers)
          ..where((c) => c.budgetId.equals(b.id)))
        .get();
    final adjustments = adjRows.fold<int>(0, (s, a) => s + a.amount);
    final carryover = carryRows.fold<int>(0, (s, c) => s + c.amount);
    var spent = 0;
    for (final alloc in allocations.where((a) => a.budgetId == b.id)) {
      final tx = await (select(financialTransactions)
            ..where((t) =>
                t.id.equals(alloc.transactionId) &
                t.status.equals('POSTED') &
                t.kind.equals('EXPENSE')))
          .getSingleOrNull();
      if (tx != null) spent += alloc.amount;
    }
    return BudgetStat(b, b.initialAmount + adjustments + carryover, spent,
        adjustments, carryover);
  }

  /// Enregistre une transaction + allocations budgétaires éventuelles.
  /// Journalisée pour la sync ; alerte budget si seuil franchi (D05 §10.1-4).
  Future<void> saveTransaction(
    FinancialTransaction tx, {
    List<({String budgetId, int amount})> allocations = const [],
  }) async {
    await into(financialTransactions)
        .insert(tx, mode: InsertMode.insertOrReplace);
    // Les allocations sont réécrites : on journalise la disparition des
    // anciennes (DELETE) puis la création des nouvelles — la déduplication
    // par ressource du moteur de sync conserve l'état final.
    final previousAllocs = await (select(transactionAllocations)
          ..where((a) => a.transactionId.equals(tx.id)))
        .get();
    await (delete(transactionAllocations)
          ..where((a) => a.transactionId.equals(tx.id)))
        .go();
    for (final a in previousAllocs) {
      logOp('TransactionAllocation', a.id, 'DELETE', {});
    }
    for (final alloc in allocations) {
      final allocId = '${tx.id}_${alloc.budgetId}';
      await into(transactionAllocations).insert(TransactionAllocation(
          id: allocId,
          transactionId: tx.id,
          budgetId: alloc.budgetId,
          amount: alloc.amount));
      logOp('TransactionAllocation', allocId, 'CREATE',
          {'budgetId': alloc.budgetId, 'amount': alloc.amount});
    }
    logOp('FinancialTransaction', tx.id, 'CREATE_OR_UPDATE',
        {'kind': tx.kind, 'amount': tx.amount, 'currency': tx.currency});

    // Alerte de dépassement de budget (seuil réglable, défaut 80 %).
    if (tx.kind == 'EXPENSE' && tx.status == 'POSTED') {
      final threshold =
          (double.tryParse(await getSetting('budgetAlertThreshold') ?? '') ??
              0.8);
      final spaceBudgets = await (select(budgets)
            ..where((b) => b.spaceId.equals(tx.spaceId)))
          .get();
      for (final b in spaceBudgets) {
        final stat = await computeBudgetStat(
            b, await watchAllocations(tx.spaceId).first);
        if (stat.envelope > 0 && stat.ratio >= threshold) {
          await pushNotification(
            spaceId: tx.spaceId,
            category: 'FINANCE',
            priority: stat.ratio >= 1.0 ? 'CRITICAL' : 'IMPORTANT',
            title: 'Budget à ${(100 * stat.ratio).round()} %',
            body:
                '« ${b.name} » a consommé ${(100 * stat.ratio).round()} % de son enveloppe.',
            resourceType: 'BUDGET',
            resourceId: b.id,
            dedupKey: 'budget-alert-${b.id}-${(100 * stat.ratio).round()}',
          );
        }
      }
    }
  }

  /// Transfert interne : ni revenu ni dépense ; deux écritures TRANSFER
  /// liées + frais en dépense distincte (D05 §10.4).
  Future<void> saveTransfer({
    required String spaceId,
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required String fromCurrency,
    required int toAmount,
    required String toCurrency,
    double rate = 1.0,
    int? fee,
    DateTime? occurredAt,
  }) async {
    final now = occurredAt ?? DateTime.now();
    final transferId = 'trf_${now.microsecondsSinceEpoch}';
    await into(transfers).insert(Transfer(
        id: transferId,
        spaceId: spaceId,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        fromAmount: fromAmount,
        fromCurrency: fromCurrency,
        toAmount: toAmount,
        toCurrency: toCurrency,
        rate: rate,
        fee: fee,
        occurredAt: now));
    await into(financialTransactions).insert(FinancialTransaction(
        id: '${transferId}_out',
        spaceId: spaceId,
        accountId: fromAccountId,
        kind: 'TRANSFER',
        amount: fromAmount,
        currency: fromCurrency,
        status: 'POSTED',
        transferId: transferId,
        rateToXof: fromCurrency == 'XOF' ? 1.0 : rate,
        occurredAt: now,
        note: 'Transfert sortant',
        createdAt: now));
    await into(financialTransactions).insert(FinancialTransaction(
        id: '${transferId}_in',
        spaceId: spaceId,
        accountId: toAccountId,
        kind: 'TRANSFER',
        amount: toAmount,
        currency: toCurrency,
        status: 'POSTED',
        transferId: transferId,
        rateToXof: toCurrency == 'XOF' ? 1.0 : rate,
        occurredAt: now,
        createdAt: now));
    if (fee != null && fee > 0) {
      await into(financialTransactions).insert(FinancialTransaction(
          id: '${transferId}_fee',
          spaceId: spaceId,
          accountId: fromAccountId,
          kind: 'EXPENSE',
          amount: fee,
          currency: fromCurrency,
          status: 'POSTED',
          transferId: transferId,
          occurredAt: now,
          note: 'Frais de transfert',
          createdAt: now));
    }
    logOp('Transfer', transferId, 'CREATE', {
      'from': fromAmount,
      'to': toAmount,
      'rate': rate,
      'fee': fee,
    });
  }

  /// Rapprochement : l'écart est présenté, la correction est explicite
  /// et séparée (D05 §10.6).
  Future<void> saveReconciliation({
    required FinancialAccount account,
    required int observedAmount,
    String? note,
  }) async {
    final balance = await computeBalance(account);
    final diff = observedAmount - balance.current;
    final now = DateTime.now();
    final reconId = 'rec_${now.microsecondsSinceEpoch}';
    await into(accountReconciliations).insert(AccountReconciliation(
        id: reconId,
        accountId: account.id,
        recordedAmount: balance.current,
        observedAmount: observedAmount,
        observedAt: now,
        note: note));

    if (diff != 0) {
      final txId = 'adj_${now.microsecondsSinceEpoch}';
      await into(financialTransactions).insert(FinancialTransaction(
          id: txId,
          spaceId: account.spaceId,
          accountId: account.id,
          kind: 'ADJUSTMENT',
          amount: diff.abs(),
          currency: account.currency,
          status: 'POSTED',
          occurredAt: now,
          note: 'Écart de rapprochement${note != null ? ' — $note' : ''}',
          createdAt: now));
      await (update(accountReconciliations)..where((r) => r.id.equals(reconId)))
          .write(AccountReconciliationsCompanion(
              adjustmentTransactionId: Value(txId)));
      logOp('FinancialTransaction', txId, 'CREATE',
          {'kind': 'ADJUSTMENT', 'amount': diff.abs()});
    }
    logOp('AccountReconciliation', reconId, 'CREATE',
        {'diff': diff, 'account': account.name});
  }

  /// Règle une échéance : crée la transaction réelle (ne touche pas le
  /// solde avant — D05 §10.6) et marque l'échéance PAID.
  Future<void> payDue(FinancialDueItem due, FinancialAccount account) async {
    final now = DateTime.now();
    final txId = 'tx_${now.microsecondsSinceEpoch}';
    await into(financialTransactions).insert(FinancialTransaction(
        id: txId,
        spaceId: due.spaceId,
        accountId: account.id,
        kind: 'EXPENSE',
        amount: due.expectedAmount,
        currency: due.currency,
        status: 'POSTED',
        categoryId: due.categoryId,
        occurredAt: now,
        note: 'Échéance : ${due.label}',
        createdAt: now));
    await (update(financialDueItems)..where((d) => d.id.equals(due.id))).write(
        FinancialDueItemsCompanion(
            status: const Value('PAID'), paidTransactionId: Value(txId)));
    logOp('FinancialDueItem', due.id, 'UPDATE', {'status': 'PAID', 'tx': txId});
  }

  Future<void> deleteTransaction(FinancialTransaction t) async {
    await (delete(transactionAllocations)
          ..where((a) => a.transactionId.equals(t.id)))
        .go();
    await (delete(financialTransactions)..where((x) => x.id.equals(t.id))).go();
    logOp('FinancialTransaction', t.id, 'DELETE', {'kind': t.kind});
  }

  Future<FinancialAccount?> getAccount(String id) =>
      (select(financialAccounts)..where((a) => a.id.equals(id)))
          .getSingleOrNull();
}

// ═══════════════════════════ PROVIDERS ═══════════════════════════

final accountsProvider = StreamProvider.family<List<FinancialAccount>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchAccounts(spaceId));

/// Tous les comptes (archivés compris) — écran de gestion des comptes.
final allAccountsProvider =
    StreamProvider.family<List<FinancialAccount>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchAllAccounts(spaceId));

final transactionsProvider =
    StreamProvider.family<List<FinancialTransaction>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchTransactions(spaceId));

final accountTransactionsProvider =
    StreamProvider.family<List<FinancialTransaction>, String>(
        (ref, accountId) =>
            ref.watch(dbProvider).watchAccountTransactions(accountId));

final categoriesProvider =
    StreamProvider.family<List<FinancialCategory>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchCategories(spaceId));

final budgetsRawProvider = StreamProvider.family<List<Budget>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchBudgets(spaceId));

final duesProvider = StreamProvider.family<List<FinancialDueItem>, String>(
    (ref, spaceId) => ref.watch(dbProvider).watchDues(spaceId));

final allocationsProvider =
    StreamProvider.family<List<TransactionAllocation>, String>(
        (ref, spaceId) => ref.watch(dbProvider).watchAllocations(spaceId));

/// Soldes calculés de tous les comptes de l'espace actif.
final balancesProvider =
    StreamProvider.family<List<AccountBalance>, String>((ref, spaceId) async* {
  // Réémet à chaque changement de comptes ou de transactions.
  ref.watch(accountsProvider(spaceId));
  ref.watch(transactionsProvider(spaceId));
  final db = ref.watch(dbProvider);
  // Petite temporisation de regroupement : Drift émet plusieurs évènements.
  await Future.delayed(const Duration(milliseconds: 50));
  yield await db.computeAllBalances(spaceId);
});

/// Statistiques budgétaires enrichies.
final budgetStatsProvider =
    StreamProvider.family<List<BudgetStat>, String>((ref, spaceId) async* {
  ref.watch(budgetsRawProvider(spaceId));
  final allocations = ref.watch(allocationsProvider(spaceId)).valueOrNull ?? [];
  final db = ref.watch(dbProvider);
  await Future.delayed(const Duration(milliseconds: 50));
  final budgets = await db.watchBudgets(spaceId).first;
  final stats = <BudgetStat>[];
  for (final b in budgets) {
    stats.add(await db.computeBudgetStat(b, allocations));
  }
  yield stats;
});

// ═══════════════════════════ ÉCRAN : FINANCES ═══════════════════════════

/// Onglet Finances — patrimoine consolidé, comptes, budgets, échéances (D05).
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final balancesAsync = ref.watch(balancesProvider(spaceId));
    final txsAsync = ref.watch(transactionsProvider(spaceId));
    final budgetStatsAsync = ref.watch(budgetStatsProvider(spaceId));
    final duesAsync = ref.watch(duesProvider(spaceId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: LhAppBar(title: 'Finances'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transaction/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle opération'),
      ),
      body: balancesAsync.maybeWhen(
        loading: () => const Center(child: CircularProgressIndicator()),
        orElse: () => balancesAsync.value == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(balancesProvider(spaceId)),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    _ConsolidatedCard(balances: balancesAsync.value!),
                    _QuickActionsRow(),
                    SectionHeader('Budgets du mois',
                        inset: LHSpacing.screen,
                        overline: 'Pilotage',
                        action: TextButton(
                            onPressed: () => context.push('/budgets'),
                            child: const Text('Tout voir'))),
                    _BudgetsPreview(stats: budgetStatsAsync.value ?? []),
                    SectionHeader('Échéances',
                        inset: LHSpacing.screen,
                        overline: 'À venir',
                        action: TextButton(
                            onPressed: () => context.push('/dues'),
                            child: const Text('Tout voir'))),
                    _DuesPreview(dues: duesAsync.value ?? []),
                    SectionHeader('Dernières opérations',
                        inset: LHSpacing.screen, overline: 'Mouvements'),
                    ..._recentTx(context, ref, txsAsync.value ?? []),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: LHSpacing.screen),
                      child: Center(
                        child: Text(
                          'Les conversions entre devises sont explicites et conservent leur taux.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _recentTx(
      BuildContext context, WidgetRef ref, List<FinancialTransaction> txs) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    // Tous comptes, archivés compris : le libellé des opérations anciennes
    // reste correct même après archivage du compte concerné.
    final accounts = ref.watch(allAccountsProvider(spaceId)).valueOrNull ?? [];
    final categories = ref.watch(categoriesProvider(spaceId)).valueOrNull ?? [];
    return txs
        .take(8)
        .map((t) =>
            _TransactionTile(tx: t, accounts: accounts, categories: categories))
        .toList();
  }
}

class _ConsolidatedCard extends StatelessWidget {
  const _ConsolidatedCard({required this.balances});
  final List<AccountBalance> balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Consolidation : conversion explicite vers XOF (taux indicatifs affichés).
    var totalXof = 0;
    final others = <AccountBalance>[];
    for (final b in balances) {
      totalXof += b.currency.code == 'XOF'
          ? b.current
          : b.current * (Currency.tauxVersXof[b.currency.code] ?? 1).round();
      if (b.currency.code != 'XOF') others.add(b);
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(LHSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.brightness == Brightness.dark
              ? [const Color(0xFF1E1B12), const Color(0xFF14251E)]
              : [const Color(0xFFFFF4D6), const Color(0xFFEDF7F2)],
        ),
        borderRadius: BorderRadius.circular(LHRadius.xl),
        border: Border.all(
            color: theme.brightness == Brightness.dark
                ? LHColors.or.withValues(alpha: 0.25)
                : LHColors.orDeep.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.savings_outlined,
              size: 18,
              color: theme.brightness == Brightness.dark
                  ? LHColors.or
                  : LHColors.orDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text('PATRIMOINE CONSOLIDÉ',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: theme.brightness == Brightness.dark
                        ? LHColors.or
                        : LHColors.orDeep)),
          ),
          TextButton(
            onPressed: () => context.push('/accounts'),
            child: const Text('Gérer'),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          Money(totalXof, Currency.xof).format(),
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '≈ équivalent XOF — taux indicatifs pour ${others.map((b) => b.currency.code).join(', ')}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: LHSpacing.lg),
        // Répartition par compte
        ...balances.map((b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _AccountLine(balance: b),
            )),
      ]),
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.balance});
  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = balance;
    return LHCard(
      onTap: () => context.push('/account/${b.account.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accountTypeColor(b.account.type, context)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(LHRadius.md),
          ),
          child: Icon(
            b.account.type == 'CASH'
                ? Icons.payments_outlined
                : b.account.type == 'MOBILE_MONEY'
                    ? Icons.phone_android_outlined
                    : b.account.type == 'SAVING'
                        ? Icons.savings_outlined
                        : Icons.account_balance_outlined,
            size: 20,
            color: accountTypeColor(b.account.type, context),
          ),
        ),
        const SizedBox(width: LHSpacing.md),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.account.name, style: theme.textTheme.titleSmall),
            Text(
              '${accountTypeLabel(b.account.type)} · ${b.currency.code}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Money(b.current, b.currency).format(withCode: false),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(b.currency.code,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const Icon(Icons.chevron_right_rounded,
            size: 20, color: LHColors.neutre),
      ]),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: _action(context, Icons.north_east_rounded, 'Dépense',
                  () => context.push('/transaction/new?type=expense'))),
          const SizedBox(width: 10),
          Expanded(
              child: _action(context, Icons.south_west_rounded, 'Revenu',
                  () => context.push('/transaction/new?type=income'))),
          const SizedBox(width: 10),
          Expanded(
              child: _action(context, Icons.swap_horiz_rounded, 'Transfert',
                  () => context.push('/transaction/new?type=transfer'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _action(context, Icons.handshake_outlined,
                  'Prêts & emprunts', () => context.push('/loans'))),
          const SizedBox(width: 10),
          Expanded(
              child: _action(context, Icons.insights_outlined, 'Statistiques',
                  () => context.push('/statistics'))),
          const SizedBox(width: 10),
          Expanded(
              child: _action(context, Icons.event_repeat_outlined, 'Échéances',
                  () => context.push('/dues'))),
        ]),
      ]),
    );
  }

  Widget _action(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LHRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(LHRadius.lg),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.7)),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: LHColors.or),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelMedium),
        ]),
      ),
    );
  }
}

class _BudgetsPreview extends StatelessWidget {
  const _BudgetsPreview({required this.stats});
  final List<BudgetStat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LHCard(
          onTap: () => context.push('/budgets'),
          child: Row(children: [
            Icon(Icons.donut_small_outlined,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Créez votre premier budget mensuel',
                    style: theme.textTheme.bodyMedium)),
          ]),
        ),
      );
    }
    return Column(children: [
      for (final s in stats.take(3))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: LHCard(
            onTap: () => context.push('/budgets'),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child:
                        Text(s.budget.name, style: theme.textTheme.titleSmall)),
                Text(
                  s.ratio >= 1 ? 'Dépassé' : '${(100 * s.ratio).round()} %',
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: s.ratio >= 1
                          ? LHColors.erreur
                          : s.ratio >= 0.8
                              ? LHColors.alerte
                              : LHColors.emeraudeClair),
                ),
              ]),
              const SizedBox(height: 8),
              BudgetBar(ratio: s.ratio),
              const SizedBox(height: 6),
              Text(
                '${Money(s.spent, s.currency).format(withCode: false)} dépensés · reste ${Money(s.available, s.currency).format(withCode: false)} FCFA',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _DuesPreview extends StatelessWidget {
  const _DuesPreview({required this.dues});
  final List<FinancialDueItem> dues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = dues.where((d) => d.status == 'OPEN').toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (open.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LHCard(
          child: Row(children: [
            const Icon(Icons.event_available, color: LHColors.emeraudeClair),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Aucune échéance à venir',
                    style: theme.textTheme.bodyMedium)),
          ]),
        ),
      );
    }
    final todayKey = fmt.dateKey(fmt.today());
    return Column(children: [
      for (final d in open.take(4))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: LHCard(
            onTap: () => context.push('/dues'),
            accent: d.dueDate.compareTo(todayKey) < 0
                ? LHColors.erreur
                : LHColors.or,
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label, style: theme.textTheme.titleSmall),
                      Text(
                        d.dueDate.compareTo(todayKey) < 0
                            ? 'En retard — prévu le ${fmt.formatShort(fmt.parseKey(d.dueDate))}'
                            : 'Prévu le ${fmt.formatLong(fmt.parseKey(d.dueDate))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: d.dueDate.compareTo(todayKey) < 0
                                ? LHColors.erreur
                                : theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
              ),
              Text(
                Money(d.expectedAmount, Currency.byCode(d.currency))
                    .format(withCode: false),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(
      {required this.tx, required this.accounts, required this.categories});

  final FinancialTransaction tx;
  final List<FinancialAccount> accounts;
  final List<FinancialCategory> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = accounts.where((a) => a.id == tx.accountId).firstOrNull;
    final category = tx.categoryId == null
        ? null
        : categories.where((c) => c.id == tx.categoryId).firstOrNull;
    final money = Money(tx.amount, Currency.byCode(tx.currency));
    final sign = tx.kind == 'INCOME'
        ? '+'
        : tx.kind == 'EXPENSE' || tx.kind == 'ADJUSTMENT'
            ? '−'
            : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LHRadius.lg)),
        tileColor: theme.colorScheme.surface,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: txKindColor(tx.kind).withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child:
              Icon(txKindIcon(tx.kind), size: 18, color: txKindColor(tx.kind)),
        ),
        title: Text(tx.note?.isNotEmpty == true
            ? tx.note!
            : category?.name ?? txKindLabel(tx.kind)),
        subtitle: Text(
          '${account?.name ?? ''} · ${fmt.formatMedium(tx.occurredAt)}'
          '${tx.status != 'POSTED' ? ' · ${txStatusLabel(tx.status)}' : ''}',
          style: TextStyle(
              fontSize: 12,
              color: tx.status != 'POSTED'
                  ? LHColors.financeAttente
                  : theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Text(
          '$sign${money.format(withCode: false)}',
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: tx.kind == 'INCOME'
                  ? LHColors.financePositif
                  : tx.kind == 'EXPENSE'
                      ? LHColors.financeNegatif
                      : LHColors.info),
        ),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : COMPTE ═══════════════════════════

/// Détail d'un compte : solde, historique par mois, rapprochement (D05 §10.6).
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txsAsync = ref.watch(accountTransactionsProvider(widget.id));
    final balances =
        ref.watch(balancesProvider(ref.watch(activeSpaceIdProvider)));
    final balance = balances.valueOrNull
        ?.where((b) => b.account.id == widget.id)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(balance?.account.name ?? 'Compte'),
        actions: [
          if (balance != null)
            IconButton(
              tooltip: 'Modifier le compte',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showAccountEditSheet(context, ref, existing: balance.account),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transaction/new?account=${widget.id}'),
        icon: const Icon(Icons.add),
        label: const Text('Opération'),
      ),
      body: Column(children: [
        if (balance != null) _header(context, balance),
        Expanded(
          child: txsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                EmptyState(icon: Icons.error_outline, message: '$e'),
            data: (txs) {
              if (txs.isEmpty) {
                return const EmptyState(
                    illustration: 'assets/illustrations/finance.png',
                    icon: Icons.receipt_long_outlined,
                    message: 'Aucune opération',
                    hint: 'Enregistrez un revenu ou une dépense.');
              }
              // Regroupement par mois.
              final groups = <String, List<FinancialTransaction>>{};
              for (final t in txs) {
                final k = fmt.formatMonthYear(t.occurredAt);
                (groups[k] ??= []).add(t);
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: groups.length,
                itemBuilder: (context, i) {
                  final entry = groups.entries.elementAt(i);
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Text(entry.key,
                              style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        ...entry.value.map((t) => Dismissible(
                              key: ValueKey(t.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: LHColors.erreur,
                                child: const Icon(Icons.delete_outline,
                                    color: Colors.white),
                              ),
                              confirmDismiss: (_) => lhConfirm(context,
                                  title: 'Supprimer l\'opération ?',
                                  message:
                                      'Montant : ${Money(t.amount, Currency.byCode(t.currency)).format()}. La suppression est journalisée pour la synchronisation.',
                                  confirmLabel: 'Supprimer',
                                  destructive: true),
                              onDismissed: (_) =>
                                  ref.read(dbProvider).deleteTransaction(t),
                              child: _TransactionTile(
                                  tx: t,
                                  accounts: balance != null
                                      ? [balance.account]
                                      : const [],
                                  categories: const []),
                            )),
                      ]);
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, AccountBalance balance) {
    final theme = Theme.of(context);
    final b = balance;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(LHSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(LHRadius.xl),
        border: Border.all(
            color: accountTypeColor(b.account.type, context)
                .withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Text(accountTypeLabel(b.account.type).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: accountTypeColor(b.account.type, context))),
        const SizedBox(height: 4),
        Text(Money(b.current, b.currency).format(),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: LHSpacing.md),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Entrées',
                  value:
                      '+${Money(b.income, b.currency).format(withCode: false)}',
                  color: LHColors.financePositif,
                  icon: Icons.south_west_rounded)),
          Expanded(
              child: StatTile(
                  label: 'Sorties',
                  value:
                      '−${Money(b.expense, b.currency).format(withCode: false)}',
                  color: LHColors.financeNegatif,
                  icon: Icons.north_east_rounded)),
        ]),
        const SizedBox(height: LHSpacing.md),
        OutlinedButton.icon(
          onPressed: () => _reconcileDialog(context, b),
          icon: const Icon(Icons.balance_outlined, size: 18),
          label: const Text('Rapprocher le compte'),
        ),
      ]),
    );
  }

  Future<void> _reconcileDialog(BuildContext context, AccountBalance b) async {
    final ctrl = TextEditingController();
    final db = ref.read(dbProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rapprochement'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Solde enregistré : ${Money(b.current, b.currency).format()}\n'
            'Saisissez le solde réellement constaté — l\'écart sera présenté, '
            'jamais corrigé automatiquement.',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                hintText: 'Solde constaté (${b.currency.symbol})'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final m = Money.tryParse(ctrl.text, b.currency);
              if (m == null) return;
              await db.saveReconciliation(
                  account: b.account, observedAmount: m.minor);
              if (ctx.mounted) Navigator.pop(ctx);
              final diff = m.minor - b.current;
              if (context.mounted) {
                lhToast(
                    context,
                    diff == 0
                        ? 'Compte rapproché : aucun écart.'
                        : 'Écart de ${Money(diff.abs(), b.currency).format()} ${diff > 0 ? 'en faveur du compte' : 'en moins'} — ajustement enregistré.');
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ SÉLECTEUR DE COMPTE ═══════════════════════════

/// Sélecteur de compte avec création intégrée : liste les comptes actifs de
/// l'espace et propose « Nouveau compte… » directement dans le menu. Si aucun
/// compte n'existe, affiche un bouton de création plein cadre au lieu d'un
/// menu vide et grisé (issue v0.2.1 : sélecteurs de compte inutilisables).
class AccountPickerField extends ConsumerWidget {
  const AccountPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Compte',
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  /// Valeur sentinel du menu déroulant pour « créer un compte ».
  static const String kNewAccount = '__new_account__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spaceId = ref.watch(activeSpaceIdProvider);
    final accounts = ref.watch(accountsProvider(spaceId)).valueOrNull ?? [];

    // Aucun compte : le menu serait vide et grisé — création plein cadre.
    if (accounts.isEmpty) {
      return LabeledField(
        label: label,
        child: OutlinedButton.icon(
          onPressed: () async {
            final acc = await showAccountEditSheet(context, ref);
            if (acc != null) onChanged(acc.id);
          },
          icon: const Icon(Icons.add_card_outlined),
          label: const Text('Créer un premier compte'),
        ),
      );
    }

    final selected =
        accounts.any((a) => a.id == value) ? value : accounts.first.id;
    final accent =
        theme.brightness == Brightness.dark ? LHColors.or : LHColors.orDeep;
    return LabeledField(
      label: label,
      child: DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        items: [
          for (final a in accounts)
            DropdownMenuItem(
              value: a.id,
              child: Row(children: [
                Icon(accountTypeIcon(a.type),
                    size: 18, color: accountTypeColor(a.type, context)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${a.name} (${a.currency})',
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          DropdownMenuItem(
            value: kNewAccount,
            child: Row(children: [
              Icon(Icons.add, size: 18, color: accent),
              const SizedBox(width: 8),
              Text('Nouveau compte…',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: accent, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
        onChanged: (v) async {
          if (v == kNewAccount) {
            final acc = await showAccountEditSheet(context, ref);
            if (acc != null) onChanged(acc.id);
            return;
          }
          onChanged(v);
        },
      ),
    );
  }
}

// ═══════════════════════════ FEUILLE : COMPTE ═══════════════════════════

const List<(String, String)> kAccountTypes = [
  ('CASH', 'Espèces'),
  ('BANK', 'Compte bancaire'),
  ('MOBILE_MONEY', 'Mobile Money'),
  ('SAVING', 'Épargne'),
  ('CUSTOM', 'Personnalisé'),
];

/// Feuille de création/édition d'un compte financier (D05 §10.2) : nom, type,
/// devise, solde initial, note ; archivage/réactivation en édition.
/// Retourne le compte créé/modifié, ou null si annulation.
Future<FinancialAccount?> showAccountEditSheet(
    BuildContext context, WidgetRef ref,
    {FinancialAccount? existing}) {
  return showModalBottomSheet<FinancialAccount>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AccountEditSheet(existing: existing),
  );
}

class _AccountEditSheet extends ConsumerStatefulWidget {
  const _AccountEditSheet({this.existing});

  final FinancialAccount? existing;

  @override
  ConsumerState<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<_AccountEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late String _type;
  late Currency _currency;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _type = e?.type ?? 'CASH';
    _currency = e == null ? Currency.xof : Currency.byCode(e.currency);
    _amountCtrl = TextEditingController(
        text: e == null || e.initialAmount == 0
            ? ''
            : Money(e.initialAmount, _currency).format(withCode: false));
    _noteCtrl = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Donnez un nom au compte.');
      return;
    }
    final money = _amountCtrl.text.trim().isEmpty
        ? Money.zero(_currency)
        : Money.tryParse(_amountCtrl.text, _currency);
    if (money == null) {
      setState(() => _error = 'Solde initial invalide.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = ref.read(dbProvider);
    final spaceId = ref.read(activeSpaceIdProvider);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    if (!_isEdit) {
      final id = const Uuid().v4();
      await db.into(db.financialAccounts).insert(
          FinancialAccountsCompanion.insert(
              id: id,
              spaceId: spaceId,
              name: name,
              type: _type,
              currency: Value(_currency.code),
              initialAmount: Value(money.minor),
              initialDate: fmt.dateKey(fmt.today()),
              note: Value(note)));
      db.logOp('FinancialAccount', id, 'CREATE', {'name': name, 'type': _type});
      final acc = await db.getAccount(id);
      if (mounted) Navigator.pop(context, acc);
      return;
    }
    final e = widget.existing!;
    await (db.update(db.financialAccounts)..where((a) => a.id.equals(e.id)))
        .write(FinancialAccountsCompanion(
            name: Value(name),
            type: Value(_type),
            currency: Value(_currency.code),
            initialAmount: Value(money.minor),
            note: Value(note)));
    db.logOp('FinancialAccount', e.id, 'UPDATE', {'name': name, 'type': _type});
    final acc = await db.getAccount(e.id);
    if (mounted) Navigator.pop(context, acc);
  }

  Future<void> _toggleArchive() async {
    final e = widget.existing!;
    final archiving = e.archivedAt == null;
    if (archiving) {
      final ok = await lhConfirm(
        context,
        title: 'Archiver « ${e.name} » ?',
        message: 'Le compte quitte les sélecteurs et le patrimoine consolidé, '
            'mais son historique est conservé et aucune opération n\'est '
            'supprimée. Il pourra être réactivé à tout moment.',
        confirmLabel: 'Archiver',
        destructive: true,
      );
      if (!ok) return;
    }
    final db = ref.read(dbProvider);
    await (db.update(db.financialAccounts)..where((a) => a.id.equals(e.id)))
        .write(FinancialAccountsCompanion(
            archivedAt: Value(archiving ? DateTime.now() : null)));
    db.logOp('FinancialAccount', e.id, 'UPDATE', {'archived': archiving});
    final acc = await db.getAccount(e.id);
    if (mounted) Navigator.pop(context, acc);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.existing;
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
            Text(
              _isEdit ? 'Modifier le compte' : 'Nouveau compte',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: LHSpacing.sm),
            Text(
              _isEdit
                  ? 'Les opérations existantes conservent leur devise d\'origine.'
                  : 'Quatre comptes types ont été créés automatiquement — '
                      'ajoutez ici vos comptes réels (MoMo, banque…).',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: LHSpacing.lg),
            LabeledField(
              label: 'Nom du compte',
              child: TextField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Ex. : MoMo MTN, Compte BOA, Tirelire…'),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Type',
              child: DropdownButtonFormField<String>(
                value:
                    kAccountTypes.any((t) => t.$1 == _type) ? _type : 'CUSTOM',
                isExpanded: true,
                items: [
                  for (final (code, label) in kAccountTypes)
                    DropdownMenuItem(
                        value: code,
                        child: Row(children: [
                          Icon(accountTypeIcon(code),
                              size: 18, color: accountTypeColor(code, context)),
                          const SizedBox(width: 8),
                          Text(label),
                        ])),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'CUSTOM'),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Devise',
              child: DropdownButtonFormField<Currency>(
                value: _currency,
                isExpanded: true,
                items: [
                  for (final c in Currency.all)
                    DropdownMenuItem(
                        value: c, child: Text('${c.label} (${c.code})')),
                ],
                onChanged: (v) => setState(() => _currency = v ?? Currency.xof),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Solde initial',
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '0 ${_currency.symbol}',
                  helperText: _isEdit
                      ? 'Point de départ du solde, compté depuis le '
                          '${fmt.formatShort(fmt.parseKey(e!.initialDate))}.'
                      : 'Argent présent sur le compte aujourd\'hui — '
                          'peut rester vide.',
                ),
              ),
            ),
            const SizedBox(height: LHSpacing.md),
            LabeledField(
              label: 'Note (facultatif)',
              child: TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                    hintText: 'Ex. : compte principal, épargne projet…'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: LHSpacing.md),
              Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: LHColors.erreur)),
            ],
            const SizedBox(height: LHSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Enregistrer' : 'Créer le compte'),
            ),
            if (_isEdit) ...[
              const SizedBox(height: LHSpacing.sm),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: e!.archivedAt == null
                        ? LHColors.erreur
                        : LHColors.emeraudeClair),
                onPressed: _toggleArchive,
                icon: Icon(e.archivedAt == null
                    ? Icons.archive_outlined
                    : Icons.restore_from_trash_outlined),
                label: Text(e.archivedAt == null
                    ? 'Archiver le compte'
                    : 'Réactiver le compte'),
              ),
            ],
            const SizedBox(height: LHSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ ÉCRAN : GESTION DES COMPTES ═══════════════════════════

/// Gestion des comptes financiers de l'espace : liste avec soldes, création,
/// modification, archivage (D05 §10.2). Accessible depuis Finances → « Gérer ».
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = ref.watch(activeSpaceIdProvider);
    final accountsAsync = ref.watch(allAccountsProvider(spaceId));
    final balances = ref.watch(balancesProvider(spaceId)).valueOrNull ?? [];

    return Scaffold(
      appBar: LhAppBar(title: 'Comptes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountEditSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau compte'),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            EmptyState(icon: Icons.error_outline, message: '$err'),
        data: (all) {
          final active = all.where((a) => a.archivedAt == null).toList();
          final archived = all.where((a) => a.archivedAt != null).toList();
          if (all.isEmpty) {
            return const EmptyState(
              illustration: 'assets/illustrations/finance.png',
              icon: Icons.account_balance_wallet_outlined,
              message: 'Aucun compte',
              hint: 'Créez un compte pour enregistrer vos opérations.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SectionHeader('Comptes actifs',
                  inset: LHSpacing.screen, overline: '${active.length}'),
              for (final a in active)
                _manageTile(context, ref, a,
                    balances.where((b) => b.account.id == a.id).firstOrNull,
                    archived: false),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: LHSpacing.lg),
                SectionHeader('Archivés',
                    inset: LHSpacing.screen, overline: '${archived.length}'),
                for (final a in archived)
                  _manageTile(context, ref, a, null, archived: true),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _manageTile(BuildContext context, WidgetRef ref, FinancialAccount a,
      AccountBalance? balance,
      {required bool archived}) {
    final theme = Theme.of(context);
    final color = accountTypeColor(a.type, context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LHCard(
        onTap: () => showAccountEditSheet(context, ref, existing: a),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(LHRadius.md),
            ),
            child: Icon(accountTypeIcon(a.type), size: 20, color: color),
          ),
          const SizedBox(width: LHSpacing.md),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: theme.textTheme.titleSmall),
              Text(
                archived
                    ? 'Archivé · ${accountTypeLabel(a.type)}'
                    : '${accountTypeLabel(a.type)} · ${a.currency}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
          if (balance != null)
            Text(
              Money(balance.current, balance.currency).format(withCode: false),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: LHColors.neutre),
        ]),
      ),
    );
  }
}
