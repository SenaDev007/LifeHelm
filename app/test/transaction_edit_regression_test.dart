import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/providers.dart';
import 'package:lifehelm/core/theme/theme.dart';
import 'package:lifehelm/core/utils/formatters.dart' as fmt;
import 'package:lifehelm/features/finance/finance_screens.dart';

/// Régression : « page rouge au vin » à l'ouverture de la saisie de dépense
/// ou de revenu (boutons Dépense / Revenu du module Finances). L'écran doit
/// se construire sans exception, avec ou sans comptes, avec ou sans
/// catégories amorcées, sur écran étroit comme normal.
void main() {
  late AppDatabase db;

  Future<void> bootstrap({bool withAccounts = true}) async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    // Depuis la v0.2.2, 4 comptes types sont auto-créés par espace : on les
    // retire pour maîtriser les scénarios (avec/sans comptes).
    await (db.delete(db.financialAccounts)
          ..where((a) => a.spaceId.equals(personal.id)))
        .go();
    if (withAccounts) {
      for (final k in ['CASH', 'BANK', 'MOBILE_MONEY']) {
        await db
            .into(db.financialAccounts)
            .insert(FinancialAccountsCompanion.insert(
              id: 'acc_$k',
              spaceId: personal.id,
              name: 'Compte $k',
              type: k,
              initialDate: fmt.dateKey(fmt.today()),
            ));
      }
    }
    await db.setSetting('activeSpaceId', personal.id);
  }

  tearDown(() async => db.close());

  Future<void> pumpScreen(WidgetTester tester, String? type,
      {Size size = const Size(720, 1600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: LHTheme.light(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: TransactionEditScreen(initialType: type),
        ),
      ),
    );
    // Laisser les flux Drift émettre (providers asynchrones) : les
    // fournisseurs regroupent avec un délai de 50 ms — on avance
    // suffisamment l'horloge pour que tous les minuteurs se déclenchent
    // avant la fin du test (invariant « no timers pending »).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    // Chasse aux minuteurs retardataires : une émission Drift tardive peut
    // programmer un dernier délai de 50 ms après le dernier frame — sans
    // cette avance, l'invariant « no timers pending » échoue.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// Retire l'arbre de widgets PUIS avance d'un frame : le démontage du
  /// ProviderScope fait annuler les flux Drift, qui programment un minuteur
  /// de durée nulle (StreamQueryStore.markAsClosed). Sans cette avance
  /// finale, l'invariant « no timers pending » du harnais échoue.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('écran Dépense (type=expense) : aucun crash, éléments visibles',
      (tester) async {
    await bootstrap(withAccounts: true);
    await pumpScreen(tester, 'expense');

    expect(tester.takeException(), isNull,
        reason: 'La page Dépense ne doit plus afficher d\'écran rouge.');
    expect(find.text('Nouvelle opération'), findsOneWidget);
    expect(find.text('Dépense'), findsWidgets);
    expect(find.text('Compte'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('écran Revenu (type=income) : aucun crash, éléments visibles',
      (tester) async {
    await bootstrap(withAccounts: true);
    await pumpScreen(tester, 'income');

    expect(tester.takeException(), isNull,
        reason: 'La page Revenu ne doit plus afficher d\'écran rouge.');
    expect(find.text('Revenu'), findsWidgets);
    expect(find.text('Catégorie'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets(
      'sans aucun compte (première utilisation) : bouton de création, pas de menu grisé',
      (tester) async {
    await bootstrap(withAccounts: false);
    await pumpScreen(tester, 'expense', size: const Size(360, 640));

    expect(tester.takeException(), isNull,
        reason: 'Ouverture sans compte : l\'écran doit rester utilisable.');
    // Le sélecteur propose la création directe au lieu d'un menu vide.
    expect(find.text('Créer un premier compte'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets(
      'création d\'un compte depuis le sélecteur : le menu se remplit et sélectionne le nouveau compte',
      (tester) async {
    await bootstrap(withAccounts: false);
    await pumpScreen(tester, 'expense', size: const Size(360, 640));

    // Ouverture de la feuille de création depuis le bouton plein cadre.
    await tester.tap(find.text('Créer un premier compte'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau compte'), findsOneWidget);

    // Saisie du nom puis création (bouton possiblement sous le pli de la
    // feuille sur petit écran — le rendre visible avant le tap).
    await tester.enterText(
        find.widgetWithText(TextField, 'Ex. : MoMo MTN, Compte BOA, Tirelire…'),
        'MoMo MTN');
    await tester.ensureVisible(find.text('Créer le compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer le compte'));
    await tester.pumpAndSettle();
    // Laisser la flux Drift propager le nouveau compte aux providers.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Retour à l'écran : le compte créé est sélectionné dans le menu.
    expect(tester.takeException(), isNull);
    expect(find.text('MoMo MTN (XOF)'), findsOneWidget);
    // Vérification en base (requête ponctuelle — jamais un flux watch, qui
    // n'émet pas sous fake-async sans pump).
    final spaceId =
        (await db.getAllSpaces()).firstWhere((s) => s.type == 'PERSONAL').id;
    final accounts = await (db.select(db.financialAccounts)
          ..where((a) => a.spaceId.equals(spaceId)))
        .get();
    expect(accounts.length, 1, reason: 'Le compte doit être en base.');
    expect(accounts.first.name, 'MoMo MTN');
    await disposeTree(tester);
  });

  testWidgets('menu déroulant : « Nouveau compte… » proposé en fin de liste',
      (tester) async {
    await bootstrap(withAccounts: true);
    await pumpScreen(tester, 'expense');

    // Ouvre le menu du sélecteur de compte.
    await tester.tap(find.text('Compte CASH (XOF)'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau compte…'), findsOneWidget);
    await tester.tap(find.text('Nouveau compte…'));
    await tester.pumpAndSettle();

    // La feuille de création s'ouvre.
    expect(find.text('Créer le compte'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('écran étroit (360x640) : pas de débordement', (tester) async {
    await bootstrap(withAccounts: true);
    await pumpScreen(tester, 'expense', size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });
}
