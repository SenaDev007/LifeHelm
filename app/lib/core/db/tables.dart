import 'package:drift/drift.dart';

/// Schéma SQLite LifeHelm — implémente les modèles proposés par les Dossiers 01 à 14.
/// Conventions (CDC §3.5) :
/// - identifiants stables (UUID texte) pour tous les objets synchronisables ;
/// - dates civiles en texte ISO `yyyy-MM-dd` (distinctes des horodatages) ;
/// - montants en unités mineures entières + code devise ;
/// - suppression logique (champs `archivedAt` / `trashedAt` / `deletedAt`).

// ══════════════════════════════ D01 — ESPACES ══════════════════════════════

class Spaces extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // PERSONAL | FAMILY | PROFESSIONAL
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#FFD700'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class SpaceMembers extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get displayName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get role => text()(); // OWNER | ADMIN | MANAGER | MEMBER | VIEWER
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Règles de récurrence partagées (tâches D03 + événements D04 + habitudes D08).
class RecurrenceRules extends Table {
  TextColumn get id => text()();
  TextColumn get freq => text()(); // DAILY | WEEKLY | MONTHLY | YEARLY
  IntColumn get interval => integer().withDefault(const Constant(1))();
  TextColumn get byWeekday => text().nullable()(); // JSON "[1,3,5]" (lun=1..dim=7)
  TextColumn get untilKey => text().nullable()(); // date civile de fin
  IntColumn get count => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D03 — TÂCHES ══════════════════════════════

class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#FFD700'))();
  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get listId => text().nullable()();
  TextColumn get parentId => text().nullable()(); // sous-tâches multi-niveaux
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('TODO'))();
  // TODO | IN_PROGRESS | WAITING | DONE | CANCELLED
  TextColumn get priority => text().withDefault(const Constant('NORMAL'))();
  // LOW | NORMAL | HIGH | URGENT — priorité manuelle (≠ classement cockpit)
  TextColumn get startDate => text().nullable()(); // date civile
  TextColumn get dueDate => text().nullable()(); // date civile
  IntColumn get reminderMinutes => integer().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get progressPercent => integer().nullable()();
  TextColumn get recurrenceRuleId => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()(); // archivage ≠ statut
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Plusieurs responsables par tâche (D03 §8.1-6).
class TaskAssignees extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Dépendances entre tâches — requises dès le MVP (D03 §8.1-5, D07).
/// `taskId` est bloquée tant que `dependsOnTaskId` n'est pas DONE/CANCELLED.
class TaskDependencies extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get dependsOnTaskId => text()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D04 — AGENDA ══════════════════════════════

class Calendars extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#5B8DD9'))();
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get calendarId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get startDate => text()(); // date civile de début
  TextColumn get startTime => text().nullable()(); // "HH:mm"
  TextColumn get endDate => text()(); // date civile de fin (exclusive si journée entière)
  TextColumn get endTime => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('SCHEDULED'))();
  // SCHEDULED | COMPLETED | CANCELLED | RESCHEDULED
  TextColumn get originalStart => text().nullable()(); // historique de report (D04)
  TextColumn get recurrenceRuleId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class EventParticipants extends Table {
  TextColumn get id => text()();
  TextColumn get eventId => text()();
  TextColumn get name => text()();
  TextColumn get status => text().withDefault(const Constant('INVITED'))();
  // INVITED | ACCEPTED | DECLINED | TENTATIVE
  @override
  Set<Column> get primaryKey => {id};
}

/// Exceptions de récurrence : occurrence annulée ou détachée en événement propre.
class EventExceptions extends Table {
  TextColumn get id => text()();
  TextColumn get eventId => text()();
  TextColumn get dateKey => text()();
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D05 — FINANCES ══════════════════════════════

class FinancialAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // CASH | BANK | MOBILE_MONEY | SAVING | CUSTOM
  TextColumn get currency => text().withDefault(const Constant('XOF'))();
  IntColumn get initialAmount => integer().withDefault(const Constant(0))();
  TextColumn get initialDate => text()(); // date de référence du solde initial
  TextColumn get note => text().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class FinancialCategories extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // INCOME | EXPENSE
  TextColumn get colorHex => text().withDefault(const Constant('#8A8A8A'))();
  @override
  Set<Column> get primaryKey => {id};
}

class FinancialTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get accountId => text()();
  TextColumn get kind => text()(); // INCOME | EXPENSE | TRANSFER | ADJUSTMENT
  IntColumn get amount => integer()(); // unités mineures, toujours positif
  TextColumn get currency => text()();
  TextColumn get status => text().withDefault(const Constant('POSTED'))();
  // POSTED | PENDING | REVERSED | VOIDED
  TextColumn get categoryId => text().nullable()();
  TextColumn get transferId => text().nullable()();
  RealColumn get rateToXof => real().nullable()(); // taux conservé (D05 §10.3)
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Un transfert interne n'est ni un revenu ni une dépense (D05 §10.4).
class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get fromAccountId => text()();
  TextColumn get toAccountId => text()();
  IntColumn get fromAmount => integer()();
  TextColumn get fromCurrency => text()();
  IntColumn get toAmount => integer()();
  TextColumn get toCurrency => text()();
  RealColumn get rate => real().withDefault(const Constant(1.0))();
  IntColumn get fee => integer().nullable()(); // frais = opération distincte
  DateTimeColumn get occurredAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Répartition explicite d'une transaction entre plusieurs budgets (D05 §10.1-3).
class TransactionAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get budgetId => text()();
  IntColumn get amount => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get periodStart => text()(); // date civile
  TextColumn get periodEnd => text()();
  IntColumn get initialAmount => integer()(); // B
  BoolColumn get carryoverEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class BudgetAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get budgetId => text()();
  IntColumn get amount => integer()(); // A, signé
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class BudgetCarryovers extends Table {
  TextColumn get id => text()();
  TextColumn get budgetId => text()();
  IntColumn get amount => integer()(); // R, positif uniquement
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Échéance prévue : ne diminue PAS le solde avant la transaction réelle (D05 §10.6).
class FinancialDueItems extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get label => text()();
  IntColumn get expectedAmount => integer()();
  TextColumn get currency => text().withDefault(const Constant('XOF'))();
  TextColumn get dueDate => text()();
  TextColumn get accountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('OPEN'))(); // OPEN | PAID | VOID
  TextColumn get paidTransactionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Rapprochement : écart présenté, jamais corrigé automatiquement (D05 §10.6).
class AccountReconciliations extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  IntColumn get recordedAmount => integer()();
  IntColumn get observedAmount => integer()();
  DateTimeColumn get observedAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get adjustmentTransactionId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D06 — NOTES ══════════════════════════════

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get parentId => text().nullable()(); // hiérarchie, cycles interdits
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get blocksJson => text().withDefault(const Constant('[]'))(); // blocs éditeur riche
  TextColumn get plainText => text().withDefault(const Constant(''))(); // indexable
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()(); // corbeille
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// La restauration crée une nouvelle version ; l'historique est conservé (D06 §11.4).
class NoteVersions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get title => text()();
  TextColumn get blocksJson => text()();
  TextColumn get plainText => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Registre documentaire simulé (les fichiers réels nécessitent le backend).
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class AttachmentLinks extends Table {
  TextColumn get id => text()();
  TextColumn get resourceType => text()(); // TASK | EVENT | NOTE | GOAL | CONTACT...
  TextColumn get resourceId => text()();
  TextColumn get documentId => text()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D07 — PROJETS & OBJECTIFS ══════════════════════════════

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('PLANNED'))();
  // PLANNED | ACTIVE | ON_HOLD | COMPLETED | CANCELLED (archivage distinct)
  TextColumn get startDate => text().nullable()();
  TextColumn get targetDate => text().nullable()();
  IntColumn get manualProgress => integer().nullable()(); // ajustement manuel traçable
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class ProjectMembers extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant('CONTRIBUTOR'))(); // LEAD | CONTRIBUTOR
  @override
  Set<Column> get primaryKey => {id};
}

