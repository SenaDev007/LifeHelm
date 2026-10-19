import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/features/finance/finance.dart' as fin;
import 'package:lifehelm/core/utils/money.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    await db.seedDemoData();
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    await db.setSetting('activeSpaceId', personal.id);
  });

  tearDown(() async => db.close());

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
