// Modèles partagés (freezed-style sans codegen pour simplicité V1)
import 'package:flutter/foundation.dart';

@immutable
class User {
  const User({
    required this.id,
    required this.email,
    required this.firstName,
    this.lastName,
    this.phone,
    this.avatarUrl,
    this.plan = 'FREE',
    this.language = 'FR',
    this.appMode = 'STANDARD',
    this.currency = 'XOF',
    this.onboarded = false,
    this.accessibleOnboarded = false,
  });

  final String id;
  final String email;
  final String firstName;
  final String? lastName;
  final String? phone;
  final String? avatarUrl;
  final String plan;
  final String language;
  final String appMode;
  final String currency;
  final bool onboarded;
  final bool accessibleOnboarded;

  String get fullName => [firstName, lastName].whereType<String>().join(' ');

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String?,
        phone: json['phone'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        plan: json['plan'] as String? ?? 'FREE',
        language: json['language'] as String? ?? 'FR',
        appMode: json['appMode'] as String? ?? 'STANDARD',
        currency: json['currency'] as String? ?? 'XOF',
        onboarded: json['onboarded'] as bool? ?? false,
        accessibleOnboarded: json['accessibleOnboarded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'plan': plan,
        'language': language,
        'appMode': appMode,
        'currency': currency,
        'onboarded': onboarded,
        'accessibleOnboarded': accessibleOnboarded,
      };
}

@immutable
class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.balance,
    this.currency = 'XOF',
    this.color,
    this.icon,
    this.archived = false,
  });

  final String id;
  final String userId;
  final String name;
  final String type;
  final num balance;
  final String currency;
  final String? color;
  final String? icon;
  final bool archived;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        userId: json['userId'] as String? ?? '',
        name: json['name'] as String,
        type: json['type'] as String,
        balance: json['balance'] is String
            ? num.tryParse(json['balance']) ?? 0
            : (json['balance'] as num?) ?? 0,
        currency: json['currency'] as String? ?? 'XOF',
        color: json['color'] as String?,
        icon: json['icon'] as String?,
        archived: json['archived'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'balance': balance,
        'currency': currency,
        'color': color,
        'icon': icon,
      };
}

@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.label,
    this.category,
    this.subcategory,
    this.note,
    this.tags = const [],
    this.date,
    this.recurring = false,
    this.savingsGoalId,
    this.account,
  });

  final String id;
  final String accountId;
  final String type; // INCOME, EXPENSE, TRANSFER
  final num amount;
  final String label;
  final String? category;
  final String? subcategory;
  final String? note;
  final List<dynamic> tags;
  final DateTime? date;
  final bool recurring;
  final String? savingsGoalId;
  final Account? account;

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as String,
        accountId: json['accountId'] as String,
        type: json['type'] as String,
        amount: json['amount'] is String
            ? num.tryParse(json['amount']) ?? 0
            : (json['amount'] as num?) ?? 0,
        label: json['label'] as String,
        category: json['category'] as String?,
        subcategory: json['subcategory'] as String?,
        note: json['note'] as String?,
        tags: json['tags'] as List<dynamic>? ?? [],
        date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
        recurring: json['recurring'] as bool? ?? false,
        savingsGoalId: json['savingsGoalId'] as String?,
        account: json['account'] != null ? Account.fromJson(json['account'] as Map<String, dynamic>) : null,
      );
}

@immutable
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currentAmount = 0,
    this.description,
    this.deadline,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? description;
  final num targetAmount;
  final num currentAmount;
  final DateTime? deadline;
  final String? imageUrl;

  double get progress => targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0;

  factory SavingsGoal.fromJson(Map<String, dynamic> json) => SavingsGoal(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        targetAmount: json['targetAmount'] is String
            ? num.tryParse(json['targetAmount']) ?? 0
            : (json['targetAmount'] as num?) ?? 0,
        currentAmount: json['currentAmount'] is String
            ? num.tryParse(json['currentAmount']) ?? 0
            : (json['currentAmount'] as num?) ?? 0,
        deadline: json['deadline'] != null ? DateTime.parse(json['deadline'] as String) : null,
        imageUrl: json['imageUrl'] as String?,
      );
}