class ProjectStages extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('TODO'))(); // TODO | IN_PROGRESS | DONE
  @override
  Set<Column> get primaryKey => {id};
}

class ProjectMilestones extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))(); // PENDING | REACHED
  IntColumn get position => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class ProjectTaskLinks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get taskId => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('NOT_STARTED'))();
  // NOT_STARTED | ACTIVE | PAUSED | ACHIEVED | ABANDONED
  TextColumn get category => text().withDefault(const Constant('PERSONAL'))(); // PERSONAL | CAREER | FAMILY | FINANCE
  TextColumn get targetDate => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class GoalMetrics extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  TextColumn get name => text()();
  TextColumn get unit => text().nullable()();
  RealColumn get startValue => real().withDefault(const Constant(0))();
  RealColumn get targetValue => real().withDefault(const Constant(100))();
  RealColumn get currentValue => real().withDefault(const Constant(0))();
  TextColumn get direction => text().withDefault(const Constant('INCREASE'))();
  @override
  Set<Column> get primaryKey => {id};
}

class GoalProgressEntries extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  TextColumn get metricId => text().nullable()();
  RealColumn get value => real()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D08 — HABITUDES & ROUTINES ══════════════════════════════

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get trackingType => text().withDefault(const Constant('BINARY'))(); // BINARY | QUANTITY
  TextColumn get unit => text().nullable()();
  RealColumn get targetValue => real().nullable()();
  TextColumn get colorHex => text().withDefault(const Constant('#10A878'))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class HabitSchedules extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  TextColumn get freq => text().withDefault(const Constant('DAILY'))(); // DAILY | WEEKLY | INTERVAL
  TextColumn get weekdaysJson => text().nullable()(); // "[1,3,5]"
  IntColumn get intervalDays => integer().nullable()();
  TextColumn get sinceKey => text()(); // date de prise d'effet
  @override
  Set<Column> get primaryKey => {id};
}

/// Statuts distincts : manquée ≠ ignorée ; jours de repos distincts (D08).
class HabitOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  TextColumn get dateKey => text()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  // PENDING | DONE | MISSED | SKIPPED | REST
  RealColumn get value => real().nullable()(); // suivi quantitatif
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class Routines extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get name => text()();
  TextColumn get scheduledTime => text().nullable()(); // "HH:mm"
  TextColumn get weekdaysJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class RoutineSteps extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  TextColumn get habitId => text().nullable()(); // référence, pas de duplication
  TextColumn get label => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class RoutineOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  TextColumn get dateKey => text()();
  IntColumn get doneCount => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D09 — BIEN-ÊTRE ══════════════════════════════

class WellbeingEntries extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get dateKey => text()();
  IntColumn get mood => integer().nullable()(); // 1..5 — subjectif, pas un diagnostic
  IntColumn get energy => integer().nullable()();
  IntColumn get stress => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get tagsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Bilan quotidien guidé : réponses aux questions de réflexion.
