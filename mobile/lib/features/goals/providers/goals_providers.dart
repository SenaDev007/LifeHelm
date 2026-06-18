// Providers pour le module Goals (Objectifs de vie)
import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class LifeGoal {
  const LifeGoal({
    required this.id,
    required this.title,
    required this.domain,
    required this.type,
    this.priority = 3,
    this.targetValue,
    this.currentValue = 0,
    this.unit,
    this.deadline,
    this.description,
    this.completed = false,
    this.milestones = const [],
    this.completedMilestones = 0,
    this.createdAt,
  });

  final String id;
  final String title;
  final String domain; // HEALTH, CAREER, FAMILY, FINANCE, EDUCATION, SPIRITUAL, OTHER
  final String type; // BINARY, NUMERIC, MILESTONE
  final int priority; // 1 (high) -> 5 (low)
  final num? targetValue;
  final num currentValue;
  final String? unit;
  final DateTime? deadline;
  final String? description;
  final bool completed;
  final List<GoalMilestone> milestones;
  final int completedMilestones;
  final DateTime? createdAt;

  double get progress {
    if (completed) return 1;
    if (type == 'NUMERIC' && targetValue != null && targetValue! > 0) {
      return (currentValue / targetValue!).clamp(0.0, 1.0).toDouble();
    }
    if (type == 'MILESTONE' && milestones.isNotEmpty) {
      return (completedMilestones / milestones.length).clamp(0.0, 1.0).toDouble();
    }
    return 0;
  }

  factory LifeGoal.fromJson(Map<String, dynamic> json) => LifeGoal(
        id: json['id'] as String,
        title: json['title'] as String,
        domain: json['domain'] as String? ?? 'OTHER',
        type: json['type'] as String? ?? 'BINARY',
        priority: (json['priority'] as num?)?.toInt() ?? 3,
        targetValue: json['targetValue'] is String
            ? num.tryParse(json['targetValue'])
            : json['targetValue'] as num?,
        currentValue: json['currentValue'] is String
            ? num.tryParse(json['currentValue']) ?? 0
            : (json['currentValue'] as num?) ?? 0,
        unit: json['unit'] as String?,
        deadline: json['deadline'] != null ? DateTime.parse(json['deadline'] as String) : null,
        description: json['description'] as String?,
        completed: json['completed'] as bool? ?? false,
        milestones: ((json['milestones'] as List<dynamic>?) ?? [])
            .map((m) => GoalMilestone.fromJson(m as Map<String, dynamic>))
            .toList(),
        completedMilestones: (json['completedMilestones'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      );
}

@immutable
class GoalMilestone {
  const GoalMilestone({required this.id, required this.title, this.completed = false});
  final String id;
  final String title;
  final bool completed;

  factory GoalMilestone.fromJson(Map<String, dynamic> json) => GoalMilestone(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool? ?? false,
      );
}

// ---------- GOALS LIST ----------
final goalsProvider = FutureProvider<List<LifeGoal>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/goals');
  final list = r.data['goals'] as List? ?? r.data as List? ?? [];
  return list.map((j) => LifeGoal.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- GOAL REPOSITORY ----------
class GoalsRepository {
  GoalsRepository(this._dio);
  final Dio _dio;

  Future<LifeGoal> createGoal(Map<String, dynamic> data) async {
    final r = await _dio.post('/goals', data: data);
    return LifeGoal.fromJson(r.data['goal'] as Map<String, dynamic>);
  }

  Future<LifeGoal> updateGoal(String id, Map<String, dynamic> data) async {
    final r = await _dio.patch('/goals/$id', data: data);
    return LifeGoal.fromJson(r.data['goal'] as Map<String, dynamic>);
  }

  Future<void> deleteGoal(String id) async {
    await _dio.delete('/goals/$id');
  }

  Future<void> addProgress(String id, num increment) async {
    await _dio.post('/goals/$id/progress', data: {'increment': increment});
  }

  Future<void> toggleComplete(String id) async {
    await _dio.post('/goals/$id/complete');
  }
}

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository(ref.watch(dioProvider));
});

// Constantes helpers
class GoalDomains {
  GoalDomains._();

  static const Map<String, String> domainLabels = {
    'HEALTH': 'Santé',
    'CAREER': 'Carrière',
    'FAMILY': 'Famille',
    'FINANCE': 'Finance',
    'EDUCATION': 'Éducation',
    'SPIRITUAL': 'Spirituel',
    'OTHER': 'Autre',
  };

  static const Map<String, String> domainEmojis = {
    'HEALTH': '💪',
    'CAREER': '💼',
    'FAMILY': '👨‍👩‍👧',
    'FINANCE': '💰',
    'EDUCATION': '📚',
    'SPIRITUAL': '🧘',
    'OTHER': '🎯',
  };

  static const Map<String, Color> _colorMap = {
    'HEALTH': Color(0xFFEF4444),
    'CAREER': Color(0xFFF59E0B),
    'FAMILY': Color(0xFFEC4899),
    'FINANCE': Color(0xFF10B981),
    'EDUCATION': Color(0xFF8B5CF6),
    'SPIRITUAL': Color(0xFF3B82F6),
    'OTHER': Color(0xFF6B7280),
  };

  static Color colorOf(String domain) =>
      _colorMap[domain] ?? const Color(0xFF6B7280);
}

class GoalTypes {
  GoalTypes._();
  static const Map<String, String> typeLabels = {
    'BINARY': 'Oui / Non',
    'NUMERIC': 'Numérique',
    'MILESTONE': 'Étapes',
  };
}