@immutable
class Tontine {
  const Tontine({
    required this.id,
    required this.name,
    required this.contributionAmount,
    required this.myRank,
    required this.totalMembers,
    this.frequency = 'MONTHLY',
    this.startDate,
    this.description,
    this.active = true,
    this.members = const [],
  });

  final String id;
  final String name;
  final String? description;
  final num contributionAmount;
  final String frequency;
  final DateTime? startDate;
  final int myRank;
  final int totalMembers;
  final bool active;
  final List<TontineMember> members;

  num get totalPot => contributionAmount * totalMembers;

  factory Tontine.fromJson(Map<String, dynamic> json) => Tontine(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        contributionAmount: json['contributionAmount'] is String
            ? num.tryParse(json['contributionAmount']) ?? 0
            : (json['contributionAmount'] as num?) ?? 0,
        frequency: json['frequency'] as String? ?? 'MONTHLY',
        startDate: json['startDate'] != null ? DateTime.parse(json['startDate'] as String) : null,
        myRank: json['myRank'] as int? ?? 1,
        totalMembers: json['totalMembers'] as int? ?? 0,
        active: json['active'] as bool? ?? true,
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => TontineMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class TontineMember {
  const TontineMember({
    required this.id,
    required this.name,
    required this.rank,
    this.phone,
    this.paid = false,
    this.received = false,
  });

  final String id;
  final String name;
  final String? phone;
  final int rank;
  final bool paid;
  final bool received;

  factory TontineMember.fromJson(Map<String, dynamic> json) => TontineMember(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        rank: json['rank'] as int? ?? 0,
        paid: json['paid'] as bool? ?? false,
        received: json['received'] as bool? ?? false,
      );
}

@immutable
class Debt {
  const Debt({
    required this.id,
    required this.direction,
    required this.personName,
    required this.amount,
    this.personPhone,
    this.dueDate,
    this.note,
    this.settled = false,
  });

  final String id;
  final String direction; // OWED, OWING
  final String personName;
  final String? personPhone;
  final num amount;
  final DateTime? dueDate;
  final String? note;
  final bool settled;

  bool get isOwing => direction == 'OWING';

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
        id: json['id'] as String,
        direction: json['direction'] as String,
        personName: json['personName'] as String,
        personPhone: json['personPhone'] as String?,
        amount: json['amount'] is String
            ? num.tryParse(json['amount']) ?? 0
            : (json['amount'] as num?) ?? 0,
        dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
        note: json['note'] as String?,
        settled: json['settled'] as bool? ?? false,
      );
}

@immutable
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.nextDueDate,
    this.category,
    this.recurrence = 'MONTHLY',
    this.dueDay = 1,
    this.reminderDays = 3,
    this.status = 'PENDING',
  });

  final String id;
  final String name;
  final num amount;
  final String? category;
  final String recurrence;
  final int dueDay;
  final DateTime nextDueDate;
  final int reminderDays;
  final String status;

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        id: json['id'] as String,
        name: json['name'] as String,
        amount: json['amount'] is String
            ? num.tryParse(json['amount']) ?? 0
            : (json['amount'] as num?) ?? 0,
        category: json['category'] as String?,
        recurrence: json['recurrence'] as String? ?? 'MONTHLY',
        dueDay: json['dueDay'] as int? ?? 1,
        nextDueDate: DateTime.parse(json['nextDueDate'] as String),
        reminderDays: json['reminderDays'] as int? ?? 3,
        status: json['status'] as String? ?? 'PENDING',
      );
}

@immutable
class FinanceDashboard {
  const FinanceDashboard({
    this.score = 0,
    this.totalBalance = 0,
    this.accounts = const [],
    this.monthIncome = 0,
    this.monthExpenses = 0,
    this.monthSavings = 0,
    this.savingsRate = 0,
    this.prevIncome = 0,
    this.prevExpenses = 0,
    this.incomeChange = 0,
    this.expensesChange = 0,
    this.byCategory = const [],
    this.savingsGoals = const [],
    this.debts = const [],
    this.bills = const [],
    this.tontines = const [],
  });