class DailyReviews extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get dateKey => text()();
  TextColumn get answersJson => text().withDefault(const Constant('[]'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class ReflectionQuestions extends Table {
  TextColumn get id => text()();
  TextColumn get question => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D10 — CARRIÈRE ══════════════════════════════

class CareerProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get headline => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Skills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Autoévaluée ≠ prouvée ≠ certifiée — états distincts (D10 §15.2).
class UserSkills extends Table {
  TextColumn get id => text()();
  TextColumn get skillId => text()();
  IntColumn get level => integer().withDefault(const Constant(0))(); // 0..5
  TextColumn get status => text().withDefault(const Constant('SELFASSESSED'))();
  // SELFASSESSED | PROVEN | CERTIFIED
  TextColumn get note => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class LearningPaths extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('NOT_STARTED'))();
  // NOT_STARTED | IN_PROGRESS | COMPLETED | PAUSED
  TextColumn get targetDate => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class LearningPathSteps extends Table {
  TextColumn get id => text()();
  TextColumn get pathId => text()();
  TextColumn get label => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get resourceNote => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class ProfessionalExperiences extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get organization => text()();
  TextColumn get role => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Certifications extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get issuer => text().nullable()();
  TextColumn get issueDate => text().nullable()();
  TextColumn get expiryDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('DECLARED'))();
  // DECLARED | EVIDENCE | VERIFIED — états distincts (D10)
  TextColumn get credentialId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class PortfolioItems extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get link => text().nullable()();
  TextColumn get relatedProjectId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D11 — CONTACTS ══════════════════════════════

class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()(); // carnets isolés par espace
  TextColumn get kind => text()(); // PERSON | ORGANIZATION
  TextColumn get firstName => text().nullable()();
  TextColumn get lastName => text().nullable()();
  TextColumn get organizationName => text().nullable()();
  TextColumn get jobTitle => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class ContactPoints extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  TextColumn get type => text()(); // PHONE | EMAIL | ADDRESS | URL
  TextColumn get value => text()();
  TextColumn get label => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Historique des interactions saisi manuellement (D11 §16.1-4).
class ContactInteractions extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  TextColumn get dateKey => text()();
  TextColumn get kind => text()(); // CALL | MEETING | MESSAGE | EMAIL | OTHER
  TextColumn get summary => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class ContactLinks extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  TextColumn get resourceType => text()(); // TASK | EVENT | PROJECT | GOAL
  TextColumn get resourceId => text()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D12 — MESSAGERIE ══════════════════════════════

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get title => text().nullable()(); // null = conversation directe
  TextColumn get kind => text().withDefault(const Constant('DIRECT'))(); // DIRECT | GROUP
  BoolColumn get readReceiptsEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastMessageAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class ConversationMembers extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get displayName => text()();
  TextColumn get role => text().withDefault(const Constant('MEMBER'))(); // OWNER | MEMBER
  TextColumn get colorHex => text().withDefault(const Constant('#5B8DD9'))();
  @override
  Set<Column> get primaryKey => {id};
}

/// États fidèles aux événements réellement connus (D12 §17.2).
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderMemberId => text()();
  TextColumn get body => text()();
  TextColumn get status => text().withDefault(const Constant('SENT'))();
  // PENDING | SENT | DELIVERED | READ | FAILED
  DateTimeColumn get sentAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get editedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // suppression pour tous, traçable
  @override
  Set<Column> get primaryKey => {id};
}

class MessageReactions extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text()();
  TextColumn get memberName => text()();
  TextColumn get emoji => text()();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D13 — NOTIFICATIONS ══════════════════════════════

class Notifications extends Table {
  TextColumn get id => text()();
  TextColumn get spaceId => text()();
  TextColumn get category => text()(); // TASK | AGENDA | FINANCE | PROJECT | HABIT | NOTE | MESSAGE | SECURITY | SYSTEM
  TextColumn get priority => text().withDefault(const Constant('NORMAL'))();
  // INFO | NORMAL | IMPORTANT | CRITICAL
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get resourceType => text().nullable()();
  TextColumn get resourceId => text().nullable()();
  TextColumn get dedupKey => text().nullable()(); // anti-doublon technique
  DateTimeColumn get readAt => dateTime().nullable()(); // lecture ≠ archivage
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class NotificationPrefs extends Table {
  TextColumn get id => text()();
  TextColumn get category => text()();
  BoolColumn get inAppEnabled => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D14 — RECHERCHE ══════════════════════════════

class RecentSearches extends Table {
  TextColumn get id => text()();
  TextColumn get query => text()();
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════ D01.4 — SYNC (offline-first) ══════════════════════════════

/// File d'opérations persistante — chaque mutation locale y est journalisée
/// en attendant la synchronisation serveur (CDC D01.4).
class SyncOperations extends Table {
  TextColumn get id => text()();
  TextColumn get resourceType => text()();
  TextColumn get resourceId => text()();
  TextColumn get op => text()(); // CREATE | UPDATE | DELETE
  TextColumn get payloadJson => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  // PENDING | SYNCED | REJECTED
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Réglages applicatifs (clé-valeur).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
