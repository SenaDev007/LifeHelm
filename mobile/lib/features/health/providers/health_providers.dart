// Providers pour le module Health (Sommeil, Humeur, Activité, Hydratation)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class SleepLog {
  const SleepLog({
    required this.id,
    required this.date,
    required this.hours,
    this.quality = 3,
    this.bedtime,
    this.wakeTime,
    this.note,
  });

  final String id;
  final DateTime date;
  final double hours;
  final int quality; // 1-5
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final String? note;

  factory SleepLog.fromJson(Map<String, dynamic> json) => SleepLog(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        hours: (json['hours'] as num?)?.toDouble() ?? 0,
        quality: (json['quality'] as num?)?.toInt() ?? 3,
        bedtime: json['bedtime'] != null ? DateTime.parse(json['bedtime'] as String) : null,
        wakeTime: json['wakeTime'] != null ? DateTime.parse(json['wakeTime'] as String) : null,
        note: json['note'] as String?,
      );
}

@immutable
class MoodLog {
  const MoodLog({
    required this.id,
    required this.date,
    required this.mood,
    this.energy = 5,
    this.note,
  });

  final String id;
  final DateTime date;
  final int mood; // 1-5
  final int energy; // 1-10
  final String? note;

  factory MoodLog.fromJson(Map<String, dynamic> json) => MoodLog(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        mood: (json['mood'] as num?)?.toInt() ?? 3,
        energy: (json['energy'] as num?)?.toInt() ?? 5,
        note: json['note'] as String?,
      );
}

@immutable
class WorkoutLog {
  const WorkoutLog({
    required this.id,
    required this.date,
    required this.type,
    this.durationMin = 0,
    this.calories = 0,
    this.distance = 0,
    this.intensity = 3,
    this.note,
  });

  final String id;
  final DateTime date;
  final String type;
  final int durationMin;
  final num calories;
  final num distance;
  final int intensity;
  final String? note;

  factory WorkoutLog.fromJson(Map<String, dynamic> json) => WorkoutLog(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        type: json['type'] as String? ?? 'OTHER',
        durationMin: (json['durationMin'] as num?)?.toInt() ?? 0,
        calories: json['calories'] is String
            ? num.tryParse(json['calories']) ?? 0
            : (json['calories'] as num?) ?? 0,
        distance: json['distance'] is String
            ? num.tryParse(json['distance']) ?? 0
            : (json['distance'] as num?) ?? 0,
        intensity: (json['intensity'] as num?)?.toInt() ?? 3,
        note: json['note'] as String?,
      );
}

@immutable
class HydrationLog {
  const HydrationLog({
    this.todayMl = 0,
    this.goalMl = 2000,
    this.logs = const [],
  });

  final int todayMl;
  final int goalMl;
  final List<HydrationEntry> logs;

  double get progress => goalMl > 0 ? (todayMl / goalMl).clamp(0.0, 1.0) : 0;

