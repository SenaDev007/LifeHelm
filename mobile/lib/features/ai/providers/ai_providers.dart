// Providers pour HELM AI
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_service.dart';

final aiInsightsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/ai/insights');
  return (r.data['insights'] as List).cast<Map<String, dynamic>>().toList();
});

final aiConversationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/ai/conversations');
  return (r.data['conversations'] as List).cast<Map<String, dynamic>>().toList();
});

class AiRepository {
  AiRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> createConversation({String? title}) async {
    final r = await _dio.post('/ai/conversations', data: {'title': title});
    return r.data['conversation'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(String conversationId, String content) async {
    final r = await _dio.post('/ai/conversations/$conversationId/messages', data: {'content': content});
    return r.data['message'] as Map<String, dynamic>;
  }

  Future<void> markInsightRead(String id) async {
    await _dio.post('/ai/insights/$id/read');
  }

  Future<void> refreshInsights() async {
    await _dio.get('/ai/insights', queryParameters: {'refresh': 'true'});
  }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(dioProvider)));
