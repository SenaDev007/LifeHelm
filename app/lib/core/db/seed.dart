import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../utils/formatters.dart' as fmt;

const _uuid = Uuid();

/// Fondations d'un espace : listes, calendriers, catégories, questions (D01.2).
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
        id: listId, spaceId: spaceId, name: name, colorHex: '#C6A85B'));
    db.logOp('TaskList', listId, 'CREATE', {'name': name});
  }

  // Calendriers par défaut.
  final calNames = [
    ('Principal', '#5B8DD9'),
    ('Perso', '#10A878'),
    if (space?.type == 'PROFESSIONAL') ('Rendez-vous clients', '#E8720C'),
    if (space?.type == 'FAMILY') ('Famille', '#C6A85B'),
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
    ('Logement', 'EXPENSE', '#C6A85B'),
    ('Énergie', 'EXPENSE', '#E8A13D'),
    ('Santé', 'EXPENSE', '#E05B5B'),
    ('Éducation', 'EXPENSE', '#8A6DD9'),
    ('Télécom', 'EXPENSE', '#E8720C'),
    ('Loisirs', 'EXPENSE', '#5BB8D9'),
    ('Autres dépenses', 'EXPENSE', '#8A8A8A'),
    ('Salaire', 'INCOME', '#10A878'),
    ('Ventes', 'INCOME', '#C6A85B'),
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

/// Données de démonstration riches — contextes personnel, familial et pro.
Future<void> seedAllDemoData(AppDatabase db) async {
  final spaces = await db.getAllSpaces();
  if (spaces.isEmpty) return;
  final personal = spaces.firstWhere((s) => s.type == 'PERSONAL');
  final family = spaces.firstWhere((s) => s.type == 'FAMILY');
  final pro = spaces.firstWhere((s) => s.type == 'PROFESSIONAL');

  final t = fmt.today();
  final key = fmt.dateKey;

  // ─────────────── ESPACE PERSONNEL ───────────────
  final lists = await (db.select(db.taskLists)
        ..where((l) => l.spaceId.equals(personal.id)))
      .get();
  final quotidien = lists.firstWhere((l) => l.name == 'Quotidien').id;
  final maison = lists.firstWhere((l) => l.name == 'Maison').id;

  // Règle de récurrence : tous les lundis.
  final weeklyRuleId = _uuid.v4();
  await db.into(db.recurrenceRules).insert(RecurrenceRule(
      id: weeklyRuleId, freq: 'WEEKLY', interval: 1, byWeekday: '[1]'));
  db.logOp('RecurrenceRule', weeklyRuleId, 'CREATE', {'freq': 'WEEKLY'});

  final t1 = _uuid.v4();
  final t2 = _uuid.v4();
  final t3 = _uuid.v4();
  final t4 = _uuid.v4();
  final t5 = _uuid.v4();
  final t6 = _uuid.v4();
  final t7 = _uuid.v4();
  final sub1 = _uuid.v4();
  final sub2 = _uuid.v4();

  Future<void> addTask(Task t) => db.into(db.tasks).insert(t);

  await addTask(Task(
      id: t1, spaceId: personal.id, listId: quotidien,
      position: 0,
      title: 'Payer la facture d\'électricité (CEET)',
      status: 'TODO', priority: 'HIGH',
      dueDate: key(t), recurrenceRuleId: null,
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.into(db.taskDependencies).insert(TaskDependency(
      id: _uuid.v4(), taskId: t1, dependsOnTaskId: t2));
  await addTask(Task(
      id: t2, spaceId: personal.id, listId: quotidien,
      position: 0,
      title: 'Vérifier le relevé du compteur',
      status: 'IN_PROGRESS', priority: 'NORMAL',
      dueDate: key(fmt.addDays(t, -1)),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: t3, spaceId: personal.id, listId: maison,
      position: 0,
      title: 'Réparer le robinet de la cuisine',
      status: 'WAITING', priority: 'NORMAL',
      notes: 'En attente de la venue du plombier',
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: t4, spaceId: personal.id, listId: quotidien,
      position: 0,
      title: 'Séance de sport',
      status: 'TODO', priority: 'NORMAL',
      dueDate: key(fmt.addDays(t, 2)), recurrenceRuleId: weeklyRuleId,
      estimatedMinutes: 45,
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: t5, spaceId: personal.id, listId: null,
      position: 0,
      title: 'Renouveler le passeport',
      status: 'TODO', priority: 'URGENT',
      dueDate: key(fmt.addDays(t, 5)),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: t6, spaceId: personal.id, listId: null,
      position: 0,
      title: 'Livre « Père riche, père pauvre » — chapitres 3-4',
      status: 'TODO', priority: 'LOW',
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: t7, spaceId: personal.id, listId: maison,
      position: 0,
      title: 'Trier les archives papier',
      status: 'DONE', priority: 'LOW',
      completedAt: DateTime.now(),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: sub1, spaceId: personal.id, listId: maison, parentId: t5,
      position: 0,
      title: 'Prendre les photos d\'identité',
      status: 'TODO', priority: 'NORMAL',
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await addTask(Task(
      id: sub2, spaceId: personal.id, listId: maison, parentId: t5,
      position: 0,
      title: 'Réunir les actes de naissance',
      status: 'DONE', priority: 'NORMAL',
      completedAt: DateTime.now(),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.taskAssignees, [
    TaskAssignee(id: _uuid.v4(), taskId: t2, name: 'Vous'),
    TaskAssignee(id: _uuid.v4(), taskId: t3, name: 'Plombier Kossi'),
  ]));

  // Comptes financiers personnels.
  final cash = _uuid.v4();
  final momo = _uuid.v4();
  final bank = _uuid.v4();
  final savings = _uuid.v4();
  await db.batch((b) => b.insertAll(db.financialAccounts, [
    FinancialAccount(id: cash, spaceId: personal.id, name: 'Caisse espèces',
        type: 'CASH', currency: 'XOF', initialAmount: 45000,
        initialDate: key(fmt.addDays(t, -30)), createdAt: DateTime.now()),
    FinancialAccount(id: momo, spaceId: personal.id, name: 'Mobile Money',
        type: 'MOBILE_MONEY', currency: 'XOF', initialAmount: 128500,
        initialDate: key(fmt.addDays(t, -30)), createdAt: DateTime.now(), note: 'Portefeuille principal'),
    FinancialAccount(id: bank, spaceId: personal.id, name: 'Compte courant',
        type: 'BANK', currency: 'XOF', initialAmount: 410000,
        initialDate: key(fmt.addDays(t, -30)), createdAt: DateTime.now()),
    FinancialAccount(id: savings, spaceId: personal.id, name: 'Épargne projet',
        type: 'SAVING', currency: 'XOF', initialAmount: 1250000,
        initialDate: key(fmt.addDays(t, -30)), createdAt: DateTime.now()),
  ]));
  for (final id in [cash, momo, bank, savings]) {
    db.logOp('FinancialAccount', id, 'CREATE', {'demo': true});
  }

  final cats = await (db.select(db.financialCategories)
        ..where((c) => c.spaceId.equals(personal.id)))
      .get();
  String catId(String name) =>
      cats.firstWhere((c) => c.name == name).id;

  // Transactions du mois.
  Future<void> tx(String accountId, String kind, int amount, String category,
      int daysAgo, String note) {
    return db.into(db.financialTransactions).insert(FinancialTransaction(
      id: _uuid.v4(), spaceId: personal.id, accountId: accountId,
      kind: kind, amount: amount, currency: 'XOF', status: 'POSTED',
      categoryId: catId(category), occurredAt: DateTime.now().subtract(Duration(days: daysAgo, hours: 3)),
      note: note, createdAt: DateTime.now(),
    ));
  }

  await tx(momo, 'INCOME', 350000, 'Salaire', 12, 'Salaire mensuel');
  await tx(bank, 'INCOME', 1250000, 'Salaire', 12, 'Virement salaire');
  await tx(momo, 'EXPENSE', 18500, 'Alimentation', 2, 'Marché d\'Adjara');
  await tx(cash, 'EXPENSE', 4000, 'Transport', 1, 'Taxi-moto');
  await tx(momo, 'EXPENSE', 12500, 'Énergie', 3, 'Recharge crédit électricité');
  await tx(momo, 'EXPENSE', 32000, 'Télécom', 5, 'Forfait internet');
  await tx(cash, 'EXPENSE', 7500, 'Alimentation', 6, 'Condiments et poisson');
  await tx(bank, 'EXPENSE', 150000, 'Logement', 8, 'Loyer');
  await tx(momo, 'EXPENSE', 22000, 'Santé', 4, 'Pharmacie');
  await tx(cash, 'EXPENSE', 9000, 'Loisirs', 9, 'Sortie football');
  await tx(momo, 'INCOME', 85000, 'Ventes', 15, 'Vente téléphone');

  // Transfert interne (ni revenu ni dépense) + frais distincts.
  final transferId = _uuid.v4();
  await db.into(db.transfers).insert(Transfer(
      id: transferId, spaceId: personal.id, fromAccountId: momo,
      toAccountId: savings, fromAmount: 100000, fromCurrency: 'XOF',
      toAmount: 100000, toCurrency: 'XOF', rate: 1.0, fee: 100,
      occurredAt: DateTime.now().subtract(const Duration(days: 10))));
  await db.batch((b) => b.insertAll(db.financialTransactions, [
    FinancialTransaction(
        id: _uuid.v4(), spaceId: personal.id, accountId: momo,
        kind: 'TRANSFER', amount: 100000, currency: 'XOF', status: 'POSTED',
        transferId: transferId, occurredAt: DateTime.now().subtract(const Duration(days: 10)),
        note: 'Versement épargne', createdAt: DateTime.now()),
    FinancialTransaction(
        id: _uuid.v4(), spaceId: personal.id, accountId: savings,
        kind: 'TRANSFER', amount: 100000, currency: 'XOF', status: 'POSTED',
        transferId: transferId, occurredAt: DateTime.now().subtract(const Duration(days: 10)),
        createdAt: DateTime.now()),
    FinancialTransaction(
        id: _uuid.v4(), spaceId: personal.id, accountId: momo,
        kind: 'EXPENSE', amount: 100, currency: 'XOF', status: 'POSTED',
        categoryId: catId('Autres dépenses'), occurredAt: DateTime.now().subtract(const Duration(days: 10)),
        note: 'Frais de transfert Mobile Money', createdAt: DateTime.now()),
  ]));

  // Budgets du mois avec allocations.
  final budgetFood = _uuid.v4();
  final budgetTransport = _uuid.v4();
  final mStart = DateTime(t.year, t.month, 1);
  final mEnd = DateTime(t.year, t.month + 1, 0);
  await db.batch((b) => b.insertAll(db.budgets, [
    Budget(id: budgetFood, spaceId: personal.id, name: 'Marché & alimentation',
        categoryId: catId('Alimentation'), periodStart: key(mStart),
        periodEnd: key(mEnd), initialAmount: 90000, carryoverEnabled: false,
        createdAt: DateTime.now()),
    Budget(id: budgetTransport, spaceId: personal.id, name: 'Transport',
        categoryId: catId('Transport'), periodStart: key(mStart),
        periodEnd: key(mEnd), initialAmount: 25000, carryoverEnabled: true,
        createdAt: DateTime.now()),
  ]));
  final foodTxs = await (db.select(db.financialTransactions)
        ..where((x) => x.spaceId.equals(personal.id) &
            x.categoryId.equals(catId('Alimentation')) &
            x.status.equals('POSTED')))
      .get();
  for (final x in foodTxs) {
    await db.into(db.transactionAllocations).insert(TransactionAllocation(
        id: _uuid.v4(), transactionId: x.id, budgetId: budgetFood, amount: x.amount));
  }
  await db.into(db.budgetAdjustments).insert(BudgetAdjustment(
      id: _uuid.v4(), budgetId: budgetFood, amount: 10000,
      reason: 'Réception prévue en fin de mois', createdAt: DateTime.now()));

  // Échéances financières.
  await db.batch((b) => b.insertAll(db.financialDueItems, [
    FinancialDueItem(id: _uuid.v4(), spaceId: personal.id,
        label: 'Loyer de novembre', expectedAmount: 150000, currency: 'XOF',
        dueDate: key(DateTime(t.year, t.month + 1, 1)), accountId: bank,
        categoryId: catId('Logement'), status: 'OPEN', createdAt: DateTime.now()),
    FinancialDueItem(id: _uuid.v4(), spaceId: personal.id,
        label: 'Écolage 1er trimestre', expectedAmount: 85000, currency: 'XOF',
        dueDate: key(fmt.addDays(t, 4)), accountId: momo, status: 'OPEN',
        createdAt: DateTime.now()),
    FinancialDueItem(id: _uuid.v4(), spaceId: personal.id,
        label: 'Abonnement salle de sport', expectedAmount: 10000, currency: 'XOF',
        dueDate: key(fmt.addDays(t, -2)), accountId: momo, status: 'OPEN',
        categoryId: catId('Loisirs'), createdAt: DateTime.now()),
  ]));

  // Événements d'agenda.
  final cals = await (db.select(db.calendars)
        ..where((c) => c.spaceId.equals(personal.id)))
      .get();
  final mainCal = cals.first.id;
  final persoCal = cals[1].id;
  final evtRrule = _uuid.v4();
  await db.into(db.recurrenceRules).insert(RecurrenceRule(
      id: evtRrule, freq: 'WEEKLY', interval: 1, byWeekday: '[2,4]'));
  db.logOp('RecurrenceRule', evtRrule, 'CREATE', {'freq': 'WEEKLY'});

  Future<void> evt(String title, String calId, String d, String? st, String? et,
      {String? loc, String status = 'SCHEDULED', String? rrule, int len = 1,
      String? desc}) {
    return db.into(db.calendarEvents).insert(CalendarEvent(
      id: _uuid.v4(), spaceId: personal.id, calendarId: calId, title: title,
      description: desc, location: loc, allDay: st == null,
      startDate: d, startTime: st, endDate: key(fmt.addDays(fmt.parseKey(d), len - 1)),
      endTime: et, status: status, recurrenceRuleId: rrule,
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
  }

  await evt('Réunion de l\'association', mainCal, key(fmt.addDays(t, 1)), '17:00', '18:30',
      loc: 'Maison des jeunes');
  await evt('Rendez-vous dentaire', persoCal, key(fmt.addDays(t, 3)), '10:00', '11:00');
  await evt('Formation Flutter — session 3', persoCal, key(fmt.addDays(t, 2)), '19:00', '20:30',
      desc: 'Module state management');
  await evt('Cours de zumba', persoCal, key(t), '18:30', '19:30', rrule: evtRrule);
  await evt('Week-end chez les parents', mainCal, key(fmt.addDays(t, 6)), null, null, len: 2);
  await evt('Point mensuel budget', persoCal, key(fmt.addDays(t, -5)), '09:00', '09:45',
      status: 'COMPLETED');
  final evtToday = _uuid.v4();
  await db.into(db.calendarEvents).insert(CalendarEvent(
      id: evtToday, spaceId: personal.id, calendarId: mainCal,
      title: 'Café avec Awa', allDay: false, startDate: key(t), startTime: '15:00',
      endDate: key(t), endTime: '16:00', status: 'SCHEDULED',
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.eventParticipants, [
    EventParticipant(id: _uuid.v4(), eventId: evtToday, name: 'Awa Mensah', status: 'ACCEPTED'),
    EventParticipant(id: _uuid.v4(), eventId: evtToday, name: 'Vous', status: 'ACCEPTED'),
  ]));

  // Notes.
  final folderAdmin = _uuid.v4();
  final folderProjets = _uuid.v4();
  await db.batch((b) => b.insertAll(db.folders, [
    Folder(id: folderAdmin, spaceId: personal.id, name: 'Administratif',
        createdAt: DateTime.now()),
    Folder(id: folderProjets, spaceId: personal.id, name: 'Projets',
        createdAt: DateTime.now()),
  ]));
  final note1 = _uuid.v4();
  final note2 = _uuid.v4();
  const blocksJson =
      '''[{"type":"h1","text":"Plan financier 2026"},{"type":"p","text":"Objectif : constituer 3 mois de dépenses en épargne de précaution."},{"type":"bullet","text":"Réduire le budget télécom de 15 %"},{"type":"bullet","text":"Automatiser le virement épargne chaque mois"},{"type":"check","text":"Ouvrir un compte dédié","checked":true},{"type":"check","text":"Paramétrer l'alerte à 80 % sur les budgets","checked":true},{"type":"quote","text":"On ne gère pas ce qu'on ne mesure pas."}]''';
  await db.batch((b) => b.insertAll(db.notes, [
    Note(id: note1, spaceId: personal.id, folderId: folderAdmin,
        title: 'Plan financier 2026',
        blocksJson: blocksJson,
        plainText: 'Plan financier 2026 Objectif : constituer 3 mois de dépenses en épargne de précaution. Réduire le budget télécom. Automatiser le virement épargne chaque mois. Ouvrir un compte dédié. Paramétrer l alerte à 80 %.',
        pinned: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Note(id: note2, spaceId: personal.id, folderId: folderProjets,
        title: 'Idées d\'activités secondaires', pinned: false,
        blocksJson:
            '''[{"type":"h2","text":"Pistes"},{"type":"p","text":"Freelance développement mobile pour PME locales."},{"type":"bullet","text":"Applications de gestion pour commerces du quartier"},{"type":"bullet","text":"Formation Flutter en présentiel"}]''',
        plainText: 'Idées d activités secondaires Freelance développement mobile pour PME locales. Applications de gestion pour commerces du quartier.',
        createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Note(id: _uuid.v4(), spaceId: personal.id, folderId: null,
        title: 'Recette de sauce arachide', pinned: false,
        blocksJson:
            '''[{"type":"p","text":"Ingrédients : arachides, tomates, oignon, poulet."},{"type":"bullet","text":"Faire griller les arachides"},{"type":"bullet","text":"Mixer avec les tomates"}]''',
        plainText: 'Recette de sauce arachide Ingrédients arachides tomates oignon poulet.',
        trashedAt: DateTime.now().subtract(const Duration(days: 2)),
        createdAt: DateTime.now(), updatedAt: DateTime.now()),
  ]));
  await db.into(db.noteVersions).insert(NoteVersion(
      id: _uuid.v4(), noteId: note1, title: 'Plan financier 2026',
      blocksJson: blocksJson,
      plainText: 'Version initiale', label: 'Création',
      createdAt: DateTime.now().subtract(const Duration(days: 14))));

  // Projet + objectif.
  final projApp = _uuid.v4();
  await db.into(db.projects).insert(Project(
      id: projApp, spaceId: personal.id,
      name: 'Application mobile de livraison',
      description: 'MVP d\'une app de livraison pour les commerces du quartier.',
      status: 'ACTIVE', startDate: key(fmt.addDays(t, -20)),
      targetDate: key(fmt.addDays(t, 40)),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.projectStages, [
    ProjectStage(id: _uuid.v4(), projectId: projApp, name: 'Cadrage & maquettes', position: 0, status: 'DONE'),
    ProjectStage(id: _uuid.v4(), projectId: projApp, name: 'Développement MVP', position: 1, status: 'IN_PROGRESS'),
    ProjectStage(id: _uuid.v4(), projectId: projApp, name: 'Tests terrain', position: 2, status: 'TODO'),
    ProjectStage(id: _uuid.v4(), projectId: projApp, name: 'Lancement', position: 3, status: 'TODO'),
  ]));
  await db.batch((b) => b.insertAll(db.projectMilestones, [
    ProjectMilestone(id: _uuid.v4(), projectId: projApp, name: 'Maquettes validées',
        dueDate: key(fmt.addDays(t, -10)), status: 'REACHED', position: 0),
    ProjectMilestone(id: _uuid.v4(), projectId: projApp, name: 'MVP fonctionnel',
        dueDate: key(fmt.addDays(t, 15)), status: 'PENDING', position: 1),
    ProjectMilestone(id: _uuid.v4(), projectId: projApp, name: '10 clients pilotes',
        dueDate: key(fmt.addDays(t, 35)), status: 'PENDING', position: 2),
  ]));
  await db.batch((b) => b.insertAll(db.projectMembers, [
    ProjectMember(id: _uuid.v4(), projectId: projApp, name: 'Vous', role: 'LEAD'),
    ProjectMember(id: _uuid.v4(), projectId: projApp, name: 'Koffi A.', role: 'CONTRIBUTOR'),
  ]));
  await db.batch((b) => b.insertAll(db.projectTaskLinks, [
    ProjectTaskLink(id: _uuid.v4(), projectId: projApp, taskId: t5),
    ProjectTaskLink(id: _uuid.v4(), projectId: projApp, taskId: t6),
  ]));

  final goalEpargne = _uuid.v4();
  final goalSante = _uuid.v4();
  await db.batch((b) => b.insertAll(db.goals, [
    Goal(id: goalEpargne, spaceId: personal.id,
        title: 'Épargner 1 000 000 FCFA', category: 'FINANCE',
        description: 'Fonds de précaution + équipement',
        status: 'ACTIVE', targetDate: key(DateTime(t.year + 1, 3, 31)),
        createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Goal(id: goalSante, spaceId: personal.id,
        title: 'Courir 5 km sans pause', category: 'PERSONAL',
        status: 'ACTIVE', createdAt: DateTime.now(), updatedAt: DateTime.now()),
  ]));
  final metricKm = _uuid.v4();
  await db.batch((b) => b.insertAll(db.goalMetrics, [
    GoalMetric(id: metricKm, goalId: goalEpargne, name: 'Montant épargné',
        unit: 'FCFA', startValue: 0, targetValue: 1000000, currentValue: 1250000,
        direction: 'INCREASE'),
    GoalMetric(id: _uuid.v4(), goalId: goalSante, name: 'Distance',
        unit: 'km', startValue: 0.5, targetValue: 5, currentValue: 3.5,
        direction: 'INCREASE'),
  ]));
  await db.batch((b) => b.insertAll(db.goalProgressEntries, [
    GoalProgressEntry(id: _uuid.v4(), goalId: goalEpargne, metricId: metricKm,
        value: 900000, note: 'Fin du mois dernier', recordedAt: DateTime.now().subtract(const Duration(days: 30))),
    GoalProgressEntry(id: _uuid.v4(), goalId: goalEpargne, metricId: metricKm,
        value: 1250000, note: 'Virement épargne effectué', recordedAt: DateTime.now().subtract(const Duration(days: 10))),
  ]));

  // Habitudes.
  final hEau = _uuid.v4();
  final hLecture = _uuid.v4();
  final hSport = _uuid.v4();
  await db.batch((b) => b.insertAll(db.habits, [
    Habit(id: hEau, spaceId: personal.id, name: 'Boire 2 L d\'eau',
        trackingType: 'QUANTITY', unit: 'L', targetValue: 2,
        colorHex: '#5BB8D9', createdAt: DateTime.now()),
    Habit(id: hLecture, spaceId: personal.id, name: 'Lire 20 minutes',
        trackingType: 'QUANTITY', unit: 'min', targetValue: 20,
        colorHex: '#C6A85B', createdAt: DateTime.now()),
    Habit(id: hSport, spaceId: personal.id, name: 'Exercice matinal',
        trackingType: 'BINARY', colorHex: '#10A878', createdAt: DateTime.now()),
  ]));
  await db.batch((b) => b.insertAll(db.habitSchedules, [
    HabitSchedule(id: _uuid.v4(), habitId: hEau, freq: 'DAILY', sinceKey: key(fmt.addDays(t, -21))),
    HabitSchedule(id: _uuid.v4(), habitId: hLecture, freq: 'DAILY', sinceKey: key(fmt.addDays(t, -21))),
    HabitSchedule(id: _uuid.v4(), habitId: hSport, freq: 'WEEKLY',
        weekdaysJson: '[1,3,5]', sinceKey: key(fmt.addDays(t, -21))),
  ]));
  // Occurrences des 7 derniers jours.
  for (var i = 6; i >= 0; i--) {
    final d = key(fmt.addDays(t, -i));
    final rnd = DateTime.now().millisecondsSinceEpoch % 10;
    await db.into(db.habitOccurrences).insert(HabitOccurrence(
        id: _uuid.v4(), habitId: hEau, dateKey: d,
        status: i == 0 ? 'PENDING' : (rnd % 4 == 0 && i > 2 ? 'MISSED' : 'DONE'),
        value: i == 0 ? null : (rnd % 4 == 0 && i > 2 ? null : 2.0),
        updatedAt: DateTime.now()));
    await db.into(db.habitOccurrences).insert(HabitOccurrence(
        id: _uuid.v4(), habitId: hLecture, dateKey: d,
        status: i == 0 ? 'PENDING' : (i % 3 == 0 ? 'SKIPPED' : 'DONE'),
        value: i == 0 || i % 3 == 0 ? null : 25,
        updatedAt: DateTime.now()));
    if ([1, 3, 5].contains(fmt.parseKey(d).weekday)) {
      await db.into(db.habitOccurrences).insert(HabitOccurrence(
          id: _uuid.v4(), habitId: hSport, dateKey: d,
          status: i == 0 ? 'PENDING' : 'DONE', updatedAt: DateTime.now()));
    }
  }

  // Routine du matin.
  final routineMatin = _uuid.v4();
  await db.into(db.routines).insert(Routine(
      id: routineMatin, spaceId: personal.id, name: 'Routine du matin',
      scheduledTime: '06:30', weekdaysJson: '[1,2,3,4,5]',
      createdAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.routineSteps, [
    RoutineStep(id: _uuid.v4(), routineId: routineMatin, habitId: hSport,
        label: 'Exercice (10 min)', position: 0),
    RoutineStep(id: _uuid.v4(), routineId: routineMatin, label: 'Douche', position: 1),
    RoutineStep(id: _uuid.v4(), routineId: routineMatin, habitId: hLecture,
        label: 'Lecture', position: 2),
    RoutineStep(id: _uuid.v4(), routineId: routineMatin, label: 'Planifier la journée', position: 3),
  ]));

  // Bien-être.
  await db.batch((b) => b.insertAll(db.wellbeingEntries, [
    WellbeingEntry(id: _uuid.v4(), spaceId: personal.id, dateKey: key(fmt.addDays(t, -1)),
        mood: 4, energy: 3, stress: 2, note: 'Bonne journée, projet avancé.',
        tagsJson: '["projet","famille"]', createdAt: DateTime.now()),
    WellbeingEntry(id: _uuid.v4(), spaceId: personal.id, dateKey: key(fmt.addDays(t, -2)),
        mood: 3, energy: 2, stress: 4, note: 'Journée chargée, beaucoup de sollicitations.',
        createdAt: DateTime.now()),
    WellbeingEntry(id: _uuid.v4(), spaceId: personal.id, dateKey: key(fmt.addDays(t, -3)),
        mood: 5, energy: 4, stress: 1, note: 'Sortie famille réussie.',
        tagsJson: '["famille"]', createdAt: DateTime.now()),
  ]));
  await db.into(db.dailyReviews).insert(DailyReview(
      id: _uuid.v4(), spaceId: personal.id, dateKey: key(fmt.addDays(t, -1)),
      answersJson:
          '''[{"q":"Qu’est-ce qui a bien fonctionné aujourd’hui ?","a":"Avancée sur le MVP"},{"q":"Qu’est-ce qui a été difficile ?","a":"Gérer les interruptions"}]''',
      note: 'Continuer les blocs de travail matinaux.',
      createdAt: DateTime.now()));

  // Carrière.
  await db.batch((b) => b.insertAll(db.skills, [
    Skill(id: _uuid.v4(), name: 'Flutter', category: 'Technique'),
    Skill(id: _uuid.v4(), name: 'Dart', category: 'Technique'),
    Skill(id: _uuid.v4(), name: 'Gestion de projet', category: 'Transversal'),
    Skill(id: _uuid.v4(), name: 'Négociation', category: 'Transversal'),
  ]));
  final skills = await db.select(db.skills).get();
  await db.batch((b) => b.insertAll(db.userSkills, [
    UserSkill(id: _uuid.v4(), skillId: skills[0].id, level: 4, status: 'PROVEN'),
    UserSkill(id: _uuid.v4(), skillId: skills[1].id, level: 4, status: 'PROVEN'),
    UserSkill(id: _uuid.v4(), skillId: skills[2].id, level: 3, status: 'SELFASSESSED'),
    UserSkill(id: _uuid.v4(), skillId: skills[3].id, level: 2, status: 'SELFASSESSED'),
  ]));
  final pathFlutter = _uuid.v4();
  await db.into(db.learningPaths).insert(LearningPath(
      id: pathFlutter, spaceId: personal.id, title: 'Maîtriser Flutter',
      description: 'Parcours complet : state management, tests, déploiement.',
      status: 'IN_PROGRESS', targetDate: key(fmt.addDays(t, 60)),
      createdAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.learningPathSteps, [
    LearningPathStep(id: _uuid.v4(), pathId: pathFlutter, label: 'Fondations Dart', done: true, position: 0),
    LearningPathStep(id: _uuid.v4(), pathId: pathFlutter, label: 'Widgets & layout', done: true, position: 1),
    LearningPathStep(id: _uuid.v4(), pathId: pathFlutter, label: 'State management (Riverpod)', done: true, position: 2),
    LearningPathStep(id: _uuid.v4(), pathId: pathFlutter, label: 'Persistance locale (Drift)', done: false, position: 3),
    LearningPathStep(id: _uuid.v4(), pathId: pathFlutter, label: 'Tests & CI', done: false, position: 4),
  ]));
  await db.batch((b) => b.insertAll(db.professionalExperiences, [
    ProfessionalExperience(id: _uuid.v4(), spaceId: personal.id,
        organization: 'Freelance', role: 'Développeur mobile',
        startDate: key(DateTime(t.year - 1, 6, 1)), isCurrent: true,
        description: 'Applications mobiles pour PME locales.'),
    ProfessionalExperience(id: _uuid.v4(), spaceId: personal.id,
        organization: 'Digital Africa SARL', role: 'Développeur junior',
        startDate: key(DateTime(t.year - 3, 1, 1)),
        endDate: key(DateTime(t.year - 1, 5, 30)), isCurrent: false,
        description: 'Maintenance d\'applications internes.'),
  ]));
  await db.batch((b) => b.insertAll(db.certifications, [
    Certification(id: _uuid.v4(), name: 'Google Flutter Certification',
        issuer: 'Google', issueDate: key(DateTime(t.year - 1, 9, 1)),
        status: 'EVIDENCE', credentialId: 'GFC-2024-8842'),
    Certification(id: _uuid.v4(), name: 'Scrum Fundamentals',
        issuer: 'SCRUMstudy', status: 'DECLARED'),
  ]));

  // Contacts personnels.
  final c1 = _uuid.v4();
  final c2 = _uuid.v4();
  final c3 = _uuid.v4();
  await db.batch((b) => b.insertAll(db.contacts, [
    Contact(id: c1, spaceId: personal.id, kind: 'PERSON', firstName: 'Awa',
        lastName: 'Mensah', jobTitle: 'Commerçante', isFavorite: true,
        createdAt: DateTime.now()),
    Contact(id: c2, spaceId: personal.id, kind: 'PERSON', firstName: 'Koffi',
        lastName: 'Adjara', jobTitle: 'Plombier', isFavorite: false, createdAt: DateTime.now()),
    Contact(id: c3, spaceId: personal.id, kind: 'ORGANIZATION',
        organizationName: 'Pharmacie du Marché', isFavorite: false, createdAt: DateTime.now()),
  ]));
  await db.batch((b) => b.insertAll(db.contactPoints, [
    ContactPoint(id: _uuid.v4(), contactId: c1, type: 'PHONE', value: '+228 90 12 34 56'),
    ContactPoint(id: _uuid.v4(), contactId: c1, type: 'EMAIL', value: 'awa.mensah@example.tg'),
    ContactPoint(id: _uuid.v4(), contactId: c2, type: 'PHONE', value: '+228 91 00 11 22'),
    ContactPoint(id: _uuid.v4(), contactId: c3, type: 'ADDRESS', value: 'Marché d\'Adjara, allée 4'),
  ]));
  await db.batch((b) => b.insertAll(db.contactInteractions, [
    ContactInteraction(id: _uuid.v4(), contactId: c1, dateKey: key(fmt.addDays(t, -4)),
        kind: 'CALL', summary: 'Prévu de se voir vendredi au marché.'),
    ContactInteraction(id: _uuid.v4(), contactId: c2, dateKey: key(fmt.addDays(t, -2)),
        kind: 'MEETING', summary: 'Passé réparer le robinet, reviendra finir.'),
  ]));

  // ─────────────── ESPACE FAMILLE ───────────────
  await db.batch((b) => b.insertAll(db.spaceMembers, [
    SpaceMember(id: _uuid.v4(), spaceId: family.id, displayName: 'Vous',
        role: 'OWNER', createdAt: DateTime.now()),
    SpaceMember(id: _uuid.v4(), spaceId: family.id, displayName: 'Aïcha (conjointe)',
        role: 'ADMIN', createdAt: DateTime.now()),
    SpaceMember(id: _uuid.v4(), spaceId: family.id, displayName: 'Maman',
        role: 'MEMBER', createdAt: DateTime.now()),
  ]));
  final famT1 = _uuid.v4();
  await db.into(db.tasks).insert(Task(
      position: 0,
      id: famT1, spaceId: family.id, title: 'Inscription des enfants à l\'école',
      status: 'IN_PROGRESS', priority: 'HIGH', dueDate: key(fmt.addDays(t, 3)),
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.batch((b) => b.insertAll(db.taskAssignees, [
    TaskAssignee(id: _uuid.v4(), taskId: famT1, name: 'Vous'),
    TaskAssignee(id: _uuid.v4(), taskId: famT1, name: 'Aïcha (conjointe)'),
  ]));
  final famCash = _uuid.v4();
  await db.into(db.financialAccounts).insert(FinancialAccount(
      id: famCash, spaceId: family.id, name: 'Caisse commune',
      type: 'CASH', currency: 'XOF', initialAmount: 210000,
      initialDate: key(fmt.addDays(t, -15)), createdAt: DateTime.now()));
  db.logOp('FinancialAccount', famCash, 'CREATE', {'name': 'Caisse commune'});
  await db.into(db.budgets).insert(Budget(
      id: _uuid.v4(), spaceId: family.id, name: 'Écolage trimestre 1',
      periodStart: key(mStart), periodEnd: key(mEnd), initialAmount: 340000,
      carryoverEnabled: false, createdAt: DateTime.now()));

  // ─────────────── ESPACE PRO ───────────────
  await db.batch((b) => b.insertAll(db.spaceMembers, [
    SpaceMember(id: _uuid.v4(), spaceId: pro.id, displayName: 'Vous',
        role: 'OWNER', createdAt: DateTime.now()),
    SpaceMember(id: _uuid.v4(), spaceId: pro.id, displayName: 'Sylvie (comptable)',
        role: 'MANAGER', createdAt: DateTime.now()),
  ]));
  final proCash = _uuid.v4();
  final proEur = _uuid.v4();
  await db.batch((b) => b.insertAll(db.financialAccounts, [
    FinancialAccount(id: proCash, spaceId: pro.id, name: 'Caisse activité',
        type: 'CASH', currency: 'XOF', initialAmount: 87500,
        initialDate: key(fmt.addDays(t, -10)), createdAt: DateTime.now()),
    FinancialAccount(id: proEur, spaceId: pro.id, name: 'Compte pro (EUR)',
        type: 'BANK', currency: 'EUR', initialAmount: 15000,
        initialDate: key(fmt.addDays(t, -10)), createdAt: DateTime.now(), note: 'Client européen'),
  ]));
  for (final id in [proCash, proEur]) {
    db.logOp('FinancialAccount', id, 'CREATE', {'demo': true});
  }
  final proT1 = _uuid.v4();
  await db.into(db.tasks).insert(Task(
      position: 0,
      id: proT1, spaceId: pro.id, title: 'Livrer la v2 pour le client Delta',
      status: 'TODO', priority: 'URGENT', dueDate: key(fmt.addDays(t, 6)),
      estimatedMinutes: 480,
      createdAt: DateTime.now(), updatedAt: DateTime.now()));
  await db.into(db.contacts).insert(Contact(
      id: _uuid.v4(), spaceId: pro.id, kind: 'ORGANIZATION',
      organizationName: 'Delta Distribution', jobTitle: 'Client — contrat en cours',
      isFavorite: false, createdAt: DateTime.now()));

  // Messagerie (espace famille).
  final conv1 = _uuid.v4();
  final conv2 = _uuid.v4();
  final you1 = _uuid.v4();
  final aicha = _uuid.v4();
  await db.batch((b) => b.insertAll(db.conversations, [
    Conversation(id: conv1, spaceId: family.id, kind: 'DIRECT',
        readReceiptsEnabled: true, lastMessageAt: DateTime.now(),
        createdAt: DateTime.now()),
    Conversation(id: conv2, spaceId: family.id, title: 'Organisation anniversaire',
        kind: 'GROUP', readReceiptsEnabled: true,
        lastMessageAt: DateTime.now().subtract(const Duration(hours: 3)),
        createdAt: DateTime.now()),
  ]));
  await db.batch((b) => b.insertAll(db.conversationMembers, [
    ConversationMember(id: you1, conversationId: conv1, displayName: 'Vous',
        role: 'OWNER', colorHex: '#C6A85B'),
    ConversationMember(id: aicha, conversationId: conv1, displayName: 'Aïcha',
        role: 'MEMBER', colorHex: '#10A878'),
    ConversationMember(id: _uuid.v4(), conversationId: conv2, displayName: 'Vous',
        role: 'OWNER', colorHex: '#C6A85B'),
    ConversationMember(id: _uuid.v4(), conversationId: conv2, displayName: 'Aïcha',
        role: 'MEMBER', colorHex: '#10A878'),
    ConversationMember(id: _uuid.v4(), conversationId: conv2, displayName: 'Maman',
        role: 'MEMBER', colorHex: '#5B8DD9'),
  ]));
  final m1 = _uuid.v4();
  final m2 = _uuid.v4();
  final m3 = _uuid.v4();
  await db.batch((b) => b.insertAll(db.messages, [
    Message(id: m1, conversationId: conv1, senderMemberId: aicha,
        body: 'Bonsoir ! Tu penses à quoi pour le dîner de dimanche ?',
        status: 'READ', sentAt: DateTime.now().subtract(const Duration(hours: 5))),
    Message(id: m2, conversationId: conv1, senderMemberId: you1,
        body: 'Je pensais au riz gras et du poulet braisé 😋',
        status: 'READ', sentAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 50))),
    Message(id: m3, conversationId: conv1, senderMemberId: aicha,
        body: 'Parfait, je m\'occupe des courses samedi matin.',
        status: 'DELIVERED', sentAt: DateTime.now().subtract(const Duration(hours: 4))),
  ]));
  await db.into(db.messageReactions).insert(
      MessageReaction(id: _uuid.v4(), messageId: m2, memberName: 'Aïcha', emoji: '❤️'));
  await db.batch((b) => b.insertAll(db.messages, [
    Message(id: _uuid.v4(), conversationId: conv2, senderMemberId: aicha,
        body: 'L\'anniversaire de papa, c\'est bien le 28 ?',
        status: 'READ', sentAt: DateTime.now().subtract(const Duration(hours: 8))),
    Message(id: _uuid.v4(), conversationId: conv2, senderMemberId: you1,
        body: '@Aïcha oui le 28 au soir. Je propose qu\'on réserve la salle.',
        status: 'READ', sentAt: DateTime.now().subtract(const Duration(hours: 7))),
    Message(id: _uuid.v4(), conversationId: conv2, senderMemberId: _uuid.v4(),
        body: 'Je peux faire le gâteau 🎂',
        status: 'READ', sentAt: DateTime.now().subtract(const Duration(hours: 3))),
  ]));
}
