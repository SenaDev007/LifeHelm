// Providers pour le module SMS Import (V2)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

// ---------- MODELES ----------

@immutable
class SmsImport {
  const SmsImport({
    required this.id,
    required this.rawSms,
    required this.sender,
    this.receivedAt,
    this.imported = false,
    this.parsedData,
    this.transactionId,
    this.createdAt,
  });

  final String id;
  final String rawSms;
  final String sender;
  final DateTime? receivedAt;
  final bool imported;
  final Map<String, dynamic>? parsedData;
  final String? transactionId;
  final DateTime? createdAt;

  factory SmsImport.fromJson(Map<String, dynamic> json) => SmsImport(
        id: (json['id'] as String?) ?? '',
        rawSms: (json['rawSms'] as String?) ?? '',
        sender: (json['sender'] as String?) ?? '',
        receivedAt: json['receivedAt'] != null ? DateTime.tryParse(json['receivedAt'] as String) : null,
        imported: (json['imported'] as bool?) ?? false,
        parsedData: json['parsedData'] is Map<String, dynamic> ? json['parsedData'] as Map<String, dynamic> : null,
        transactionId: json['transactionId'] as String?,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}

// ---------- PROVIDERS ----------

/// GET /sms-imports?imported=false → liste des SMS
final smsImportsProvider = FutureProvider.family<List<SmsImport>, bool>((ref, importedOnly) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/sms-imports', queryParameters: {
    if (importedOnly) 'imported': 'false',
  });
  final data = r.data['smsImports'] ?? r.data['imports'] ?? r.data;
  if (data is! List) return [];
  return data.map((j) => SmsImport.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- REPOSITORY ----------

class SmsImportRepository {
  SmsImportRepository(this._dio);
  final Dio _dio;

  /// POST /sms-imports { rawSms, sender, receivedAt? } → sauver + parser
  Future<SmsImport> save({
    required String rawSms,
    required String sender,
    DateTime? receivedAt,
  }) async {
    final r = await _dio.post('/sms-imports', data: {
      'rawSms': rawSms,
      'sender': sender,
      if (receivedAt != null) 'receivedAt': receivedAt.toIso8601String(),
    });
    final data = r.data['smsImport'] ?? r.data['import'] ?? r.data;
    return SmsImport.fromJson(data as Map<String, dynamic>);
  }

  /// POST /sms-imports/:id/convert { accountId } → convertir en transaction
  Future<Map<String, dynamic>> convert(String id, String accountId) async {
    final r = await _dio.post('/sms-imports/$id/convert', data: {'accountId': accountId});
    return (r.data['transaction'] ?? r.data) as Map<String, dynamic>;
  }

  /// POST /sms-imports/preview { rawSms, sender } → parser sans sauver
  Future<Map<String, dynamic>> preview({required String rawSms, required String sender}) async {
    final r = await _dio.post('/sms-imports/preview', data: {
      'rawSms': rawSms,
      'sender': sender,
    });
    return (r.data['parsed'] ?? r.data['parsedData'] ?? r.data) as Map<String, dynamic>;
  }
}

final smsImportRepositoryProvider = Provider<SmsImportRepository>((ref) {
  return SmsImportRepository(ref.watch(dioProvider));
});
