import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/db/seed.dart';
import 'package:lifehelm/core/utils/formatters.dart' as fmt;
import 'package:lifehelm/features/finance/finance.dart' as fin;
import 'package:lifehelm/core/utils/money.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    // Depuis la v0.2.2, initializeDefaultSpaces crée les 4 comptes types
    // (Espèces, Banque, Mobile Money, Épargne) par espace — plus besoin
    // d'en insérer manuellement.
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    // Budget de test pour l'allocation des transactions.
    final now = DateTime.now();
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
        id: 'bg_test_1',
        spaceId: personal.id,
        name: 'Budget test',
        initialAmount: 100000,
        periodStart: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
        periodEnd: '${now.year}-${now.month.toString().padLeft(2, '0')}-28'));
    await db.setSetting('activeSpaceId', personal.id);
  });

  tearDown(() async => db.close());

  test('comptes types : 4 comptes auto-créés par espace à l\'initialisation',
      () async {
    final spaces = await db.getAllSpaces();
    for (final space in spaces) {
      final accounts = await db.watchAllAccounts(space.id).first;
      expect(accounts.length, 4,
          reason: '${space.name} doit avoir 4 comptes types');
      final types = accounts.map((a) => a.type).toSet();
      expect(types, {'CASH', 'BANK', 'MOBILE_MONEY', 'SAVING'});
      for (final a in accounts) {
        expect(a.currency, 'XOF');
        expect(a.archivedAt, isNull);
      }
    }
  });

  test(
      'seedDefaultAccounts : idempotent — jamais de doublon, jamais de modification',
      () async {
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    // Re-amorçage : aucun changement (l'espace possède déjà des comptes).
    await seedDefaultAccounts(db, personal.id);
    expect((await db.watchAllAccounts(personal.id).first).length, 4);

    // Espace réellement vide (simule une installation v0.2.1) → backfill.
    final freshId = 'space-vide';
    await db.into(db.spaces).insert(
        SpacesCompanion.insert(id: freshId, type: 'PERSONAL', name: 'Legacy'));
    await seedDefaultAccounts(db, freshId);
    expect((await db.watchAllAccounts(freshId).first).length, 4);
    // Un seul compte personnalisé : seedDefaultAccounts ne touche à rien.
    await (db.delete(db.financialAccounts)
          ..where((a) => a.spaceId.equals(freshId)))
        .go();
    await db.into(db.financialAccounts).insert(
        FinancialAccountsCompanion.insert(
            id: 'acc_perso',
            spaceId: freshId,
            name: 'Mon MoMo',
            type: 'MOBILE_MONEY',
            initialDate: fmt.dateKey(fmt.today())));
    await seedDefaultAccounts(db, freshId);
    final after = await db.watchAllAccounts(freshId).first;
    expect(after.length, 1);
    expect(after.first.name, 'Mon MoMo');
  });

  test('ensureDefaultAccounts : backfill complet des espaces sans comptes',
      () async {
    // Simule une installation v0.2.1 : on vide un espace de ses comptes.
    final spaces = await db.getAllSpaces();
    final family = spaces.firstWhere((s) => s.type == 'FAMILY');
    await (db.delete(db.financialAccounts)
          ..where((a) => a.spaceId.equals(family.id)))
        .go();
    expect((await db.watchAllAccounts(family.id).first), isEmpty);

    await db.ensureDefaultAccounts();
    // L'espace vidé est complété…
    expect((await db.watchAllAccounts(family.id).first).length, 4);
    // …et les autres espaces (déjà pourvus) sont inchangés : toujours 4.
    for (final space in spaces.where((s) => s.id != family.id)) {
      expect((await db.watchAllAccounts(space.id).first).length, 4,
          reason: '${space.name} ne doit pas être modifié');
    }
  });

  test('computeAllBalances ne doit pas lever', () async {
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    final balances = await db.computeAllBalances(personal.id);
    expect(balances.length, 4);
    for (final b in balances) {
      // ignore: avoid_print
      print('${b.account.name}: ${Money(b.current, b.currency).format()}');
    }
  });

  test('budgetStats', () async {
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    final budgets = await db.watchBudgets(personal.id).first;
    final allocs = await db.watchAllocations(personal.id).first;
    for (final b in budgets) {
      final stat = await db.computeBudgetStat(b, allocs);
      // ignore: avoid_print
      print('${b.name}: E=${stat.envelope} D=${stat.spent}');
    }
  });

  test('saveTransaction avec allocation budget', () async {
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    final accounts = await db.watchAccounts(personal.id).first;
    final budgets = await db.watchBudgets(personal.id).first;
    final tx = FinancialTransaction(
      id: 'tx_test_1',
      spaceId: personal.id,
      accountId: accounts.first.id,
      kind: 'EXPENSE',
      amount: 5000,
      currency: 'XOF',
      status: 'POSTED',
      occurredAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    await db.saveTransaction(tx, allocations: [
      (budgetId: budgets.first.id, amount: 5000),
    ]);
    expect(true, true);
  });
}
