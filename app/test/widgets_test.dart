import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifehelm/core/taxonomy.dart';
import 'package:lifehelm/core/theme/theme.dart';
import 'package:lifehelm/core/widgets/common.dart';
import 'package:lifehelm/core/widgets/pickers.dart';

void main() {
  testWidgets('LHCard rend sans crash en hauteur non bornée (regression stretch)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: LHTheme.dark(),
      home: ListView(children: [
        const LHCard(
          child: Column(children: [
            Text('Titre'),
            Row(children: [Text('Contenu')]),
          ]),
        ),
        LHCard(
          accent: const Color(0xFFFFD700),
          child: Column(children: [Text('Avec accent')]),
        ),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Titre'), findsOneWidget);
    expect(find.text('Avec accent'), findsOneWidget);
  });

  group('ProfessionPickerField', () {
    Future<void> pumpField(WidgetTester tester, TextEditingController ctrl,
        {String? Function()? onChangeSpy}) async {
      await tester.pumpWidget(MaterialApp(
        theme: LHTheme.light(),
        home: Scaffold(
          body: ListView(children: [
            ProfessionPickerField(
              controller: ctrl,
              onChanged: onChangeSpy == null ? null : (v) => onChangeSpy(),
            ),
          ]),
        ),
      ));
      await tester.pump();
    }

    testWidgets(
        'saisie libre : le contrôleur externe capture le texte tapé '
        '(la profession personnalisée n\'est plus perdue)', (tester) async {
      final ctrl = TextEditingController();
      await pumpField(tester, ctrl);

      await tester.enterText(
          find.byType(TextField), 'Zémidjanneur du rail');
      await tester.pump();

      expect(ctrl.text, 'Zémidjanneur du rail');
      ctrl.dispose();
    });

    testWidgets(
        'le bouton parcourir ouvre la liste complète des métiers, '
        'groupée par domaine et défilable', (tester) async {
      final ctrl = TextEditingController();
      await pumpField(tester, ctrl);

      // Avant ouverture : la liste n'est pas visible.
      expect(find.text('Votre profession'), findsNothing);

      await tester.tap(find.byTooltip('Parcourir la liste des professions'));
      await tester.pumpAndSettle();

      // La feuille montre le titre, le compteur et les en-têtes de domaines.
      expect(find.text('Votre profession'), findsOneWidget);
      expect(find.text('${allProfessions.length} métiers'), findsOneWidget);
      expect(find.text('AGRICULTURE, ÉLEVAGE ET PÊCHE'), findsOneWidget);
      // Un métier du premier domaine est visible sans recherche préalable.
      expect(find.text('Agriculteur / Agricultrice'), findsOneWidget);

      // Sélection dans la liste → le champ est rempli.
      await tester.tap(find.text('Agriculteur / Agricultrice'));
      await tester.pumpAndSettle();
      expect(ctrl.text, 'Agriculteur / Agricultrice');
      ctrl.dispose();
    });

    testWidgets('la recherche dans la feuille filtre et propose la saisie libre',
        (tester) async {
      final ctrl = TextEditingController();
      await pumpField(tester, ctrl);

      await tester.tap(find.byTooltip('Parcourir la liste des professions'));
      await tester.pumpAndSettle();

      // Champ de recherche de la feuille (le second TextField : le premier
      // est le champ profession lui-même).
      await tester.enterText(find.byType(TextField).at(1), 'commerc');
      await tester.pumpAndSettle();

      // Correspondance du référentiel affichée avec son domaine — la
      // recherche est insensible aux accents (commerc → Commerçant).
      expect(find.text('Commerçant / Commerçante'), findsOneWidget);
      // Option de saisie libre en tête quand la saisie n'est pas un métier.
      expect(find.text('Utiliser « commerc »'), findsOneWidget);

      // Effacement puis recherche sans accent d'un métier accentué.
      await tester.tap(find.byTooltip('Effacer la recherche'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'medecin');
      await tester.pumpAndSettle();
      expect(find.text('Médecin généraliste'), findsOneWidget);

      // Retour à une saisie libre et sélection.
      await tester.enterText(find.byType(TextField).at(1), 'commerc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utiliser « commerc »'));
      await tester.pumpAndSettle();
      expect(ctrl.text, 'commerc');
      ctrl.dispose();
    });
  });
}
