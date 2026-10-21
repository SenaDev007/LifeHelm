import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/db/seed.dart';
import 'package:lifehelm/core/taxonomy.dart';
import 'package:lifehelm/core/utils/money.dart';
import 'package:lifehelm/features/finance/finance.dart';

/// Tests de la taxonomie financière exhaustive, du module Prêts & emprunts,
/// de la planification budgétaire multi-mois et du profil local.
void main() {
  late AppDatabase db;
  late String spaceId;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    final spaces = await db.getAllSpaces();
    spaceId = spaces.firstWhere((s) => s.type == 'PERSONAL').id;
  });

  tearDown(() async => db.close());

  Future<List<FinancialCategory>> categories() =>
      (db.select(db.financialCategories)
            ..where((c) => c.spaceId.equals(spaceId)))
          .get();

  group('taxonomie exhaustive (recettes & dépenses)', () {
    test('amorce toutes les catégories et sous-catégories officielles', () async {
      final cats = await categories();
      final parents = cats.where((c) => c.parentId == null).toList();
      final incomeParents = parents.where((c) => c.kind == 'INCOME');
      final expenseParents = parents.where((c) => c.kind == 'EXPENSE');

      // 5 familles de recettes et 16 familles de dépenses.
      expect(incomeParents.length, taxonomyIncome.length,
          reason: 'toutes les familles de recettes sont amorcées');
      expect(expenseParents.length, taxonomyExpense.length,
          reason: 'toutes les familles de dépenses sont amorcées');

      // Chaque famille embarque ses sous-catégories.
      final expectedSubs = [
        for (final n in [...taxonomyIncome, ...taxonomyExpense]) ...n.subs
      ].length;
      final actualSubs = cats.where((c) => c.parentId != null).length;
      expect(actualSubs, expectedSubs);

      // « Épargne et dettes » existe avec sa sous-catégorie « Prêt accordé ».
      final epargne =
          cats.where((c) => c.slug == 'exp-epargne-dettes').firstOrNull;
      expect(epargne, isNotNull, reason: 'la famille Épargne et dettes existe');
      final subs = cats.where((c) => c.parentId == epargne!.id).toList();
      expect(subs.map((s) => s.name), contains('Prêt accordé'));
      expect(subs.map((s) => s.name), contains('Remboursement d\'emprunt'));
    });

    test('idempotent : ré-amorçage sans aucun doublon', () async {
      await seedTaxonomyForSpace(db, spaceId);
      final before = (await categories()).length;
      await seedTaxonomyForSpace(db, spaceId);
      await seedTaxonomyForSpace(db, spaceId);
      final after = (await categories()).length;
      expect(after, before, reason: 'aucune catégorie dupliquée');
    });

    test('ensureTaxonomy : montée de version d\'une installation ancienne',
        () async {
      // Installation « ancienne » : on retire la taxonomie et on recrée
      // des catégories plates legacy + la référence de version.
      await (db.delete(db.financialCategories)
            ..where((c) => c.spaceId.equals(spaceId)))
          .go();
      await db.removeSetting('taxonomyVersion');
      await db.into(db.financialCategories).insert(FinancialCategory(
          id: 'legacy-1',
          spaceId: spaceId,
          name: 'Alimentation',
          kind: 'EXPENSE',
          colorHex: '#10A878'));
      await db.into(db.financialCategories).insert(FinancialCategory(
          id: 'legacy-2',
          spaceId: spaceId,
          name: 'Transport',
          kind: 'EXPENSE',
          colorHex: '#5B8DD9'));
      // Un compte + une opération qui référence la catégorie legacy-1.
      await db.into(db.financialAccounts).insert(FinancialAccountsCompanion
          .insert(
          id: 'acc1', spaceId: spaceId, name: 'Espèces', type: 'CASH',
          initialDate: '2026-01-01'));
      await db.into(db.financialTransactions).insert(
          FinancialTransactionsCompanion.insert(
              id: 'tx-legacy',
              spaceId: spaceId,
              accountId: 'acc1',
              kind: 'EXPENSE',
              currency: 'XOF',
              amount: 1000,
              categoryId: const Value('legacy-1'),
              occurredAt: DateTime(2026)));

      await db.ensureTaxonomy();

      final cats = await categories();
      // La taxonomie officielle est là…
      expect(cats.where((c) => c.slug == 'exp-epargne-dettes').firstOrNull,
          isNotNull);
      // …la catégorie legacy référencée est conservée…
      expect(cats.where((c) => c.id == 'legacy-1').firstOrNull, isNotNull);
      // …celle non référencée a été supprimée.
      expect(cats.where((c) => c.id == 'legacy-2').firstOrNull, isNull);
      // Version enregistrée : un second appel est immédiat (idempotent).
      expect(await db.getSetting('taxonomyVersion'), '2');
      await db.ensureTaxonomy(); // pas de doublon
      expect((await categories()).length, cats.length);
    });
  });

  group('prêts & emprunts (workflows)', () {
    test('prêt accordé : décaissement EXPENSE puis remboursement INCOME → soldé',
        () async {
      // Compte de départ.
      await db.into(db.financialAccounts).insert(FinancialAccountsCompanion
          .insert(
          id: 'acc1', spaceId: spaceId, name: 'Mobile Money', type: 'MOBILE_MONEY',
          initialDate: '2026-01-01'));

      final cats = await categories();
      final pretAccorde =
          cats.firstWhere((c) => c.name == 'Prêt accordé');

      // 1. Prêt accordé de 50 000 FCFA à Koffi.
      final loanId = 'loan-1';
      await db.into(db.loans).insert(Loan(
          id: loanId,
          spaceId: spaceId,
          direction: 'LENT',
          counterparty: 'Koffi Adjoua',
          principalAmount: 50000,
          currency: 'XOF',
          startedAt: '2026-01-10',
          status: 'ACTIVE',
          createdAt: DateTime(2026)));
      db.logOp('Loan', loanId, 'CREATE', {});

      // Décaissement : EXPENSE liée, catégorie Prêt accordé.
      await db.saveTransaction(FinancialTransaction(
          id: 'tx-out',
          spaceId: spaceId,
          accountId: 'acc1',
          kind: 'EXPENSE',
          amount: 50000,
          currency: 'XOF',
          status: 'POSTED',
          categoryId: pretAccorde.id,
          loanId: loanId,
          occurredAt: DateTime(2026, 1, 10),
          createdAt: DateTime(2026, 1, 10)));

      // 2. Remboursement partiel de 20 000 (recette « Prêt accordé remboursé »).
      final rembRecu =
          cats.firstWhere((c) => c.name == 'Prêt accordé remboursé');
      await db.saveTransaction(FinancialTransaction(
          id: 'tx-repay-1',
          spaceId: spaceId,
          accountId: 'acc1',
          kind: 'INCOME',
          amount: 20000,
          currency: 'XOF',
          status: 'POSTED',
          categoryId: rembRecu.id,
          loanId: loanId,
          occurredAt: DateTime(2026, 2, 1),
          createdAt: DateTime(2026, 2, 1)));

      var txs = await db.loanTransactions(loanId);
      expect(txs.length, 2);
      // 3. Solde du prêt : 30 000 restants.
      var repaid = txs
          .where((t) => t.kind == 'INCOME' && t.status == 'POSTED')
          .fold<int>(0, (s, t) => s + t.amount);
      expect(repaid, 20000);

      // 4. Remboursement final : 30 000 → prêt soldé.
      await db.saveTransaction(FinancialTransaction(
          id: 'tx-repay-2',
          spaceId: spaceId,
          accountId: 'acc1',
          kind: 'INCOME',
          amount: 30000,
          currency: 'XOF',
          status: 'POSTED',
          categoryId: rembRecu.id,
          loanId: loanId,
          occurredAt: DateTime(2026, 3, 1),
          createdAt: DateTime(2026, 3, 1)));
      txs = await db.loanTransactions(loanId);
      repaid = txs
          .where((t) => t.kind == 'INCOME' && t.status == 'POSTED')
          .fold<int>(0, (s, t) => s + t.amount);
      expect(repaid, 50000);
      await (db.update(db.loans)..where((l) => l.id.equals(loanId)))
          .write(const LoansCompanion(status: Value('SETTLED')));
      final loan = await db.getLoan(loanId);
      expect(loan!.status, 'SETTLED');
    });

    test('emprunt reçu : entrée INCOME « Emprunt reçu » puis remboursement EXPENSE',
        () async {
      await db.into(db.financialAccounts).insert(FinancialAccountsCompanion
          .insert(
          id: 'acc1', spaceId: spaceId, name: 'Espèces', type: 'CASH',
          initialDate: '2026-01-01'));
      final cats = await categories();
      final empruntRecu = cats
          .firstWhere((c) => c.name == 'Emprunt reçu (capital emprunté)');

      await db.into(db.loans).insert(Loan(
          id: 'loan-2',
          spaceId: spaceId,
          direction: 'BORROWED',
          counterparty: 'MFI Espoir',
          principalAmount: 100000,
          currency: 'XOF',
          startedAt: '2026-02-01',
          status: 'ACTIVE',
          createdAt: DateTime(2026)));

      await db.saveTransaction(FinancialTransaction(
          id: 'tx-in',
          spaceId: spaceId,
          accountId: 'acc1',
          kind: 'INCOME',
          amount: 100000,
          currency: 'XOF',
          status: 'POSTED',
          categoryId: empruntRecu.id,
          loanId: 'loan-2',
          occurredAt: DateTime(2026, 2, 1),
          createdAt: DateTime(2026, 2, 1)));

      final txs = await db.loanTransactions('loan-2');
      expect(txs.single.kind, 'INCOME');
      expect(txs.single.categoryId, empruntRecu.id);
    });
  });

  group('planification budgétaire multi-mois', () {
    test('6 mois → 6 enveloppes mensuelles reliées par une série', () async {
      final start = DateTime(2026, 1, 1);
      const months = 6;
      final seriesId = 'ser-test';
      for (var i = 0; i < months; i++) {
        final mStart = DateTime(start.year, start.month + i, 1);
        final mEnd = DateTime(start.year, start.month + i + 1, 0);
        await db.into(db.budgets).insert(Budget(
            id: 'bud-$i',
            spaceId: spaceId,
            name: 'Marché',
            periodStart: '${mStart.year}-${mStart.month.toString().padLeft(2, '0')}-01',
            periodEnd:
                '${mEnd.year}-${mEnd.month.toString().padLeft(2, '0')}-${mEnd.day.toString().padLeft(2, '0')}',
            initialAmount: 75000,
            carryoverEnabled: true,
            planningCategory: 'Besoins essentiels',
            planningSubCategory: 'Alimentation et courses',
            seriesId: seriesId,
            createdAt: DateTime(2026)));
      }
      final budgets = await (db.select(db.budgets)
            ..where((b) => b.spaceId.equals(spaceId)))
          .get();
      expect(budgets.length, months);
      expect(budgets.every((b) => b.seriesId == seriesId), isTrue);
      expect(
          budgets.map((b) => b.planningCategory).toSet(), {'Besoins essentiels'});
      // Périodes consécutives sans trou : janv → juin.
      expect(budgets.first.periodStart, '2026-01-01');
      expect(budgets.last.periodStart, '2026-06-01');
    });
  });

  group('profil local (photo, profession, questions de sécurité)', () {
    test('lecture/écriture mono-ligne + hachage des réponses', () async {
      final profile = await db.getLocalProfile();
      expect(profile.id, 'me');
      expect(profile.avatarPath, isNull);

      await db.saveLocalProfile(const UserProfileCompanion(
        avatarPath: Value('data:image/jpeg;base64,xyz'),
        profession: Value('Commerçante'),
        countryIso: Value('BJ'),
        securityQuestion1: Value('Dans quelle ville êtes-vous né(e) ?'),
        securityAnswer1: Value('hash1'),
      ));

      final updated = await db.getLocalProfile();
      expect(updated.avatarPath, 'data:image/jpeg;base64,xyz');
      expect(updated.profession, 'Commerçante');
      expect(updated.countryIso, 'BJ');
      expect(updated.securityQuestion1, 'Dans quelle ville êtes-vous né(e) ?');
      expect(updated.securityAnswer1, 'hash1');
    });
  });

  test('Money : sérialisation XOF stable', () {
    final m = Money.tryParse('75 000', Currency.xof);
    expect(m, isNotNull);
    expect(m!.minor, 75000);
  });
}
