import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../db/database.dart';
import '../providers.dart' show dbProvider;
import 'token_store.dart';

export 'token_store.dart' show LhUser, LhStoredSession;

// ══════════════════════════ EXCEPTIONS TYPÉES ══════════════════════════

/// Erreur renvoyée par le serveur (statut HTTP + code métier éventuel).
class LhApiException implements Exception {
  LhApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String? code;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'LhApiException($statusCode, $code) : $message';
}

/// Indisponibilité réseau (hors ligne, DNS, timeout…).
class LhNetworkException implements Exception {
  LhNetworkException([this.message = 'Réseau indisponible']);

  final String message;

  @override
  String toString() => 'LhNetworkException : $message';
}

/// Traduction française des codes d'erreur serveur.
String apiErrorText(Object error) {
  if (error is LhNetworkException) {
    return 'Connexion impossible — vérifiez votre réseau ou l\'URL du serveur.';
  }
  if (error is LhApiException) {
    switch (error.code) {
      case 'INVALID_CREDENTIALS':
        return 'Identifiants incorrects.';
      case 'TOTP_INVALID':
        return 'Code de vérification incorrect.';
      case 'TOTP_REQUIRED':
        return 'Code de vérification requis.';
      case 'EMAIL_TAKEN':
        return 'Ce courriel est déjà utilisé par un compte.';
      case 'PHONE_TAKEN':
        return 'Ce numéro de téléphone est déjà utilisé par un compte.';
      case 'INVALID_TOKEN':
      case 'TOKEN_REUSED':
      case 'UNAUTHORIZED':
        return 'Session expirée — reconnectez-vous.';
      case 'INVALID_RESET_TOKEN':
        return 'Code de réinitialisation invalide ou expiré.';
      default:
        if (error.message.isNotEmpty) return error.message;
        return 'Erreur serveur (${error.statusCode}).';
    }
  }
  return 'Une erreur inattendue est survenue.';
}

// ══════════════════════════ RÉSULTAT D'AUTHENTIFICATION ══════════════════════════

/// Réponse des endpoints /auth/register et /auth/login.
class LhAuthResult {
  const LhAuthResult(
      {required this.user,
      required this.accessToken,
      required this.refreshToken,
      required this.expiresIn});

  final LhUser user;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  LhStoredSession toSession() => LhStoredSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        user: user,
      );
}

/// Session d'appareil telle que renvoyée par GET /auth/sessions.
class LhDeviceSession {
  const LhDeviceSession({
    required this.id,
    required this.deviceName,
    this.ip,
    required this.createdAt,
    required this.lastUsedAt,
    required this.current,
  });

  final String id;
  final String deviceName;
  final String? ip;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final bool current;

