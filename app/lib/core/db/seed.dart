import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../taxonomy.dart';
import 'database.dart';

const _uuid = Uuid();

/// Fondations d'un espace : listes, calendriers, taxonomie financière
/// complète, questions de bilan (D01.2).
/// NOTE : aucune donnée de démonstration n'est créée — l'app démarre
/// vide et propre.
Future<void> seedSpaceFoundations(AppDatabase db, String spaceId,
    {required String ownerName, required bool withDemo}) async {
  // Listes de tâches par défaut.
  final defaultLists = {
    'PERSONAL': ['Quotidien', 'Maison', 'Santé'],
    'FAMILY': ['Famille', 'Courses', 'Enfants'],
    'PROFESSIONAL': ['Pilotage', 'Clients', 'Administratif'],
  };
  final space = await db.getSpace(spaceId);
  final listNames = defaultLists[space?.type ?? 'PERSONAL'] ?? ['Général'];
  for (final name in listNames) {
    final listId = _uuid.v4();
    await db.into(db.taskLists).insert(TaskList(
        id: listId, spaceId: spaceId, name: name, colorHex: '#FFB400'));
    db.logOp('TaskList', listId, 'CREATE', {'name': name});
  }

  // Calendriers par défaut.
  final calNames = [
    ('Principal', '#3B82F6'),
    ('Perso', '#22C55E'),
    if (space?.type == 'PROFESSIONAL') ('Rendez-vous clients', '#FF7A00'),
    if (space?.type == 'FAMILY') ('Famille', '#FFB400'),
  ];
  for (final (name, color) in calNames) {
    final calId = _uuid.v4();
    await db.into(db.calendars).insert(Calendar(
        id: calId, spaceId: spaceId, name: name, colorHex: color, isVisible: true));
    db.logOp('Calendar', calId, 'CREATE', {'name': name});
  }

  // Taxonomie financière exhaustive (catégories + sous-catégories).
  await seedTaxonomyForSpace(db, spaceId);

  // Profil carrière vierge.
  final profileId = _uuid.v4();
  await db.into(db.careerProfiles).insert(
      CareerProfile(id: profileId, spaceId: spaceId));
  db.logOp('CareerProfile', profileId, 'CREATE', {'spaceId': spaceId});

  // Questions de bilan quotidien (D09) — personnalisables.
  const questions = [
    'Qu’est-ce qui a bien fonctionné aujourd’hui ?',
    'Qu’est-ce qui a été difficile ?',
    'Qu’ai-je appris aujourd’hui ?',
    'Que ferai-je différemment demain ?',
    'Suis-je aligned avec mes priorités cette semaine ?',
  ];
  for (var i = 0; i < questions.length; i++) {
    await db.into(db.reflectionQuestions).insert(ReflectionQuestion(
        id: _uuid.v4(), question: questions[i], position: i, active: true));
  }
}

/// Amorce la taxonomie officielle (recettes + dépenses, catégories et
/// sous-catégories) pour un espace. Idempotent par slug : les lignes déjà
/// présentes ne sont jamais dupliquées. Les inserts passent par un batch
/// Drift (une seule transaction) — quasi instantané même sur le web.
Future<void> seedTaxonomyForSpace(AppDatabase db, String spaceId) async {
  // Lecture unique des slugs déjà présents (dédoublonnage).
  final rows = await (db.select(db.financialCategories)
        ..where((c) => c.spaceId.equals(spaceId)))
      .get();
  final existing = rows
      .map((c) => c.slug)
      .whereType<String>()
      .toSet();

  // Collecte de tout ce qui manque, parents d'abord pour référencer leurs
  // identifiants dans les sous-catégories.
  final pendingParents = <FinancialCategoriesCompanion>[];
  final pendingSubs = <FinancialCategoriesCompanion>[];
  final logged = <(String, String, Map<String, dynamic>)>[]; // (id, kind, log)

  for (final entry in [
    for (final n in taxonomyIncome) (n, 'INCOME'),
    for (final n in taxonomyExpense) (n, 'EXPENSE'),
  ]) {
    final (node, kind) = entry;
    if (existing.contains(node.slug)) continue;
    final parentId = _uuid.v4();
    pendingParents.add(FinancialCategoriesCompanion.insert(
        id: parentId,
        spaceId: spaceId,
        name: node.name,
        kind: kind,
        colorHex: Value(node.colorHex),
        slug: Value(node.slug)));
    logged.add((parentId, kind, {'name': node.name, 'kind': kind, 'slug': node.slug}));
    for (final sub in node.subs) {
      final subSlug = '${node.slug}::${_slugify(sub)}';
      if (existing.contains(subSlug)) continue;
      final subId = _uuid.v4();
      pendingSubs.add(FinancialCategoriesCompanion.insert(
          id: subId,
          spaceId: spaceId,
          name: sub,
          kind: kind,
          colorHex: Value(node.colorHex),
          parentId: Value(parentId),
          slug: Value(subSlug)));
      logged.add((subId, kind, {'name': sub, 'kind': kind, 'slug': subSlug}));
    }
  }

  if (pendingParents.isNotEmpty || pendingSubs.isNotEmpty) {
    await db.batch((batch) {
      batch.insertAll(db.financialCategories, pendingParents);
      batch.insertAll(db.financialCategories, pendingSubs);
    });
    // Journalisation de synchronisation après le commit du batch.
    for (final (id, _, payload) in logged) {
      db.logOp('FinancialCategory', id, 'CREATE', payload);
    }
  }
}

String _slugify(String label) {
  return label
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

