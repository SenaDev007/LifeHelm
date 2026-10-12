// Providers pour les habitudes, le rituel du matin et la revue du soir.
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
    this.last30Days = const [],
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
  final List<bool> last30Days;
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
        lastSevenDays: _boolList(json['lastSevenDays']),
        last30Days: _boolList(json['last30Days']),
        completedToday: json['completedToday'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );

  static List<bool> _boolList(dynamic value) =>
      ((value as List<dynamic>?) ?? []).map((item) => item == true || item == 1).toList();
}

@immutable
class RitualStep {
  const RitualStep({required this.id, required this.label, this.type = 'CHECK', this.done = false, this.habitId});
  final String id;
  final String label;
  final String type;
  final bool done;
  final String? habitId;

  factory RitualStep.fromJson(Map<String, dynamic> json) => RitualStep(
        id: (json['id'] ?? json['key'] ?? json['label'] ?? 'step').toString(),
        label: (json['label'] ?? json['key'] ?? 'Étape').toString(),
        type: json['type'] as String? ?? 'CHECK',
        done: json['done'] as bool? ?? json['completed'] as bool? ?? false,
        habitId: json['habitId'] as String?,
      );
}

@immutable
class Ritual {
  const Ritual({
    this.steps = const [],
    this.completed = 0,
    this.total = 0,
    this.reflection,
    this.gratitude = const [],
  });
  final List<RitualStep> steps;
  final int completed;
  final int total;
  final String? reflection;
  final List<String> gratitude;

  factory Ritual.fromJson(Map<String, dynamic> json) {
    final raw = (json['ritual'] as Map<String, dynamic>?) ??
        (json['review'] as Map<String, dynamic>?) ?? json;
    final steps = ((raw['steps'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RitualStep.fromJson)
        .toList();
    final gratitude = ((raw['gratitude'] as List<dynamic>?) ?? []).map((item) => item.toString()).toList();
    return Ritual(
      steps: steps,
      completed: steps.isNotEmpty ? steps.where((step) => step.done).length : gratitude.length,
      total: steps.isNotEmpty ? steps.length : gratitude.length,
      reflection: raw['reflection'] as String?,
      gratitude: gratitude,
    );
  }
}

final habitsProvider = FutureProvider<List<Habit>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/habits');
  final list = r.data['habits'] as List? ?? r.data as List? ?? [];
  return list.map((j) => Habit.fromJson(j as Map<String, dynamic>)).toList();
});

final morningRitualProvider = FutureProvider<Ritual>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/morning-ritual');
  return Ritual.fromJson(r.data as Map<String, dynamic>);
});

final eveningReviewProvider = FutureProvider<Ritual>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/routines/evening-review');
  return Ritual.fromJson(r.data as Map<String, dynamic>);
});

class RoutinesRepository {
  RoutinesRepository(this._dio);
  final Dio _dio;

  Future<Habit> createHabit(Map<String, dynamic> data) async {
    final r = await _dio.post('/routines/habits', data: data);
    return Habit.fromJson(r.data['habit'] as Map<String, dynamic>);
  }

  Future<void> deleteHabit(String id) async { await _dio.delete('/routines/habits/$id'); }

  Future<void> logHabit(String id, {DateTime? date, bool? done}) async {
    final day = date ?? DateTime.now();
    await _dio.post('/routines/habits/$id/log', data: {
      'date': DateTime(day.year, day.month, day.day).toIso8601String(),
      if (done != null) 'completed': done,
    });
  }

  Future<void> unlogHabit(String id, {DateTime? date}) async {
    final day = date ?? DateTime.now();
    await _dio.delete('/routines/habits/$id/log', queryParameters: {
      'date': DateTime(day.year, day.month, day.day).toIso8601String(),
    });
  }

  Future<void> saveMorningRitual(List<RitualStep> steps) async {
    final now = DateTime.now();
    await _dio.post('/routines/morning-ritual', data: {
      'date': DateTime(now.year, now.month, now.day).toIso8601String(),
      'steps': steps.map((step) => {'key': step.id, 'label': step.label, 'completed': step.done}).toList(),
      'completed': steps.isNotEmpty && steps.every((step) => step.done),
    });
  }

  Future<void> saveEveningReview({
    required List<String> gratitude,
    String? reflection,
    List<String> topPriorities = const [],
    int? energyLevel,
  }) async {
    final now = DateTime.now();
    await _dio.post('/routines/evening-review', data: {
      'date': DateTime(now.year, now.month, now.day).toIso8601String(),
      'gratitude': gratitude.where((item) => item.trim().isNotEmpty).toList(),
      'reflection': reflection,
      'topPriorities': topPriorities.where((item) => item.trim().isNotEmpty).take(3).toList(),
      'energyLevel': energyLevel,
    });
  }
}

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) => RoutinesRepository(ref.watch(dioProvider)));
