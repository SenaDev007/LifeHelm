import 'package:uuid/uuid.dart';

import 'database.dart';


const _uuid = Uuid();

/// Fondations d'un espace : listes, calendriers, catégories, questions (D01.2).
/// NOTE : aucune donnée de démonstration n'est plus créée — l'app démarre
/// vide et propre (les contenus de démo ont été retirés de LifeHelm).
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
        id: listId, spaceId: spaceId, name: name, colorHex: '#FFD700'));
    db.logOp('TaskList', listId, 'CREATE', {'name': name});
  }

  // Calendriers par défaut.
  final calNames = [
    ('Principal', '#5B8DD9'),
    ('Perso', '#10A878'),
    if (space?.type == 'PROFESSIONAL') ('Rendez-vous clients', '#E8720C'),
    if (space?.type == 'FAMILY') ('Famille', '#FFD700'),
  ];
  for (final (name, color) in calNames) {
    final calId = _uuid.v4();
    await db.into(db.calendars).insert(Calendar(
        id: calId, spaceId: spaceId, name: name, colorHex: color, isVisible: true));
    db.logOp('Calendar', calId, 'CREATE', {'name': name});
  }

  // Catégories financières communes.
  const categories = [
    ('Alimentation', 'EXPENSE', '#10A878'),
    ('Transport', 'EXPENSE', '#5B8DD9'),
    ('Logement', 'EXPENSE', '#FFD700'),
    ('Énergie', 'EXPENSE', '#E8A13D'),
    ('Santé', 'EXPENSE', '#E05B5B'),
    ('Éducation', 'EXPENSE', '#8A6DD9'),
    ('Télécom', 'EXPENSE', '#E8720C'),
    ('Loisirs', 'EXPENSE', '#5BB8D9'),
    ('Autres dépenses', 'EXPENSE', '#8A8A8A'),
    ('Salaire', 'INCOME', '#10A878'),
    ('Ventes', 'INCOME', '#FFD700'),
    ('Services', 'INCOME', '#5B8DD9'),
    ('Autres revenus', 'INCOME', '#8A8A8A'),
  ];
  for (final (name, kind, color) in categories) {
    final catId = _uuid.v4();
    await db.into(db.financialCategories).insert(FinancialCategory(
        id: catId, spaceId: spaceId, name: name, kind: kind, colorHex: color));
    db.logOp('FinancialCategory', catId, 'CREATE', {'name': name, 'kind': kind});
  }

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