  factory LhDeviceSession.fromJson(Map<String, dynamic> json) =>
      LhDeviceSession(
        id: json['id'] as String,
        deviceName: (json['deviceName'] as String?) ?? 'Appareil inconnu',
        ip: json['ip'] as String?,
        createdAt: json['createdAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['createdAt'] as String),
        lastUsedAt: json['lastUsedAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['lastUsedAt'] as String),
        current: (json['current'] as bool?) ?? false,
      );
}

// ══════════════════════════ ÉTAT DE SESSION ══════════════════════════

/// État de session exposé à l'UI : anonyme ou connecté.
class LhSessionState {
  const LhSessionState(
      {this.status = 'anonymous', this.user, this.lastError});

  static const anonymous = LhSessionState();

  final String status; // 'anonymous' | 'connected'
  final LhUser? user;
  final String? lastError;

  bool get isConnected => status == 'connected';
}

/// Notifieur de session : écoute le [TokenStore] + les expirations
/// signalées par l'[ApiClient] (refresh impossible → session effacée).
class SessionNotifier extends StateNotifier<LhSessionState> {
  SessionNotifier(this._store, this._client) : super(LhSessionState.anonymous) {
    _init();
  }

  final TokenStore _store;
  final ApiClient _client;
  StreamSubscription<LhStoredSession?>? _storeSub;
  StreamSubscription<void>? _expiredSub;

  Future<void> _init() async {
    final session = await _store.load();
    if (session != null && session.user != null) {
      state = LhSessionState(status: 'connected', user: session.user);
    }
    _storeSub = _store.changes.listen((session) {
      if (session == null || session.user == null) {
        state = LhSessionState.anonymous;
      } else {
        state = LhSessionState(status: 'connected', user: session.user);
      }
    });
    _expiredSub = _client.onSessionExpired.listen((_) {
      // Le refresh a échoué : la session a déjà été effacée par le client.
      state = const LhSessionState(
          status: 'anonymous', lastError: 'Session expirée — reconnectez-vous.');
    });
  }

  /// Recharge le profil depuis le serveur (GET /auth/me).
  Future<void> refreshUser() async {
    if (!state.isConnected) return;
    try {
      final user = await _client.me();
      await _store.updateUser(user);
    } on LhNetworkException {
      // Hors ligne : on garde le profil en cache, silencieux.
    } on LhApiException {
      // 401 déjà géré par le client (refresh) — sinon profil inchangé.
    }
  }

  @override
  void dispose() {
    _storeSub?.cancel();
    _expiredSub?.cancel();
    super.dispose();
  }
}

// ══════════════════════════ CLIENT HTTP ══════════════════════════

/// Client REST LifeHelm — contrats {baseUrl}/api/v1 (CDC §3).
///
/// - `baseUrl` lu depuis le réglage `apiBaseUrl` (défaut `/api/v1`,
///   chemin relatif same-origin pour le web ; URL complète sur mobile) ;
/// - Bearer automatique + rafraîchissement sur 401 puis **une** retry ;
/// - exceptions typées [LhApiException] / [LhNetworkException].
class ApiClient {
  ApiClient(
      {required AppDatabase database,
      required TokenStore tokenStore,
      http.Client? httpClient})
      : _db = database,
        _store = tokenStore,
        _inner = httpClient;

  static const String defaultBaseUrl = '/api/v1';

  final AppDatabase _db;
  final TokenStore _store;
  final http.Client? _inner;
  String? _cachedBaseUrl;

  final _sessionExpired = StreamController<void>.broadcast();
  Future<bool>? _refreshing;

  /// Émis quand le refresh a échoué et que la session a été effacée.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  /// Invalide le cache d'URL (après changement en Paramètres).
  void invalidateBaseUrl() => _cachedBaseUrl = null;

  Future<String> _baseUrl() async {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;
    _cachedBaseUrl =
        (await _db.getSetting('apiBaseUrl')) ?? defaultBaseUrl;
    return _cachedBaseUrl!;
  }

  Uri _resolveUri(String base, String pathAndQuery) {
    if (base.startsWith('http://') || base.startsWith('https://')) {
      return Uri.parse('$base$pathAndQuery');
    }
    if (base.startsWith('/')) {
      if (!kIsWeb) {
        // Sur mobile, un chemin relatif n'a pas d'origine : l'utilisateur
        // doit renseigner une URL complète dans Paramètres.
        throw LhNetworkException(
            'URL du serveur incomplète — renseignez une URL complète '
            '(https://…) dans Paramètres → Avancé.');
      }
      return Uri.base.resolve('$base$pathAndQuery');
    }
    throw LhNetworkException('URL du serveur invalide : « $base ».');
  }

  http.Client get _client => _inner ?? http.Client();

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final base = await _baseUrl();
    final uri = _resolveUri(base, path);
    final payload = body == null ? null : jsonEncode(body);

    Future<http.Response> attempt() async {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (payload != null) 'Content-Type': 'application/json',
      };
      if (auth) {
        final session = await _store.load();
        if (session != null) headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (payload != null) request.body = payload;
      final response =
          await _client.send(request).then(http.Response.fromStream);
      return response;
    }

    http.Response response;
    try {
      response = await attempt();
    } on LhNetworkException {
      rethrow;
    } catch (_) {
      throw LhNetworkException();
    }

    // 401 sur une requête authentifiée → refresh puis UNE retry.
    if (response.statusCode == 401 && auth) {
      bool refreshed;
      try {
        refreshed = await _tryRefresh();
      } on LhNetworkException {
        // Réseau mort pendant le refresh : on ne déconnecte pas.
        throw LhNetworkException();
      }
      if (refreshed) {
        try {
          response = await attempt();
        } on LhNetworkException {
          rethrow;
        } catch (_) {
          throw LhNetworkException();
        }
      } else {
        throw LhApiException(401, 'UNAUTHORIZED', 'Session expirée');
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const {};
      try {
        return Map<String, dynamic>.from(
            jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      } catch (_) {
        return const {};
      }
    }

    String? code;
    var message = '';
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      code = decoded['code'] as String?;
      message = (decoded['message'] as String?) ?? '';
    } catch (_) {
      // Corps non JSON : code générique.
    }
    throw LhApiException(response.statusCode, code, message);
  }

  /// POST /auth/refresh avec le refreshToken du store.
  /// Retourne false (et efface la session) si le refresh est REFUSÉ
  /// (INVALID_TOKEN / TOKEN_REUSED). Une indisponibilité réseau ne
  /// déconnecte jamais l'utilisateur : l'exception est relancée.
  Future<bool> _tryRefresh() async {
    _refreshing ??= _doRefresh();
    try {
      return await _refreshing!;
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> _doRefresh() async {
    final session = await _store.load();
    if (session == null) return false;
    try {
      final data = await _send('POST', '/auth/refresh',
          body: {'refreshToken': session.refreshToken}, auth: false);
      final expiresIn = (data['expiresIn'] as num?)?.toInt() ?? 3600;
      await _store.save(LhStoredSession(
        accessToken: data['accessToken'] as String,
        refreshToken:
            (data['refreshToken'] as String?) ?? session.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        user: session.user,
      ));
      return true;
    } on LhNetworkException {
      // Serveur injoignable : la session locale reste valide.
      rethrow;
    } catch (_) {
      // Refresh refusé (INVALID_TOKEN / TOKEN_REUSED) : session effacée.
      await _store.clear();
      _sessionExpired.add(null);
      return false;
    }
  }

  // ── Verbes génériques ──

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  // ── Authentification (sans Bearer) ──

  Future<LhAuthResult> register({
    String? email,
    String? phone,
    required String password,
    required String firstName,
    String? lastName,
    String? deviceName,
  }) async {
    final data = await _send('POST', '/auth/register',
        body: {
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'password': password,
          'firstName': firstName,
          if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
          if (deviceName != null && deviceName.isNotEmpty)
            'deviceName': deviceName,
        },
        auth: false);
    return _authResult(data);
  }

  Future<LhAuthResult> login({
    required String identifier,
    required String password,
    String? totpCode,
    String? deviceName,
  }) async {
    final data = await _send('POST', '/auth/login',
        body: {
          'identifier': identifier,
          'password': password,
          if (totpCode != null && totpCode.isNotEmpty) 'totpCode': totpCode,
          if (deviceName != null && deviceName.isNotEmpty)
            'deviceName': deviceName,
        },
        auth: false);
    return _authResult(data);
  }

  LhAuthResult _authResult(Map<String, dynamic> data) => LhAuthResult(
        user: LhUser.fromJson(
            Map<String, dynamic>.from(data['user'] as Map)),
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        expiresIn: (data['expiresIn'] as num?)?.toInt() ?? 3600,
      );

  Future<void> logout(String refreshToken) async {
    await _send('POST', '/auth/logout',
        body: {'refreshToken': refreshToken}, auth: false);
  }

  // ── Compte (Bearer) ──

  Future<LhUser> me() async {
    final data = await get('/auth/me');
    return LhUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<void> logoutAll() async {
    await post('/auth/logout-all');
  }

  Future<List<LhDeviceSession>> sessions() async {
    final data = await get('/auth/sessions');
    final list = (data['sessions'] as List? ?? [])
        .map((s) => LhDeviceSession.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    return list;
  }

  Future<void> revokeSession(String id) async {
    await delete('/auth/sessions/$id');
  }

  Future<void> changePassword(
      {required String currentPassword, required String newPassword}) async {
    await post('/auth/password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        });
  }

  Future<Map<String, dynamic>> forgotPassword(String identifier) async {
    return _send('POST', '/auth/password/forgot',
        body: {'identifier': identifier}, auth: false);
  }

  Future<void> resetPassword(
      {required String resetToken, required String newPassword}) async {
    await _send('POST', '/auth/password/reset',
        body: {'resetToken': resetToken, 'newPassword': newPassword},
        auth: false);
  }

  Future<void> enable2fa(String totpCode) async {
    await post('/auth/2fa/enable', body: {'totpCode': totpCode});
  }

  Future<void> disable2fa(String totpCode) async {
    await post('/auth/2fa/disable', body: {'totpCode': totpCode});
  }

  Future<({String secret, String otpauthUrl})> setup2fa() async {
    final data = await post('/auth/2fa/setup');
    return (
      secret: data['secret'] as String,
      otpauthUrl: data['otpauthUrl'] as String,
    );
  }

  /// Libère les ressources (contrôleur d'événements de session).
  void dispose() {
    _sessionExpired.close();
  }
}

// ══════════════════════════ PROVIDERS RIVERPOD ══════════════════════════

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    database: ref.watch(dbProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

final sessionProvider =
    StateNotifierProvider<SessionNotifier, LhSessionState>((ref) {
  return SessionNotifier(
    ref.watch(tokenStoreProvider),
    ref.watch(apiClientProvider),
  );
});
