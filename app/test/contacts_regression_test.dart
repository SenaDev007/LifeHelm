import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/providers.dart';
import 'package:lifehelm/core/theme/theme.dart';
import 'package:lifehelm/features/contacts/contacts.dart';

/// Régression : « package:flutter/src/widgets/framework.dart failed
/// assertion line 6281 pos 12 » (_dependents.isEmpty) signalée par
/// l'utilisateur sur la page Contacts. Le parcours complet doit se dérouler
/// sans exception : liste, création (feuille), fiche détail, édition,
/// notes, favori, ajout de coordonnée.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    await db.setSetting('activeSpaceId', personal.id);
  });

  tearDown(() async => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    // GoRouter réel : la création d'un contact pousse /contact/:id —
    // « No GoRouter found in context » sinon.
    final router = GoRouter(
      initialLocation: '/contacts',
      routes: [
        GoRoute(
          path: '/contacts',
          builder: (context, state) => const ContactsScreen(),
        ),
        GoRoute(
          path: '/contact/:id',
          builder: (context, state) =>
              ContactDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: LHTheme.light(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('parcours complet contacts sans exception', (tester) async {
    await pumpHome(tester);
    expect(tester.takeException(), isNull);

    // État vide visible.
    expect(find.text('Aucun contact ici'), findsOneWidget);

    // —— Création via la feuille « Nouveau contact » ——
    await tester.tap(find.text('Nouveau contact').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'L\'ouverture de la feuille ne doit pas lever.');

    // Ordre des TextFields à l'écran : le champ de recherche de la liste
    // (index 0, derrière la feuille) puis ceux de la feuille : Prénom(1),
    // Nom(2), Fonction-sélecteur(3), Téléphone(4), Courriel(5).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Alphonsine');
    await tester.enterText(fields.at(2), 'Dossou');
    await tester.enterText(fields.at(3), 'Commerçante');
    await tester.enterText(fields.at(4), '01 97 12 34 56');
    await tester.pump();

    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull,
        reason: 'La création ne doit pas provoquer d\'erreur (framework.dart).');

    // La fiche détail s'ouvre après création.
    expect(find.text('Alphonsine Dossou'), findsWidgets);

    // —— Édition de l'identité ——
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Le dialogue d\'édition ne doit pas lever (framework.dart).');
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // —— Notes ——
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Préfère être appelée Maman A');
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // —— Retour à la liste : le contact apparaît ——
    // (pageBack() cherche le tooltip anglais « Back » ; l'app est en
    // français — on tape directement la flèche de retour.)
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Alphonsine Dossou'), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('organisation : création et affichage sans exception',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Nouveau contact').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Organisation'));
    await tester.pumpAndSettle();
    // Recherche(0) puis Nom de l'organisation(1), Secteur(2).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'YEHI OR Tech');
    await tester.enterText(fields.at(2), 'Technologie');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('YEHI OR Tech'), findsWidgets);

    await disposeTree(tester);
  });
}
