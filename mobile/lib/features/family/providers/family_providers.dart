// Providers pour le module Famille (V2)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

// ---------- MODELES ----------

@immutable
class Family {
  const Family({
    required this.id,
    required this.name,
    this.description,
    required this.inviteCode,
    this.membersCount = 0,
    this.myRole = 'MEMBER',
    this.createdAt,
    this.members = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final int membersCount;
  final String myRole; // ADMIN | MEMBER
  final DateTime? createdAt;
  final List<FamilyMember> members;

  bool get isAdmin => myRole == 'ADMIN';

  factory Family.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? [])
        .map((m) => FamilyMember.fromJson(m as Map<String, dynamic>))
        .toList();
    return Family(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      inviteCode: (json['inviteCode'] as String?) ?? '',
      membersCount: json['membersCount'] as int? ?? members.length,
      myRole: (json['myRole'] as String?) ?? (json['role'] as String?) ?? 'MEMBER',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      members: members,
    );
  }
}

@immutable
class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.firstName,
    this.lastName,
    this.avatarUrl,
    required this.role,
    this.joinedAt,
  });

  final String id;
  final String firstName;
  final String? lastName;
  final String? avatarUrl;
  final String role; // ADMIN | MEMBER
  final DateTime? joinedAt;

  String get fullName => [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  bool get isAdmin => role == 'ADMIN';

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return FamilyMember(
      id: json['id'] as String? ?? (json['userId'] as String?) ?? '',
      firstName: (json['firstName'] as String?) ?? (user?['firstName'] as String?) ?? '',
      lastName: json['lastName'] as String? ?? (user?['lastName'] as String?),
      avatarUrl: json['avatarUrl'] as String? ?? (user?['avatarUrl'] as String?),
      role: (json['role'] as String?) ?? 'MEMBER',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'] as String)
          : (json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null),
    );
  }
}

@immutable
class FamilyBudget {
  const FamilyBudget({
    required this.id,
    required this.familyId,
    required this.month,
    this.totalIncome = 0,
    this.totalExpense = 0,
    this.note,
    this.contributions = const [],
  });

  final String id;
  final String familyId;
  final String month; // YYYY-MM
  final num totalIncome;
  final num totalExpense;
  final String? note;
  final List<BudgetContribution> contributions;

  num get balance => totalIncome - totalExpense;

