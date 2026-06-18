// Providers pour le module Exports (V2)
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

@immutable
class ExportJob {
  const ExportJob({
    required this.id,
    required this.type,
    required this.format,
    required this.status,
    this.year,
    this.month,
    this.url,
    this.errorMessage,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String type; // MONTHLY_REPORT | TRANSACTIONS_CSV
  final String format; // html | csv | pdf
  final String status; // PENDING | COMPLETED | FAILED
  final int? year;
  final int? month;
  final String? url;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory ExportJob.fromJson(Map<String, dynamic> json) => ExportJob(
        id: (json['id'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        format: (json['format'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PENDING',
        year: json['year'] is int ? json['year'] as int : int.tryParse(json['year']?.toString() ?? ''),
        month: json['month'] is int ? json['month'] as int : int.tryParse(json['month']?.toString() ?? ''),
        url: json['url'] as String?,
        errorMessage: json['errorMessage'] as String?,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      );
}

/// GET /exports/jobs → historique exports
final exportJobsProvider = FutureProvider<List<ExportJob>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/exports/jobs');
  final data = r.data['jobs'] ?? r.data;
  if (data is! List) return [];
  return data.map((j) => ExportJob.fromJson(j as Map<String, dynamic>)).toList();
});
