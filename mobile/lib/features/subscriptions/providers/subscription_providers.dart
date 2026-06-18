// Providers pour le module Abonnements (V2)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_service.dart';

// ---------- MODELES ----------

@immutable
class PlanPricing {
  const PlanPricing({
    this.monthly = 0,
    this.annual = 0,
  });

  final num monthly;
  final num annual;

  factory PlanPricing.fromJson(Map<String, dynamic> json) => PlanPricing(
        monthly: _parseNum(json['monthly']),
        annual: _parseNum(json['annual']),
      );
}

@immutable
class PlansInfo {
  const PlansInfo({
    this.free = const PlanPricing(),
    this.pro = const PlanPricing(),
    this.family = const PlanPricing(),
  });

  final PlanPricing free;
  final PlanPricing pro;
  final PlanPricing family;

  PlanPricing forPlan(String plan) {
    switch (plan.toUpperCase()) {
      case 'PRO': return pro;
      case 'FAMILY': return family;
      default: return free;
    }
  }

  factory PlansInfo.fromJson(Map<String, dynamic> json) => PlansInfo(
        free: json['FREE'] != null ? PlanPricing.fromJson(json['FREE'] as Map<String, dynamic>) : const PlanPricing(),
        pro: json['PRO'] != null ? PlanPricing.fromJson(json['PRO'] as Map<String, dynamic>) : const PlanPricing(),
        family: json['FAMILY'] != null ? PlanPricing.fromJson(json['FAMILY'] as Map<String, dynamic>) : const PlanPricing(),
      );
}

@immutable
class CurrentSubscription {
  const CurrentSubscription({
    this.id = '',
    this.plan = 'FREE',
    this.period = 'MONTHLY',
    this.status = 'INACTIVE',
    this.amount = 0,
    this.startedAt,
    this.expiresAt,
    this.autoRenew = false,
    this.method,
  });

  final String id;
  final String plan; // FREE | PRO | FAMILY
  final String period; // MONTHLY | ANNUAL
  final String status; // ACTIVE | EXPIRED | CANCELLED | PENDING | INACTIVE
  final num amount;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  final String? method; // MTN | MOOV | WAVE | CARD

  bool get isActive => status == 'ACTIVE';

  factory CurrentSubscription.fromJson(Map<String, dynamic> json) => CurrentSubscription(
        id: (json['id'] as String?) ?? '',
        plan: (json['plan'] as String?) ?? 'FREE',
        period: (json['period'] as String?) ?? 'MONTHLY',
        status: (json['status'] as String?) ?? 'INACTIVE',
        amount: _parseNum(json['amount']),
        startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'] as String) : null,
        expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
        autoRenew: (json['autoRenew'] as bool?) ?? false,
        method: json['method'] as String?,
      );
}

@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.status,
    required this.method,
    this.plan,
    this.period,
    this.reference,
    this.createdAt,
    this.errorMessage,
  });

  final String id;
  final num amount;
  final String status; // SUCCESS | FAILED | PENDING | CANCELLED
  final String method;
  final String? plan;
  final String? period;
  final String? reference;
  final DateTime? createdAt;
  final String? errorMessage;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: (json['id'] as String?) ?? '',
        amount: _parseNum(json['amount']),
        status: (json['status'] as String?) ?? 'PENDING',
        method: (json['method'] as String?) ?? '',
        plan: json['plan'] as String?,
        period: json['period'] as String?,
        reference: json['reference'] as String?,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        errorMessage: json['errorMessage'] as String?,
      );
}

@immutable
class PaymentInitiation {
  const PaymentInitiation({
    required this.paymentId,
    this.fedaPayId,
    this.checkoutUrl,
  });

  final String paymentId;
  final String? fedaPayId;
  final String? checkoutUrl;

  factory PaymentInitiation.fromJson(Map<String, dynamic> json) => PaymentInitiation(
        paymentId: (json['paymentId'] as String?) ?? '',
        fedaPayId: json['fedaPayId'] as String?,
        checkoutUrl: json['checkoutUrl'] as String?,
      );
}

num _parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

// ---------- PROVIDERS ----------

/// GET /subscriptions/plans → { FREE, PRO, FAMILY }
final plansProvider = FutureProvider<PlansInfo>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/subscriptions/plans');
  final data = r.data['plans'] ?? r.data;
  return PlansInfo.fromJson(data as Map<String, dynamic>);
});

/// GET /subscriptions/current → abonnement actuel
final currentSubscriptionProvider = FutureProvider<CurrentSubscription>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/subscriptions/current');
  final data = r.data['subscription'] ?? r.data;
  if (data == null) return const CurrentSubscription();
  return CurrentSubscription.fromJson(data as Map<String, dynamic>);
});

/// GET /subscriptions/payments → historique des paiements
final paymentsHistoryProvider = FutureProvider<List<PaymentRecord>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/subscriptions/payments');
  final data = r.data['payments'] ?? r.data;
  return (data as List).map((j) => PaymentRecord.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- REPOSITORY ----------

class SubscriptionRepository {
  SubscriptionRepository(this._dio);
  final Dio _dio;

  /// POST /subscriptions/initiate { plan, period, method, phone?, callbackUrl? }
  /// → { paymentId, fedaPayId, checkoutUrl }
  Future<PaymentInitiation> initiatePayment({
    required String plan,
    required String period,
    required String method,
    String? phone,
    String? callbackUrl,
  }) async {
    final r = await _dio.post('/subscriptions/initiate', data: {
      'plan': plan,
      'period': period,
      'method': method,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (callbackUrl != null) 'callbackUrl': callbackUrl,
    });
    final data = r.data['payment'] ?? r.data;
    return PaymentInitiation.fromJson(data as Map<String, dynamic>);
  }

  /// POST /subscriptions/verify/:paymentId → vérifier statut paiement
  Future<Map<String, dynamic>> verifyPayment(String paymentId) async {
    final r = await _dio.post('/subscriptions/verify/$paymentId');
    return (r.data['payment'] ?? r.data) as Map<String, dynamic>;
  }

  /// POST /subscriptions/cancel → désactiver auto-renew
  Future<void> cancelSubscription() async {
    await _dio.post('/subscriptions/cancel');
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(dioProvider));
});

// ---------- HELPERS ----------

class PaymentMethods {
  PaymentMethods._();

  static const Map<String, String> labels = {
    'MTN': 'MTN MoMo',
    'MOOV': 'Moov Money',
    'WAVE': 'Wave',
    'CARD': 'Carte bancaire',
  };

  static const Map<String, IconData> icons = {
    'MTN': Icons.phone_android,
    'MOOV': Icons.phone_android,
    'WAVE': Icons.waves,
    'CARD': Icons.credit_card,
  };

  static const List<String> all = ['MTN', 'MOOV', 'WAVE', 'CARD'];

  static bool isMoMo(String method) => method == 'MTN' || method == 'MOOV' || method == 'WAVE';
}