  factory FamilyBudget.fromJson(Map<String, dynamic> json) => FamilyBudget(
        id: json['id'] as String,
        familyId: (json['familyId'] as String?) ?? '',
        month: (json['month'] as String?) ?? '',
        totalIncome: _parseNum(json['totalIncome']),
        totalExpense: _parseNum(json['totalExpense']),
        note: json['note'] as String?,
        contributions: ((json['contributions'] as List<dynamic>?) ?? [])
            .map((c) => BudgetContribution.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class BudgetContribution {
  const BudgetContribution({
    required this.id,
    required this.amount,
    this.note,
    this.userId,
    this.userName,
    this.createdAt,
  });

  final String id;
  final num amount;
  final String? note;
  final String? userId;
  final String? userName;
  final DateTime? createdAt;

  factory BudgetContribution.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    String? userName;
    if (user != null) {
      userName = [user['firstName'], user['lastName']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
    }
    userName ??= json['userName'] as String?;
    return BudgetContribution(
      id: json['id'] as String? ?? '',
      amount: _parseNum(json['amount']),
      note: json['note'] as String?,
      userId: json['userId'] as String? ?? (user?['id'] as String?),
      userName: userName,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

@immutable
class FamilyGoal {
  const FamilyGoal({
    required this.id,
    required this.familyId,
    required this.title,
    this.description,
    required this.targetAmount,
    this.currentAmount = 0,
    this.deadline,
    this.assignedTo,
    this.assignedToName,
    this.completed = false,
  });

  final String id;
  final String familyId;
  final String title;
  final String? description;
  final num targetAmount;
  final num currentAmount;
  final DateTime? deadline;
  final String? assignedTo;
  final String? assignedToName;
  final bool completed;

  double get progress => targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0;

  factory FamilyGoal.fromJson(Map<String, dynamic> json) => FamilyGoal(
        id: json['id'] as String,
        familyId: (json['familyId'] as String?) ?? '',
        title: json['title'] as String,
        description: json['description'] as String?,
        targetAmount: _parseNum(json['targetAmount']),
        currentAmount: _parseNum(json['currentAmount']),
        deadline: json['deadline'] != null ? DateTime.tryParse(json['deadline'] as String) : null,
        assignedTo: json['assignedTo'] as String?,
        assignedToName: json['assignedToName'] as String?,
        completed: (json['completed'] as bool?) ?? false,
      );
}

@immutable
class FamilyDashboard {
  const FamilyDashboard({
    required this.id,
    required this.name,
    this.description,
    this.inviteCode = '',
    this.myRole = 'MEMBER',
    this.members = const [],
    this.currentBudget,
    this.goals = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final String myRole;
  final List<FamilyMember> members;
  final FamilyBudget? currentBudget;
  final List<FamilyGoal> goals;

  bool get isAdmin => myRole == 'ADMIN';

  factory FamilyDashboard.fromJson(Map<String, dynamic> json) => FamilyDashboard(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        inviteCode: (json['inviteCode'] as String?) ?? '',
        myRole: (json['myRole'] as String?) ?? (json['role'] as String?) ?? 'MEMBER',
        members: ((json['members'] as List<dynamic>?) ?? [])
            .map((m) => FamilyMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        currentBudget: json['currentBudget'] != null
            ? FamilyBudget.fromJson(json['currentBudget'] as Map<String, dynamic>)
            : null,
        goals: ((json['goals'] as List<dynamic>?) ?? [])
            .map((g) => FamilyGoal.fromJson(g as Map<String, dynamic>))
            .toList(),
      );
}

num _parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

// ---------- PROVIDERS ----------

/// GET /family/mine — liste des familles auxquelles l'user appartient
final familiesProvider = FutureProvider<List<Family>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/family/mine');
  final data = r.data['families'] ?? r.data;
  return (data as List).map((j) => Family.fromJson(j as Map<String, dynamic>)).toList();
});

/// GET /family/:id — détails d'une famille
final familyDetailProvider = FutureProvider.family<Family, String>((ref, id) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/family/$id');
  final data = r.data['family'] ?? r.data;
  return Family.fromJson(data as Map<String, dynamic>);
});

/// GET /family/:id/dashboard — dashboard famille (members, currentBudget, goals)
final familyDashboardProvider = FutureProvider.family<FamilyDashboard, String>((ref, id) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/family/$id/dashboard');
  final data = r.data['dashboard'] ?? r.data['family'] ?? r.data;
  return FamilyDashboard.fromJson(data as Map<String, dynamic>);
});

/// GET /family/:id/budgets — liste des budgets familiaux
final familyBudgetsProvider = FutureProvider.family<List<FamilyBudget>, String>((ref, id) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/family/$id/budgets');
  final data = r.data['budgets'] ?? r.data;
  return (data as List).map((j) => FamilyBudget.fromJson(j as Map<String, dynamic>)).toList();
});

/// GET /family/:id/goals — objectifs familiaux
final familyGoalsProvider = FutureProvider.family<List<FamilyGoal>, String>((ref, id) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/family/$id/goals');
  final data = r.data['goals'] ?? r.data;
  return (data as List).map((j) => FamilyGoal.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- REPOSITORY ----------

class FamilyRepository {
  FamilyRepository(this._dio);
  final Dio _dio;

  /// POST /family { name, description? }
  Future<Family> createFamily({required String name, String? description}) async {
    final r = await _dio.post('/family', data: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    final data = r.data['family'] ?? r.data;
    return Family.fromJson(data as Map<String, dynamic>);
  }

  /// POST /family/join { inviteCode }
  Future<Family> joinFamily(String inviteCode) async {
    final r = await _dio.post('/family/join', data: {'inviteCode': inviteCode});
    final data = r.data['family'] ?? r.data;
    return Family.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /family/:id/leave
  Future<void> leaveFamily(String id) async {
    await _dio.delete('/family/$id/leave');
  }

  /// DELETE /family/:id/members/:userId (admin only)
  Future<void> removeMember(String familyId, String userId) async {
    await _dio.delete('/family/$familyId/members/$userId');
  }

  /// PATCH /family/:id (admin only)
  Future<Family> updateFamily(String id, {String? name, String? description}) async {
    final r = await _dio.patch('/family/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    });
    final data = r.data['family'] ?? r.data;
    return Family.fromJson(data as Map<String, dynamic>);
  }

  /// POST /family/:id/regenerate-code (admin only)
  Future<String> regenerateCode(String id) async {
    final r = await _dio.post('/family/$id/regenerate-code');
    final data = r.data;
    return (data['inviteCode'] as String?) ??
        (data['family'] != null ? (data['family']['inviteCode'] as String?) : null) ??
        '';
  }

  /// POST /family/:id/budgets { month, totalIncome?, totalExpense?, note? }
  Future<FamilyBudget> createBudget(
    String familyId, {
    required String month,
    num? totalIncome,
    num? totalExpense,
    String? note,
  }) async {
    final r = await _dio.post('/family/$familyId/budgets', data: {
      'month': month,
      if (totalIncome != null) 'totalIncome': totalIncome,
      if (totalExpense != null) 'totalExpense': totalExpense,
      if (note != null) 'note': note,
    });
    final data = r.data['budget'] ?? r.data;
    return FamilyBudget.fromJson(data as Map<String, dynamic>);
  }

  /// POST /family/budgets/:budgetId/contributions { amount, note? }
  Future<void> addContribution(String budgetId, {required num amount, String? note}) async {
    await _dio.post('/family/budgets/$budgetId/contributions', data: {
      'amount': amount,
      if (note != null) 'note': note,
    });
  }

  /// POST /family/:id/goals { title, description?, targetAmount, deadline?, assignedTo? }
  Future<FamilyGoal> createGoal(
    String familyId, {
    required String title,
    String? description,
    required num targetAmount,
    DateTime? deadline,
    String? assignedTo,
  }) async {
    final r = await _dio.post('/family/$familyId/goals', data: {
      'title': title,
      if (description != null) 'description': description,
      'targetAmount': targetAmount,
      if (deadline != null) 'deadline': deadline.toIso8601String(),
      if (assignedTo != null) 'assignedTo': assignedTo,
    });
    final data = r.data['goal'] ?? r.data;
    return FamilyGoal.fromJson(data as Map<String, dynamic>);
  }

  /// PATCH /family/goals/:goalId { title?, currentAmount?, completed? }
  Future<FamilyGoal> updateGoal(
    String goalId, {
    String? title,
    num? currentAmount,
    bool? completed,
  }) async {
    final r = await _dio.patch('/family/goals/$goalId', data: {
      if (title != null) 'title': title,
      if (currentAmount != null) 'currentAmount': currentAmount,
      if (completed != null) 'completed': completed,
    });
    final data = r.data['goal'] ?? r.data;
    return FamilyGoal.fromJson(data as Map<String, dynamic>);
  }
}

final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  return FamilyRepository(ref.watch(dioProvider));
});
