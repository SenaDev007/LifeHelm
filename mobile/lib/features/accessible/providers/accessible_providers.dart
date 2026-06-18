// Providers pour le Mode Accessible (boutique simplifiée)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class BoutiqueLog {
  const BoutiqueLog({
    required this.id,
    required this.date,
    this.openingCapital = 0,
    this.restockCost = 0,
    this.totalSales = 0,
    this.netProfit = 0,
    this.note,
  });

  final String id;
  final DateTime date;
  final num openingCapital;
  final num restockCost;
  final num totalSales;
  final num netProfit;
  final String? note;

  factory BoutiqueLog.fromJson(Map<String, dynamic> json) => BoutiqueLog(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        openingCapital: _num(json['openingCapital']),
        restockCost: _num(json['restockCost']),
        totalSales: _num(json['totalSales']),
        netProfit: _num(json['netProfit']),
        note: json['note'] as String?,
      );
}

@immutable
class AccessibleDashboard {
  const AccessibleDashboard({
    this.today,
    this.weekProfit = 0,
    this.recent = const [],
  });

  final BoutiqueLog? today;
  final num weekProfit;
  final List<BoutiqueLog> recent;

  factory AccessibleDashboard.fromJson(Map<String, dynamic> json) => AccessibleDashboard(
        today: json['today'] != null
            ? BoutiqueLog.fromJson(json['today'] as Map<String, dynamic>)
            : null,
        weekProfit: _num(json['weekProfit']),
        recent: ((json['recent'] as List<dynamic>?) ?? [])
            .map((b) => BoutiqueLog.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

num _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

// ---------- DASHBOARD ----------
final accessibleDashboardProvider = FutureProvider<AccessibleDashboard>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/accessible/dashboard');
  return AccessibleDashboard.fromJson(r.data as Map<String, dynamic>);
});

// ---------- REPOSITORY ----------
class AccessibleRepository {
  AccessibleRepository(this._dio);
  final Dio _dio;

  Future<BoutiqueLog> createBoutiqueLog(Map<String, dynamic> data) async {
    final r = await _dio.post('/accessible/boutique', data: data);
    return BoutiqueLog.fromJson(r.data['log'] as Map<String, dynamic>);
  }

  Future<BoutiqueLog> updateBoutiqueLog(String id, Map<String, dynamic> data) async {
    final r = await _dio.patch('/accessible/boutique/$id', data: data);
    return BoutiqueLog.fromJson(r.data['log'] as Map<String, dynamic>);
  }

  Future<void> deleteBoutiqueLog(String id) async {
    await _dio.delete('/accessible/boutique/$id');
  }
}

final accessibleRepositoryProvider = Provider<AccessibleRepository>((ref) {
  return AccessibleRepository(ref.watch(dioProvider));
});
