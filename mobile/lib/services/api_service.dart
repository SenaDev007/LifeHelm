// Service API central (Dio)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.apiTimeout,
    receiveTimeout: AppConfig.apiTimeout,
    sendTimeout: AppConfig.apiTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
      logPrint: (o) => debugPrint('[API] $o'),
    ));
  }

  // Interceptor pour injecter le token
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      // Si 401, on tente un refresh
      if (error.response?.statusCode == 401) {
        const storage = FlutterSecureStorage();
        final refreshToken = await storage.read(key: 'refresh_token');
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
            final r = await refreshDio.post('/auth/refresh', options: Options(
              headers: {'Cookie': 'refresh_token=$refreshToken'},
            ));
            final newToken = r.data['accessToken'] as String;
            await storage.write(key: 'access_token', value: newToken);
            // Retry
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final clone = await dio.fetch(error.requestOptions);
            return handler.resolve(clone);
          } catch (_) {
            await storage.deleteAll();
          }
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});

// Auth state
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final Map<String, dynamic>? user;
  final String? errorMessage;

  AuthState copyWith({AuthStatus? status, Map<String, dynamic>? user, String? errorMessage}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        errorMessage: errorMessage,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._dio) : super(const AuthState()) {
    _init();
  }

  final Dio _dio;

  Future<void> _init() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final r = await _dio.get('/auth/me');
      state = AuthState(status: AuthStatus.authenticated, user: r.data['user'] as Map<String, dynamic>?);
    } catch (_) {
      await storage.deleteAll();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
    String? phone,
  }) async {
    try {
      final r = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
      });
      await _storeTokens(r.data);
      state = AuthState(status: AuthStatus.authenticated, user: r.data['user'] as Map<String, dynamic>?);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(errorMessage: _extractError(e));
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    try {
      final r = await _dio.post('/auth/login', data: {'email': email, 'password': password});
      await _storeTokens(r.data);
      state = AuthState(status: AuthStatus.authenticated, user: r.data['user'] as Map<String, dynamic>?);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(errorMessage: _extractError(e));
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> refreshUser() async {
    try {
      final r = await _dio.get('/auth/me');
      state = AuthState(status: AuthStatus.authenticated, user: r.data['user'] as Map<String, dynamic>?);
    } catch (_) {}
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    const storage = FlutterSecureStorage();
    final accessToken = data['accessToken'] as String?;
    if (accessToken != null) {
      await storage.write(key: 'access_token', value: accessToken);
    }
    // Refresh token est en cookie httpOnly côté backend — on ne peut pas le lire côté Flutter.
    // Pour le mobile, on stocke aussi le refresh token si l'API le renvoie dans le body.
    // (À adapter si le backend mobile renvoie les deux tokens dans le body.)
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      final err = data['error'] as String;
      switch (err) {
        case 'INVALID_CREDENTIALS':
          return 'Email ou mot de passe incorrect';
        case 'EMAIL_TAKEN':
          return 'Cet email est déjà utilisé';
        case 'INVALID_INPUT':
          return 'Données invalides';
        default:
          return err;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      return 'Connexion au serveur impossible. Vérifie ton réseau.';
    }
    return 'Une erreur est survenue';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(dioProvider));
});