  final int score;
  final num totalBalance;
  final List<Account> accounts;
  final num monthIncome;
  final num monthExpenses;
  final num monthSavings;
  final int savingsRate;
  final num prevIncome;
  final num prevExpenses;
  final int incomeChange;
  final int expensesChange;
  final List<CategoryAmount> byCategory;
  final List<SavingsGoal> savingsGoals;
  final List<Debt> debts;
  final List<Bill> bills;
  final List<Tontine> tontines;

  factory FinanceDashboard.fromJson(Map<String, dynamic> json) {
    final month = json['month'] as Map<String, dynamic>? ?? {};
    return FinanceDashboard(
      score: json['score'] as int? ?? 0,
      totalBalance: _parseNum(json['totalBalance']),
      accounts: ((json['accounts'] as List<dynamic>?) ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList(),
      monthIncome: _parseNum(month['income']),
      monthExpenses: _parseNum(month['expenses']),
      monthSavings: _parseNum(month['savings']),
      savingsRate: month['savingsRate'] as int? ?? 0,
      prevIncome: _parseNum(month['prevIncome']),
      prevExpenses: _parseNum(month['prevExpenses']),
      incomeChange: month['incomeChange'] as int? ?? 0,
      expensesChange: month['expensesChange'] as int? ?? 0,
      byCategory: ((json['byCategory'] as List<dynamic>?) ?? [])
          .map((c) => CategoryAmount.fromJson(c as Map<String, dynamic>))
          .toList(),
      savingsGoals: ((json['savingsGoals'] as List<dynamic>?) ?? [])
          .map((g) => SavingsGoal.fromJson(g as Map<String, dynamic>))
          .toList(),
      debts: ((json['debts'] as List<dynamic>?) ?? [])
          .map((d) => Debt.fromJson(d as Map<String, dynamic>))
          .toList(),
      bills: ((json['bills'] as List<dynamic>?) ?? [])
          .map((b) => Bill.fromJson(b as Map<String, dynamic>))
          .toList(),
      tontines: ((json['tontines'] as List<dynamic>?) ?? [])
          .map((t) => Tontine.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

@immutable
class CategoryAmount {
  const CategoryAmount({required this.category, required this.amount});
  final String category;
  final num amount;

  factory CategoryAmount.fromJson(Map<String, dynamic> json) => CategoryAmount(
        category: json['category'] as String,
        amount: _parseNum(json['amount']),
      );
}

num _parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

// ---------- HOME DASHBOARD 360° ----------
@immutable
class HomeDashboard {
  const HomeDashboard({
    this.globalScore = 0,
    this.scores = const PillarScores(),
    this.financial = const FinancialSummary(),
    this.health = const HealthSummary(),
    this.habits = const HabitsSummary(),
    this.goals = const GoalsSummary(),
    this.alerts = const [],
    this.boutiqueWeekProfit = 0,
    this.unreadInsights = 0,
  });

  final int globalScore;
  final PillarScores scores;
  final FinancialSummary financial;
  final HealthSummary health;
  final HabitsSummary habits;
  final GoalsSummary goals;
  final List<HomeAlert> alerts;
  final num boutiqueWeekProfit;
  final int unreadInsights;

  factory HomeDashboard.fromJson(Map<String, dynamic> json) => HomeDashboard(
        globalScore: json['globalScore'] as int? ?? 0,
        scores: PillarScores.fromJson(json['scores'] as Map<String, dynamic>? ?? {}),
        financial: FinancialSummary.fromJson(json['financial'] as Map<String, dynamic>? ?? {}),
        health: HealthSummary.fromJson(json['health'] as Map<String, dynamic>? ?? {}),
        habits: HabitsSummary.fromJson(json['habits'] as Map<String, dynamic>? ?? {}),
        goals: GoalsSummary.fromJson(json['goals'] as Map<String, dynamic>? ?? {}),
        alerts: ((json['alerts'] as List<dynamic>?) ?? [])
            .map((a) => HomeAlert.fromJson(a as Map<String, dynamic>))
            .toList(),
        boutiqueWeekProfit: _parseNum(json['boutiqueWeekProfit']),
        unreadInsights: json['unreadInsights'] as int? ?? 0,
      );
}

@immutable
class PillarScores {
  const PillarScores({
    this.finance = 0,
    this.health = 0,
    this.routines = 0,
    this.goals = 0,
    this.career = 0,
    this.relations = 0,
  });

  final int finance;
  final int health;
  final int routines;
  final int goals;
  final int career;
  final int relations;

  factory PillarScores.fromJson(Map<String, dynamic> json) => PillarScores(
        finance: json['finance'] as int? ?? 0,
        health: json['health'] as int? ?? 0,
        routines: json['routines'] as int? ?? 0,
        goals: json['goals'] as int? ?? 0,
        career: json['career'] as int? ?? 0,
        relations: json['relations'] as int? ?? 0,
      );

  List<MapEntry<String, int>> toList() => [
        MapEntry('Finance', finance),
        MapEntry('Santé', health),
        MapEntry('Routines', routines),
        MapEntry('Objectifs', goals),
        MapEntry('Carrière', career),
        MapEntry('Relations', relations),
      ];
}

@immutable
class FinancialSummary {
  const FinancialSummary({
    this.totalBalance = 0,
    this.income = 0,
    this.expenses = 0,
    this.savings = 0,
    this.savingsRate = 0,
    this.accountsCount = 0,
  });

  final num totalBalance;
  final num income;
  final num expenses;
  final num savings;
  final int savingsRate;
  final int accountsCount;

  factory FinancialSummary.fromJson(Map<String, dynamic> json) => FinancialSummary(
        totalBalance: _parseNum(json['totalBalance']),
        income: _parseNum(json['income']),
        expenses: _parseNum(json['expenses']),
        savings: _parseNum(json['savings']),
        savingsRate: json['savingsRate'] as int? ?? 0,
        accountsCount: json['accountsCount'] as int? ?? 0,
      );
}

@immutable
class HealthSummary {
  const HealthSummary({this.avgSleep = 0, this.avgEnergy = 0, this.weekWorkouts = 0});
  final double avgSleep;
  final double avgEnergy;
  final int weekWorkouts;

  factory HealthSummary.fromJson(Map<String, dynamic> json) => HealthSummary(
        avgSleep: (json['avgSleep'] as num?)?.toDouble() ?? 0,
        avgEnergy: (json['avgEnergy'] as num?)?.toDouble() ?? 0,
        weekWorkouts: json['weekWorkouts'] as int? ?? 0,
      );
}

@immutable
class HabitsSummary {
  const HabitsSummary({this.doneToday = 0, this.doneThisWeek = 0});
  final int doneToday;
  final int doneThisWeek;

  factory HabitsSummary.fromJson(Map<String, dynamic> json) => HabitsSummary(
        doneToday: json['doneToday'] as int? ?? 0,
        doneThisWeek: json['doneThisWeek'] as int? ?? 0,
      );
}

@immutable
class GoalsSummary {
  const GoalsSummary({this.active = 0, this.topPriorities = const []});
  final int active;
  final List<TopPriority> topPriorities;

  factory GoalsSummary.fromJson(Map<String, dynamic> json) => GoalsSummary(
        active: json['active'] as int? ?? 0,
        topPriorities: ((json['topPriorities'] as List<dynamic>?) ?? [])
            .map((p) => TopPriority.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class TopPriority {
  const TopPriority({required this.id, required this.title, required this.domain});
  final String id;
  final String title;
  final String domain;

  factory TopPriority.fromJson(Map<String, dynamic> json) => TopPriority(
        id: json['id'] as String,
        title: json['title'] as String,
        domain: json['domain'] as String,
      );
}

@immutable
class HomeAlert {
  const HomeAlert({required this.type, required this.message});
  final String type;
  final String message;

  factory HomeAlert.fromJson(Map<String, dynamic> json) => HomeAlert(
        type: json['type'] as String,
        message: json['message'] as String,
      );
}
