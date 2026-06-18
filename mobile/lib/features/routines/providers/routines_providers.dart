// Providers pour le module Routines (Habitudes + rituels matin/soir)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class Habit {
  const Habit({
    required this.id,
    required this.name,
    this.description,
    this.icon = '✅',
    this.color,
    this.frequency = 'DAILY',
    this.targetCount = 1,
    this.streak = 0,
    this.bestStreak = 0,
    this.lastSevenDays = const [],
    this.completedToday = false,
    this.active = true,
  });

  final String id;
  final String name;
  final String? description;
  final String icon;
  final String? color;
  final String frequency;
  final int targetCount;
  final int streak;
  final int bestStreak;
  final List<bool> lastSevenDays;
  final bool completedToday;
  final bool active;

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String? ?? '✅',
        color: json['color'] as String?,
        frequency: json['frequency'] as String? ?? 'DAILY',
        targetCount: (json['targetCount'] as num?)?.toInt() ?? 1,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['bestStreak'] as num?)?.toInt() ?? 0,
        lastSevenDays: ((json['lastSevenDays'] as List<dynamic>?) ?? [])
            .map((e) => e == true || e == 1)
            .toList(),
        completedToday: json['completedToday'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );
}

@immutable
class RitualStep {
  const RitualStep({
    required this.id,
    required this.label,
    this.type = 'CHECK',
    this.done = false,
    this.habitId,
  });

  final String id;
  final String label;
  final String type;
  final bool done;
  final String? habitId;

  factory RitualStep.fromJson(Map<String, dynamic> json) => RitualStep(
        id: json['id'] as String,
        label: json['label'] as String,
        type: json['type'] as String? ?? 'CHECK',
        done: json['done'] as bool? ?? false,
        habitId: json['habitId'] as String?,
      );
}

@immutable
class Ritual {
  const Ritual({this.steps = const [], this.completed = 0, this.total = 0});
  final List<RitualStep> steps;
  final int completed;
  final int total;

  factory Ritual.fromJson(Map<String, dynamic> json) => Ritual(
        steps: ((json['steps'] as List<dynamic>?) ?? [])
            .map((s) => RitualStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}

// ---------- HABITS ----------
final habitsProvider = FutureProvider<List<Habit>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/habits');
  final list = r.data['habits'] as List? ?? r.data as List? ?? [];
  return list.map((j) => Habit.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- MORNING RITUAL ----------
final morningRitualProvider = FutureProvider<Ritual>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/morning-ritual');
  return Ritual.fromJson(r.data as Map<String, dynamic>);
});

// ---------- EVENING REVIEW ----------
final eveningReviewProvider = FutureProvider<Ritual>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/evening-review');
  return Ritual.fromJson(r.data as Map<String, dynamic>);
});

// ---------- ROUTINES REPOSITORY ----------
class RoutinesRepository {
  RoutinesRepository(this._dio);
  final Dio _dio;

  Future<Habit> createHabit(Map<String, dynamic> data) async {
    final r = await _dio.post('/routines/habits', data: data);
    return Habit.fromJson(r.data['habit'] as Map<String, dynamic>);
  }

  Future<void> deleteHabit(String id) async {
    await _dio.delete('/routines/habits/$id');
  }

  Future<void> logHabit(String id, {DateTime? date, bool? done}) async {
    await _dio.post('/routines/habits/$id/log', data: {
      'date': (date ?? DateTime.now()).toIso8601String(),
      if (done != null) 'done': done,
    });
  }

  Future<void> unlogHabit(String id, {DateTime? date}) async {
    await _dio.delete('/routines/habits/$id/log', queryParameters: {
      'date': (date ?? DateTime.now()).toIso8601String(),
    });
  }
}

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) {
  return RoutinesRepository(ref.watch(dioProvider));
});
