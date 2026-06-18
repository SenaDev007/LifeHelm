// Providers pour le module Finance
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../services/api_service.dart';

// ---------- ACCOUNTS ----------
final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/accounts');
  return (r.data['accounts'] as List).map((j) => Account.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- TRANSACTIONS ----------
final transactionsProvider = FutureProvider.family<List<Transaction>, int>((ref, limit) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/transactions', queryParameters: {'limit': limit});
  return (r.data['transactions'] as List).map((j) => Transaction.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- FINANCE DASHBOARD ----------
final financeDashboardProvider = FutureProvider<FinanceDashboard>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/dashboard');
  return FinanceDashboard.fromJson(r.data as Map<String, dynamic>);
});

// ---------- SAVINGS GOALS ----------
final savingsGoalsProvider = FutureProvider<List<SavingsGoal>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/savings-goals');
  return (r.data['savingsGoals'] as List).map((j) => SavingsGoal.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- TONTINES ----------
final tontinesProvider = FutureProvider<List<Tontine>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/tontines');
  return (r.data['tontines'] as List).map((j) => Tontine.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- DEBTS ----------
final debtsProvider = FutureProvider<List<Debt>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/debts');
  return (r.data['debts'] as List).map((j) => Debt.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- BILLS ----------
final billsProvider = FutureProvider<List<Bill>>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/finance/bills');
  return (r.data['bills'] as List).map((j) => Bill.fromJson(j as Map<String, dynamic>)).toList();
});

// ---------- HOME DASHBOARD ----------
final homeDashboardProvider = FutureProvider<HomeDashboard>((ref) async {
  final dio = ref.watch(dioProvider);
  ref.watch(authProvider);
  final r = await dio.get('/home');
  return HomeDashboard.fromJson(r.data as Map<String, dynamic>);
});

// ---------- MUTATIONS ----------
class FinanceRepository {
  FinanceRepository(this._dio);
  final Dio _dio;

  Future<Account> createAccount(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/accounts', data: data);
    return Account.fromJson(r.data['account'] as Map<String, dynamic>);
  }

  Future<void> updateAccount(String id, Map<String, dynamic> data) async {
    await _dio.patch('/finance/accounts/$id', data: data);
  }

  Future<void> deleteAccount(String id) async {
    await _dio.delete('/finance/accounts/$id');
  }

  Future<Transaction> createTransaction(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/transactions', data: data);
    return Transaction.fromJson(r.data['transaction'] as Map<String, dynamic>);
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> data) async {
    await _dio.patch('/finance/transactions/$id', data: data);
  }

  Future<void> deleteTransaction(String id) async {
    await _dio.delete('/finance/transactions/$id');
  }

  Future<SavingsGoal> createSavingsGoal(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/savings-goals', data: data);
    return SavingsGoal.fromJson(r.data['savingsGoal'] as Map<String, dynamic>);
  }

  Future<void> updateSavingsGoal(String id, Map<String, dynamic> data) async {
    await _dio.patch('/finance/savings-goals/$id', data: data);
  }

  Future<void> contributeToSavingsGoal(String id, num amount) async {
    await _dio.post('/finance/savings-goals/$id/contribute', data: {'amount': amount});
  }

  Future<void> deleteSavingsGoal(String id) async {
    await _dio.delete('/finance/savings-goals/$id');
  }

  Future<Tontine> createTontine(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/tontines', data: data);
    return Tontine.fromJson(r.data['tontine'] as Map<String, dynamic>);
  }

  Future<void> deleteTontine(String id) async {
    await _dio.delete('/finance/tontines/$id');
  }

  Future<Debt> createDebt(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/debts', data: data);
    return Debt.fromJson(r.data['debt'] as Map<String, dynamic>);
  }

  Future<void> updateDebt(String id, Map<String, dynamic> data) async {
    await _dio.patch('/finance/debts/$id', data: data);
  }

  Future<void> settleDebt(String id) async {
    await _dio.post('/finance/debts/$id/settle');
  }

  Future<void> deleteDebt(String id) async {
    await _dio.delete('/finance/debts/$id');
  }

  Future<Bill> createBill(Map<String, dynamic> data) async {
    final r = await _dio.post('/finance/bills', data: data);
    return Bill.fromJson(r.data['bill'] as Map<String, dynamic>);
  }

  Future<void> payBill(String id) async {
    await _dio.post('/finance/bills/$id/pay');
  }

  Future<void> deleteBill(String id) async {
    await _dio.delete('/finance/bills/$id');
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(dioProvider));
});
