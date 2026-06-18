// Providers pour le module Settings (préférences & objectifs)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class UserSettings {
  const UserSettings({
    this.notificationsEnabled = true,
    this.dailyReminderTime = '08:00',
    this.weeklyReportDay = 'SUNDAY',
    this.weeklyReportTime = '18:00',
    this.sleepGoalHours = 8.0,
    this.hydrationGoalMl = 2000,
    this.weeklyWorkoutsGoal = 3,
    this.monthlySavingsRate = 20,
    this.language = 'FR',
    this.appMode = 'STANDARD',
  });

  final bool notificationsEnabled;
  final String dailyReminderTime;
  final String weeklyReportDay;
  final String weeklyReportTime;
  final double sleepGoalHours;
  final int hydrationGoalMl;
  final int weeklyWorkoutsGoal;
  final int monthlySavingsRate;
  final String language;
  final String appMode;

  UserSettings copyWith({
    bool? notificationsEnabled,
    String? dailyReminderTime,
    String? weeklyReportDay,
    String? weeklyReportTime,
    double? sleepGoalHours,
    int? hydrationGoalMl,
    int? weeklyWorkoutsGoal,
    int? monthlySavingsRate,
    String? language,
    String? appMode,
  }) =>
      UserSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
        weeklyReportDay: weeklyReportDay ?? this.weeklyReportDay,
        weeklyReportTime: weeklyReportTime ?? this.weeklyReportTime,
        sleepGoalHours: sleepGoalHours ?? this.sleepGoalHours,
        hydrationGoalMl: hydrationGoalMl ?? this.hydrationGoalMl,
        weeklyWorkoutsGoal: weeklyWorkoutsGoal ?? this.weeklyWorkoutsGoal,
        monthlySavingsRate: monthlySavingsRate ?? this.monthlySavingsRate,
        language: language ?? this.language,
        appMode: appMode ?? this.appMode,
      );

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        dailyReminderTime: json['dailyReminderTime'] as String? ?? '08:00',
        weeklyReportDay: json['weeklyReportDay'] as String? ?? 'SUNDAY',
        weeklyReportTime: json['weeklyReportTime'] as String? ?? '18:00',
        sleepGoalHours: (json['sleepGoalHours'] as num?)?.toDouble() ?? 8.0,
        hydrationGoalMl: (json['hydrationGoalMl'] as num?)?.toInt() ?? 2000,
        weeklyWorkoutsGoal: (json['weeklyWorkoutsGoal'] as num?)?.toInt() ?? 3,
        monthlySavingsRate: (json['monthlySavingsRate'] as num?)?.toInt() ?? 20,
        language: json['language'] as String? ?? 'FR',
        appMode: json['appMode'] as String? ?? 'STANDARD',
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'dailyReminderTime': dailyReminderTime,
        'weeklyReportDay': weeklyReportDay,
        'weeklyReportTime': weeklyReportTime,
        'sleepGoalHours': sleepGoalHours,
        'hydrationGoalMl': hydrationGoalMl,
        'weeklyWorkoutsGoal': weeklyWorkoutsGoal,
        'monthlySavingsRate': monthlySavingsRate,
        'language': language,
        'appMode': appMode,
      };
}

// ---------- SETTINGS PROVIDER ----------
final settingsProvider = FutureProvider<UserSettings>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/settings');
  return UserSettings.fromJson((r.data['settings'] ?? r.data) as Map<String, dynamic>);
});

// ---------- SETTINGS REPOSITORY ----------
class SettingsRepository {
  SettingsRepository(this._dio);
  final Dio _dio;

  Future<UserSettings> update(Map<String, dynamic> data) async {
    final r = await _dio.patch('/settings', data: data);
    return UserSettings.fromJson((r.data['settings'] ?? r.data) as Map<String, dynamic>);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(dioProvider));
});

class WeekDays {
  WeekDays._();
  static const Map<String, String> dayLabels = {
    'MONDAY': 'Lundi',
    'TUESDAY': 'Mardi',
    'WEDNESDAY': 'Mercredi',
    'THURSDAY': 'Jeudi',
    'FRIDAY': 'Vendredi',
    'SATURDAY': 'Samedi',
    'SUNDAY': 'Dimanche',
  };
}
