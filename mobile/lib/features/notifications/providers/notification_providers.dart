// Providers pour le module Notifications (V2)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

// ---------- MODELES ----------

@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.read = false,
    this.data,
    this.createdAt,
    this.scheduledFor,
  });

  final String id;
  final String type; // FINANCE | HEALTH | ROUTINES | GOALS | FAMILY | SUBSCRIPTION | SYSTEM | etc.
  final String title;
  final String body;
  final bool read;
  final Map<String, dynamic>? data;
  final DateTime? createdAt;
  final DateTime? scheduledFor;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: (json['id'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'SYSTEM',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        read: (json['read'] as bool?) ?? false,
        data: json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : null,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        scheduledFor: json['scheduledFor'] != null ? DateTime.tryParse(json['scheduledFor'] as String) : null,
      );
}

@immutable
class NotificationsResult {
  const NotificationsResult({
    this.notifications = const [],
    this.unreadCount = 0,
  });

  final List<NotificationItem> notifications;
  final int unreadCount;

  factory NotificationsResult.fromJson(Map<String, dynamic> json) => NotificationsResult(
        notifications: ((json['notifications'] as List<dynamic>?) ?? [])
            .map((n) => NotificationItem.fromJson(n as Map<String, dynamic>))
            .toList(),
        unreadCount: (json['unreadCount'] as int?) ?? 0,
      );
}

// ---------- PROVIDERS ----------

/// GET /notifications?limit=50&unread=true → liste + unreadCount
final notificationsProvider = FutureProvider<NotificationsResult>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/notifications', queryParameters: {'limit': 50});
  final data = r.data;
  // Le backend peut renvoyer soit { notifications, unreadCount } soit { data: [...] }
  if (data is Map<String, dynamic> && data['notifications'] != null) {
    return NotificationsResult.fromJson(data);
  }
  if (data is Map<String, dynamic> && data['data'] is List) {
    final list = (data['data'] as List).map((n) => NotificationItem.fromJson(n as Map<String, dynamic>)).toList();
    final unread = list.where((n) => !n.read).length;
    return NotificationsResult(notifications: list, unreadCount: unread);
  }
  if (data is List) {
    final list = data.map((n) => NotificationItem.fromJson(n as Map<String, dynamic>)).toList();
    final unread = list.where((n) => !n.read).length;
    return NotificationsResult(notifications: list, unreadCount: unread);
  }
  return const NotificationsResult();
});

/// Provider simple qui ne renvoie que le nombre de notifications non lues
final unreadCountProvider = FutureProvider<int>((ref) async {
  final result = await ref.watch(notificationsProvider.future);
  return result.unreadCount;
});

// ---------- REPOSITORY ----------

class NotificationRepository {
  NotificationRepository(this._dio);
  final Dio _dio;

  /// POST /notifications/:id/read → marquer comme lu
  Future<void> markRead(String id) async {
    await _dio.post('/notifications/$id/read');
  }

  /// POST /notifications/read-all → tout marquer lu
  Future<void> markAllRead() async {
    await _dio.post('/notifications/read-all');
  }

  /// DELETE /notifications/:id
  Future<void> delete(String id) async {
    await _dio.delete('/notifications/$id');
  }

  /// POST /notifications/schedule { type, title, body, scheduledFor, data? }
  Future<void> schedule({
    required String type,
    required String title,
    required String body,
    required DateTime scheduledFor,
    Map<String, dynamic>? data,
  }) async {
    await _dio.post('/notifications/schedule', data: {
      'type': type,
      'title': title,
      'body': body,
      'scheduledFor': scheduledFor.toIso8601String(),
      if (data != null) 'data': data,
    });
  }

  /// POST /notifications/generate-daily → génère notifs intelligentes du jour
  Future<void> generateDaily() async {
    await _dio.post('/notifications/generate-daily');
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(dioProvider));
});

// ---------- HELPERS ----------

class NotificationTypes {
  NotificationTypes._();

  static const Map<String, String> typeLabels = {
    'FINANCE': 'Finance',
    'HEALTH': 'Santé',
    'ROUTINES': 'Routines',
    'GOALS': 'Objectifs',
    'FAMILY': 'Famille',
    'SUBSCRIPTION': 'Abonnement',
    'SYSTEM': 'Système',
    'INSIGHT': 'Insight',
    'REMINDER': 'Rappel',
  };

  static String label(String type) => typeLabels[type.toUpperCase()] ?? type;
}