  factory HydrationLog.fromJson(Map<String, dynamic> json) => HydrationLog(
        todayMl: (json['todayMl'] as num?)?.toInt() ?? 0,
        goalMl: (json['goalMl'] as num?)?.toInt() ?? 2000,
        logs: ((json['logs'] as List<dynamic>?) ?? [])
            .map((l) => HydrationEntry.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class HydrationEntry {
  const HydrationEntry({required this.id, required this.amountMl, required this.time});
  final String id;
  final int amountMl;
  final DateTime time;

  factory HydrationEntry.fromJson(Map<String, dynamic> json) => HydrationEntry(
        id: json['id'] as String,
        amountMl: (json['amountMl'] as num?)?.toInt() ?? 0,
        time: DateTime.parse(json['time'] as String),
      );
}

@immutable
class HealthDashboard {
  const HealthDashboard({
    this.score = 0,
    this.avgSleep = 0,
    this.avgEnergy = 0,
    this.weekWorkouts = 0,
    this.todayHydrationMl = 0,
    this.hydrationGoalMl = 2000,
    this.todayMood = 0,
    this.recentWorkouts = const [],
  });

  final int score;
  final double avgSleep;
  final double avgEnergy;
  final int weekWorkouts;
  final int todayHydrationMl;
  final int hydrationGoalMl;
  final int todayMood;
  final List<WorkoutLog> recentWorkouts;

  factory HealthDashboard.fromJson(Map<String, dynamic> json) => HealthDashboard(
        score: (json['score'] as num?)?.toInt() ?? 0,
        avgSleep: (json['avgSleep'] as num?)?.toDouble() ?? 0,
        avgEnergy: (json['avgEnergy'] as num?)?.toDouble() ?? 0,
        weekWorkouts: (json['weekWorkouts'] as num?)?.toInt() ?? 0,
        todayHydrationMl: (json['todayHydrationMl'] as num?)?.toInt() ?? 0,
        hydrationGoalMl: (json['hydrationGoalMl'] as num?)?.toInt() ?? 2000,
        todayMood: (json['todayMood'] as num?)?.toInt() ?? 0,
        recentWorkouts: ((json['recentWorkouts'] as List<dynamic>?) ?? [])
            .map((w) => WorkoutLog.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}

// ---------- PROVIDERS ----------
final sleepProvider = FutureProvider<List<SleepLog>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/health/sleep');
  final list = r.data['logs'] as List? ?? r.data['sleep'] as List? ?? [];
  return list.map((j) => SleepLog.fromJson(j as Map<String, dynamic>)).toList();
});

final moodProvider = FutureProvider<List<MoodLog>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/health/mood');
  final list = r.data['logs'] as List? ?? r.data['mood'] as List? ?? [];
  return list.map((j) => MoodLog.fromJson(j as Map<String, dynamic>)).toList();
});

final workoutsProvider = FutureProvider<List<WorkoutLog>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/health/workouts');
  final list = r.data['logs'] as List? ?? r.data['workouts'] as List? ?? [];
  return list.map((j) => WorkoutLog.fromJson(j as Map<String, dynamic>)).toList();
});

final hydrationProvider = FutureProvider<HydrationLog>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/health/hydration');
  return HydrationLog.fromJson(r.data as Map<String, dynamic>);
});

final healthDashboardProvider = FutureProvider<HealthDashboard>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/health/dashboard');
  return HealthDashboard.fromJson(r.data as Map<String, dynamic>);
});

// ---------- HEALTH REPOSITORY ----------
class HealthRepository {
  HealthRepository(this._dio);
  final Dio _dio;

  Future<SleepLog> addSleep(Map<String, dynamic> data) async {
    final r = await _dio.post('/health/sleep', data: data);
    return SleepLog.fromJson(r.data['log'] as Map<String, dynamic>);
  }

  Future<MoodLog> addMood(int mood, {int? energy, String? note}) async {
    final r = await _dio.post('/health/mood', data: {
      'mood': mood,
      if (energy != null) 'energy': energy,
      if (note != null) 'note': note,
    });
    return MoodLog.fromJson(r.data['log'] as Map<String, dynamic>);
  }

  Future<WorkoutLog> addWorkout(Map<String, dynamic> data) async {
    final r = await _dio.post('/health/workouts', data: data);
    return WorkoutLog.fromJson(r.data['log'] as Map<String, dynamic>);
  }

  Future<HydrationLog> addHydration(int amountMl) async {
    final r = await _dio.post('/health/hydration', data: {'amountMl': amountMl});
    return HydrationLog.fromJson(r.data as Map<String, dynamic>);
  }
}

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref.watch(dioProvider));
});

class WorkoutTypes {
  WorkoutTypes._();
  static const Map<String, String> workoutLabels = {
    'WALK': 'Marche',
    'RUN': 'Course',
    'BIKE': 'Vélo',
    'STRENGTH': 'Renforcement',
    'YOGA': 'Yoga',
    'FOOTBALL': 'Football',
    'DANCE': 'Danse',
    'SWIM': 'Natation',
    'OTHER': 'Autre',
  };
  static const Map<String, String> workoutEmojis = {
    'WALK': '🚶',
    'RUN': '🏃',
    'BIKE': '🚴',
    'STRENGTH': '💪',
    'YOGA': '🧘',
    'FOOTBALL': '⚽',
    'DANCE': '💃',
    'SWIM': '🏊',
    'OTHER': '🎯',
  };
}
