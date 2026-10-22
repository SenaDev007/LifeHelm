import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/providers.dart';
import 'package:lifehelm/core/theme/theme.dart';
import 'package:lifehelm/features/messaging/messaging.dart';

/// Régression : « Au niveau de la messagerie, ça m'envoie la page d'erreur
/// package flutter » signalée par l'utilisateur. Le parcours complet doit
/// se dérouler sans exception : liste vide, création (feuille), conversation
/// directe, envoi + accusés simulés, retour, groupe, réponse simulée.
void main() {
  late AppDatabase db;
  late String personalSpaceId;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.initializeDefaultSpaces(ownerName: 'Test');
    final spaces = await db.getAllSpaces();
    final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
    personalSpaceId = personal.id;
    await db.setSetting('activeSpaceId', personal.id);
  });

  tearDown(() async => db.close());

  Future<void> pumpMessages(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (context, state) => const ConversationsScreen(),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) =>
              ChatScreen(id: state.pathParameters['id']!),
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
  }

  testWidgets('parcours complet messagerie sans exception', (tester) async {
    await pumpMessages(tester);
    expect(tester.takeException(), isNull);

    // État vide illustré.
    expect(find.text('Aucune conversation'), findsOneWidget);

    // ── Création d'une conversation directe via la feuille ──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.widgetWithText(TextField, 'Nom du correspondant *'), 'Awa Mensah');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Le chat est ouvert : envoi d'un message.
    await tester.enterText(find.byType(TextField).last, 'Salut Awa !');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('Salut Awa !'), findsOneWidget);

    // Les accusés simulés (600 ms → SENT, +1,8 s → DELIVERED, lectures
    // 3-7 s, réponse simulée 3-7 s) : on avance largement le temps.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Retour à la liste : la conversation apparaît.
    // (Le bouton retour Material est implicite sur l'AppBar du chat.)
    final backButton = find.byType(BackButton);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton);
    } else {
      await tester.tap(find.byTooltip('Retour'));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Awa'), findsWidgets);

    // ── Groupe : création directe en base puis ouverture ──
    await db.createConversation(
        spaceId: personalSpaceId,
        kind: 'GROUP',
        title: 'Équipe LifeHelm',
        memberNames: ['Awa Mensah', 'Koffi Ahouandjinou']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Équipe LifeHelm'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Envoi dans le groupe + simulations complètes (réponse simulée possible).
    await tester.enterText(find.byType(TextField).last, 'Réunion à 15 h ?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Nettoyage de l'arbre : aucune incohérence au démontage.
    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
