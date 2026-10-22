import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
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
    return 'Connexion impossible — vérifiez votre réseau.';
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
        return 'Erreur de connexion (${error.statusCode}).';
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
/// - `baseUrl` lu depuis le réglage `apiBaseUrl` ; défauts :
///   web → `/api/v1` (same-origin, preview), mobile → serveur de prod Railway ;
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

  /// Serveur par défaut sur mobile (production Railway) — tant que
  /// l'utilisateur ne définit pas d'URL complète dans Paramètres → Avancé.
  static const String defaultServerUrl =
      'https://lifehelm-production.up.railway.app/api/v1';

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
    _cachedBaseUrl = (await _db.getSetting('apiBaseUrl')) ??
        (kIsWeb ? defaultBaseUrl : defaultServerUrl);
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
            'Connexion impossible — vérifiez votre réseau.');
      }
      return Uri.base.resolve('$base$pathAndQuery');
    }
    throw LhNetworkException('Connexion impossible — vérifiez votre réseau.');
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

  Future<Map<String, dynamic>> patch(String path,
          {Map<String, dynamic>? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<Map<String, dynamic>> put(String path,
          {Map<String, dynamic>? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<Map<String, dynamic>> delete(String path,
          {Map<String, dynamic>? body, bool auth = true}) =>
      _send('DELETE', path, body: body, auth: auth);

  // ── Authentification (sans Bearer) ──

  Future<LhAuthResult> register({
    String? email,
    String? phone,
    required String password,
    required String firstName,
    String? lastName,
    String? profession,
    String? country,
    String? deviceName,
  }) async {
    final data = await _send('POST', '/auth/register',
        body: {
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'password': password,
          'firstName': firstName,
          if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
          if (profession != null && profession.isNotEmpty)
            'profession': profession,
          if (country != null && country.isNotEmpty) 'country': country,
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

  /// Met à jour le profil serveur (PATCH /auth/profile).
  /// Retourne le profil rafraîchi.
  Future<LhUser> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? profession,
    String? country,
    String? avatarUrl,
  }) async {
    final data = await patch('/auth/profile', body: {
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phone != null) 'phone': phone,
      if (profession != null) 'profession': profession,
      if (country != null) 'country': country,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    });
    return LhUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  /// Suppression DÉFINITIVE du compte et de toutes ses données serveur
  /// (DELETE /auth/account). Exige le mot de passe courant.
  Future<void> deleteAccount(String password) async {
    await delete('/auth/account', body: {'password': password});
  }

  // ── Questions de sécurité (récupération du compte) ──

  /// Enregistre les questions/réponses (réponses hachées sha256 côté client).
  Future<void> setSecurityQuestions(
      List<({String question, String answerHash})> items) async {
    await post('/auth/security-questions', body: {
      'items': [
        for (final i in items)
          {'question': i.question, 'answerHash': i.answerHash}
      ],
    });
  }

  /// Questions publiques d'un compte (écran de récupération).
  /// Retourne null si le compte n'en a pas défini.
  Future<List<String>?> securityQuestionsOf(String identifier) async {
    final data = await _send(
        'GET',
        '/auth/security-questions?identifier='
        '${Uri.encodeComponent(identifier)}',
        auth: false);
    final raw = data['questions'];
    if (raw == null) return null;
    return (raw as List).map((q) => q as String).toList();
  }

  /// Vérifie les réponses aux questions de sécurité : si elles sont
  /// correctes, renvoie un jeton de réinitialisation (comme « mot de passe
  /// oublié ») utilisable via [resetPassword].
  Future<String> recoverBySecurityQuestions(
      String identifier, Map<int, String> answerHashes) async {
    final data = await _send('POST', '/auth/recover',
        body: {
          'identifier': identifier,
          'answers': {
            for (final e in answerHashes.entries) '${e.key}': e.value,
          },
        },
        auth: false);
    return data['resetToken'] as String;
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

  // ── HELM AI (Dossier 17 — Phase 1) ──

  /// Disponibilité de l'assistant (AVAILABLE / OFFLINE, jamais mensonger).
  Future<LhAiStatus> aiStatus() async {
    final data = await get('/ai/status');
    return LhAiStatus.fromJson(data);
  }

  Future<String> aiCreateConversation(
      {String entryPoint = 'CENTRAL_ASSISTANT', String? moduleContext}) async {
    final data = await post('/ai/conversations', body: {
      'entryPoint': entryPoint,
      if (moduleContext != null) 'moduleContext': moduleContext,
    });
    return data['id'] as String;
  }

  Future<List<LhAiConversationSummary>> aiListConversations() async {
    final data = await get('/ai/conversations');
    final list = data['conversations'] as List? ?? [];
    return list
        .map((c) =>
            LhAiConversationSummary.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  /// Conversation + messages (null si introuvable / non autorisé).
  Future<LhAiConversation?> aiGetConversation(String id) async {
    final data = await get('/ai/conversations/$id');
    return LhAiConversation.fromJson(data);
  }

  Future<void> aiDeleteConversation(String id) async {
    await delete('/ai/conversations/$id');
  }

  /// Envoie une demande et renvoie la réponse structurée HELM AI.
  Future<LhAiAnswer> aiSendMessage(String conversationId, String message) async {
    final data = await post('/ai/conversations/$conversationId/messages',
        body: {'message': message});
    return LhAiAnswer.fromJson(data);
  }

  // ── HELM AI Phase 2 — actions confirmées, préférences, usage ──

  /// Détail d'une action (statut, expiration paresseuse incluse).
  Future<LhAiActionDetail> aiGetAction(String id) async {
    final data = await get('/ai/actions/$id');
    return LhAiActionDetail.fromJson(data);
  }

  /// Confirme puis exécute une action — [payloadHash] = preuve que
  /// l'utilisateur a vu exactement ce qui sera exécuté ;
  /// [idempotencyKey] = UUID généré POUR CETTE tentative (double-tap sûr).
  Future<LhAiActionDetail> aiConfirmAction(
      String id, String payloadHash, String idempotencyKey) async {
    final data = await post('/ai/actions/$id/confirm',
        body: {'payloadHash': payloadHash, 'idempotencyKey': idempotencyKey});
    return LhAiActionDetail.fromJson(data);
  }

  /// Refuse une action proposée.
  Future<void> aiCancelAction(String id, {String? reason}) async {
    await post('/ai/actions/$id/cancel',
        body: {if (reason != null) 'reason': reason});
  }

  /// Préférences HELM AI (autonomie, périmètre de contexte, alertes).
  Future<LhAiPreferences> aiGetPreferences() async {
    final data = await get('/ai/preferences');
    return LhAiPreferences.fromJson(data);
  }

  Future<LhAiPreferences> aiUpdatePreferences(
      Map<String, dynamic> changes) async {
    final data = await patch('/ai/preferences', body: changes);
    return LhAiPreferences.fromJson(data);
  }

  /// Compteurs d'usage (messages, actions, quota 24 h).
  Future<LhAiUsage> aiUsage() async {
    final data = await get('/ai/usage');
    return LhAiUsage.fromJson(data);
  }

  // ── HELM AI Phase 3 — briefing, alertes, consentements (D17.6) ──

  /// Briefing du jour (sections structurées + accroche + alertes du jour).
  /// Généré côté serveur au premier appel du jour, en cache ensuite.
  Future<LhAiBriefingResponse> aiGetBriefing({String? date}) async {
    final data = await get('/ai/briefing${date != null ? '?date=$date' : ''}');
    return LhAiBriefingResponse.fromJson(data);
  }

  /// Alertes intelligentes (filtre optionnel : UNREAD | READ | DISMISSED).
  Future<List<LhAiAlert>> aiListAlerts({String? status}) async {
    final data =
        await get('/ai/alerts${status != null ? '?status=$status' : ''}');
    final list = data['alerts'] as List? ?? [];
    return list
        .map((a) => LhAiAlert.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList();
  }

  /// Marque une alerte comme lue (idempotent).
  Future<LhAiAlert> aiMarkAlertRead(String id) async {
    final data = await post('/ai/alerts/$id/read');
    return LhAiAlert.fromJson(data);
  }

  /// Ignore une alerte (elle ne reviendra pas pour la même période).
  Future<LhAiAlert> aiDismissAlert(String id) async {
    final data = await post('/ai/alerts/$id/dismiss');
    return LhAiAlert.fromJson(data);
  }

  /// Catalogue des consentements granulaires (périmètres sensibles).
  Future<List<LhAiConsent>> aiGetConsents() async {
    final data = await get('/ai/consents');
    final list = data['scopes'] as List? ?? [];
    return list
        .map((c) => LhAiConsent.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  /// Octroie / retire un consentement — journalisé côté serveur.
  Future<LhAiConsent> aiSetConsent(String scope, bool granted) async {
    final data = await put('/ai/consents/$scope', body: {'granted': granted});
    return LhAiConsent.fromJson(data);
  }

  // ── Notifications push natives du briefing (D17.6) ──

  /// Enregistre l'appareil pour le push FCM (upsert par jeton côté serveur).
  /// Retourne l'identifiant serveur de l'appareil (désinscription future).
  Future<String> pushRegisterDevice({
    required String token,
    String? deviceId,
    String appVersion = '0.3.0',
  }) async {
    final platform = kIsWeb
        ? 'WEB'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'ANDROID',
            TargetPlatform.iOS => 'IOS',
            _ => 'WEB',
          };
    final data = await post('/push/devices', body: {
      'token': token,
      'platform': platform,
      if (deviceId != null) 'deviceId': deviceId,
      'appVersion': appVersion,
    });
    return data['id'] as String;
  }

  /// Retire l'appareil enregistré (arrêt des notifications serveur).
  Future<void> pushUnregisterDevice(String serverDeviceId) async {
    await delete('/push/devices/$serverDeviceId');
  }

  /// Statut push du serveur (READY / DEGRADED + appareils actifs).
  Future<Map<String, dynamic>> pushStatus() async => get('/push/status');

  /// Libère les ressources (contrôleur d'événements de session).
  void dispose() {
    _sessionExpired.close();
  }
}
// ══════════════════════════ MODÈLES HELM AI (D17) ══════════════════════════

/// Disponibilité de l'assistant (AVAILABLE / OFFLINE — D17.3 §17.4).
class LhAiStatus {
  const LhAiStatus(
      {required this.available, this.model, required this.capabilities});
  final bool available;
  final String? model;
  final List<String> capabilities;

  factory LhAiStatus.fromJson(Map<String, dynamic> json) => LhAiStatus(
        available: json['available'] == true,
        model: json['model'] as String?,
        capabilities: (json['capabilities'] as List? ?? [])
            .map((c) => c as String)
            .toList(),
      );
}

class LhAiConversationSummary {
  const LhAiConversationSummary(
      {required this.id, this.title, required this.updatedAt});
  final String id;
  final String? title;
  final DateTime updatedAt;

  factory LhAiConversationSummary.fromJson(Map<String, dynamic> json) =>
      LhAiConversationSummary(
        id: json['id'] as String,
        title: json['title'] as String?,
        updatedAt: json['updatedAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['updatedAt'] as String),
      );
}

/// Message d'une conversation (rôle utilisateur ou assistant).
class LhAiMessage {
  const LhAiMessage(
      {required this.role,
      required this.content,
      this.answerType,
      this.structured});
  final String role; // USER | ASSISTANT
  final String content;
  final String? answerType;
  final Map<String, dynamic>? structured;

  factory LhAiMessage.fromJson(Map<String, dynamic> json) => LhAiMessage(
        role: json['role'] as String? ?? 'USER',
        content: json['content'] as String? ?? '',
        answerType: json['answerType'] as String?,
        structured: json['structured'] == null
            ? null
            : Map<String, dynamic>.from(json['structured'] as Map),
      );
}

class LhAiConversation {
  const LhAiConversation(
      {required this.id, this.title, required this.messages});
  final String id;
  final String? title;
  final List<LhAiMessage> messages;

  factory LhAiConversation.fromJson(Map<String, dynamic> json) =>
      LhAiConversation(
        id: json['id'] as String,
        title: json['title'] as String?,
        messages: (json['messages'] as List? ?? [])
            .map((m) => LhAiMessage.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );
}

/// Fait vérifié cité par HELM AI (valeur réellement lue dans les modules).
class LhAiFact {
  const LhAiFact({required this.key, required this.value});
  final String key;
  final String value;

  factory LhAiFact.fromJson(Map<String, dynamic> json) => LhAiFact(
        key: json['key'] as String? ?? '',
        value: '${json['value'] ?? ''}',
      );
}

/// Action proposée par HELM AI — JAMAIS exécutée sans confirmation
/// explicite de l'utilisateur (cycle D17.2 §6).
///
/// Phase 2 : les propositions matérielles côté serveur portent un [id]
/// et un [payloadHash] — la confirmation passe par /ai/actions/:id/confirm.
/// Une proposition sans [id] (repli hors-ligne) reste appliquable localement.
class LhAiProposedAction {
  const LhAiProposedAction({
    required this.actionType,
    required this.title,
    this.id,
    this.summary,
    this.payload,
    this.payloadHash,
    this.expiresAt,
    this.status,
    this.dueDate,
    this.priority = 'NORMAL',
  });
  final String actionType; // CREATE_TASK_DRAFT | PROPOSE_EVENT_CHANGE | PROPOSE_FINANCIAL_CORRECTION | CREATE_TASK (repli)
  final String title;
  final String? id; // présent = action serveur confirmable
  final String? summary;
  final Map<String, dynamic>? payload;
  final String? payloadHash; // preuve d'identité du contenu confirmé
  final DateTime? expiresAt;
  final String? status; // AWAITING_CONFIRMATION | SUCCEEDED | …
  final String? dueDate; // repli local CREATE_TASK
  final String priority;

  bool get isServerAction => id != null && payloadHash != null;
  bool get confirmable =>
      isServerAction && (status == null || status == 'AWAITING_CONFIRMATION');

  factory LhAiProposedAction.fromJson(Map<String, dynamic> json) =>
      LhAiProposedAction(
        actionType: json['actionType'] as String? ?? 'CREATE_TASK',
        title: json['title'] as String? ?? '',
        id: json['id'] as String?,
        summary: json['summary'] as String?,
        payload: json['payload'] == null
            ? null
            : Map<String, dynamic>.from(json['payload'] as Map),
        payloadHash: json['payloadHash'] as String?,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'] as String),
        status: json['status'] as String?,
        dueDate: json['dueDate'] as String?,
        priority: json['priority'] as String? ?? 'NORMAL',
      );
}

/// Détail/état d'une action (réponse de GET/confirm — D17.2 §6.4).
class LhAiActionDetail {
  const LhAiActionDetail({
    required this.id,
    required this.actionType,
    required this.status,
    required this.title,
    this.summary,
    this.result,
    this.error,
    this.expiresAt,
  });
  final String id;
  final String actionType;
  final String status; // AWAITING_CONFIRMATION | SUCCEEDED | FAILED | CANCELLED | EXPIRED | …
  final String title;
  final String? summary;
  final Map<String, dynamic>? result; // { resourceId, serverVersion, kind }
  final Map<String, dynamic>? error; // { code, message }
  final DateTime? expiresAt;

  factory LhAiActionDetail.fromJson(Map<String, dynamic> json) =>
      LhAiActionDetail(
        id: json['id'] as String,
        actionType: json['actionType'] as String? ?? '',
        status: json['status'] as String? ?? 'AWAITING_CONFIRMATION',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String?,
        result: json['result'] == null
            ? null
            : Map<String, dynamic>.from(json['result'] as Map),
        error: json['error'] == null
            ? null
            : Map<String, dynamic>.from(json['error'] as Map),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'] as String),
      );
}

/// Préférences HELM AI (D17.2 §7.2) — autonomie, alertes, périmètre.
class LhAiPreferences {
  const LhAiPreferences({
    this.autonomyLevel = 'SUGGEST',
    this.alertThreshold = 'NORMAL',
    this.contextScope = const {},
    this.dailyBriefing = false,
    this.briefingHour = 7,
  });
  final String autonomyLevel; // SUGGEST | PREPARE | ASSIST
  final String alertThreshold; // INFORMATION | NORMAL | IMPORTANT
  final Map<String, dynamic> contextScope; // { finance, tasks, agenda, projects, notes }
  final bool dailyBriefing;
  final int briefingHour;

  bool scope(String key) => contextScope[key] == true;

  factory LhAiPreferences.fromJson(Map<String, dynamic> json) =>
      LhAiPreferences(
        autonomyLevel: json['autonomyLevel'] as String? ?? 'SUGGEST',
        alertThreshold: json['alertThreshold'] as String? ?? 'NORMAL',
        contextScope: json['contextScope'] == null
            ? const {}
            : Map<String, dynamic>.from(json['contextScope'] as Map),
        dailyBriefing: json['dailyBriefing'] == true,
        briefingHour: (json['briefingHour'] as num?)?.toInt() ?? 7,
      );
}

/// Compteurs d'usage sur 24 h (D17.2 §7.5).
class LhAiUsage {
  const LhAiUsage({
    this.messages = 0,
    this.messageQuota = 60,
    this.actionsConfirmed = 0,
    this.averageLatencyMs = 0,
  });
  final int messages;
  final int messageQuota;
  final int actionsConfirmed;
  final int averageLatencyMs;

  factory LhAiUsage.fromJson(Map<String, dynamic> json) => LhAiUsage(
        messages: (json['messages'] as num?)?.toInt() ?? 0,
        messageQuota: (json['messageQuota'] as num?)?.toInt() ?? 60,
        actionsConfirmed: (json['actionsConfirmed'] as num?)?.toInt() ?? 0,
        averageLatencyMs: (json['averageLatencyMs'] as num?)?.toInt() ?? 0,
      );
}

/// Réponse structurée HELM AI (contrat D17.4 §4.2) : réponse, faits
/// vérifiés, hypothèses, incertitudes, actions proposées et drapeaux
class LhAiAnswer {
  const LhAiAnswer({
    required this.answer,
    this.answerType = 'INFORMATION',
    this.facts = const [],
    this.assumptions = const [],
    this.uncertainties = const [],
    this.safetyFlags = const [],
    this.proposedActions = const [],
    this.requiresConfirmation = false,
    this.degraded = false,
    this.latencyMs,
  });
  final String answer;
  final String answerType;
  final List<LhAiFact> facts;
  final List<String> assumptions;
  final List<String> uncertainties;
  final List<String> safetyFlags;
  final List<LhAiProposedAction> proposedActions;
  final bool requiresConfirmation;
  final bool degraded;
  final int? latencyMs;

  factory LhAiAnswer.fromJson(Map<String, dynamic> json) => LhAiAnswer(
        answer: json['answer'] as String? ?? '',
        answerType: json['answerType'] as String? ?? 'INFORMATION',
        facts: (json['facts'] as List? ?? [])
            .map((f) => LhAiFact.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
        assumptions: (json['assumptions'] as List? ?? [])
            .map((a) => a as String)
            .toList(),
        uncertainties: (json['uncertainties'] as List? ?? [])
            .map((u) => u as String)
            .toList(),
        safetyFlags: (json['safetyFlags'] as List? ?? [])
            .map((s) => s as String)
            .toList(),
        proposedActions: (json['proposedActions'] as List? ?? [])
            .map((a) =>
                LhAiProposedAction.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
        requiresConfirmation: json['requiresConfirmation'] == true,
        degraded: json['degraded'] == true,
        latencyMs: (json['latencyMs'] as num?)?.toInt(),
      );
}

// ════════════════ MODÈLES HELM AI PHASE 3 (D17.6) ════════════════

/// Réponse du point d'entrée briefing : soit `{enabled: false}` (opt-in
/// absent), soit le briefing du jour + les alertes associées.
class LhAiBriefingResponse {
  const LhAiBriefingResponse({
    required this.enabled,
    this.briefingHour,
    this.briefing,
    this.alerts = const [],
    this.generatedNow = false,
  });
  final bool enabled;
  final int? briefingHour; // heure choisie quand le briefing est désactivé
  final LhAiBriefing? briefing;
  final List<LhAiAlert> alerts;
  final bool generatedNow;

  factory LhAiBriefingResponse.fromJson(Map<String, dynamic> json) =>
      LhAiBriefingResponse(
        enabled: json['enabled'] == true,
        briefingHour: (json['briefingHour'] as num?)?.toInt(),
        briefing: json['briefing'] == null
            ? null
            : LhAiBriefing.fromJson(
                Map<String, dynamic>.from(json['briefing'] as Map)),
        alerts: (json['alerts'] as List? ?? [])
            .map((a) => LhAiAlert.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
        generatedNow: json['generatedNow'] == true,
      );
}

/// Briefing quotidien — accroche rédigée + sections structurées
/// (agenda, tâches, finances, budgets, échéances, prêts, projets,
/// bien-être/messagerie si consentis).
class LhAiBriefing {
  const LhAiBriefing({
    required this.date,
    required this.headline,
    required this.message,
    required this.sections,
    required this.alertCount,
    required this.generatedBy,
    required this.degraded,
    required this.createdAt,
  });
  final String date; // AAAA-MM-JJ
  final String headline;
  final String message;
  final Map<String, dynamic> sections;
  final int alertCount;
  final String generatedBy; // CRON | ON_DEMAND
  final bool degraded; // true = assemblage déterministe (sans modèle)
  final DateTime createdAt;

  factory LhAiBriefing.fromJson(Map<String, dynamic> json) => LhAiBriefing(
        date: json['date'] as String? ?? '',
        headline: json['headline'] as String? ?? '',
        message: json['message'] as String? ?? '',
        sections:
            Map<String, dynamic>.from(json['sections'] as Map? ?? {}),
        alertCount: (json['alertCount'] as num?)?.toInt() ?? 0,
        generatedBy: json['generatedBy'] as String? ?? 'ON_DEMAND',
        degraded: json['degraded'] == true,
        createdAt: json['createdAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'headline': headline,
        'message': message,
        'sections': sections,
        'alertCount': alertCount,
        'generatedBy': generatedBy,
        'degraded': degraded,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Alerte intelligente (budget, échéance, tâche, prêt) — dédupliquée
/// par le serveur, cycle UNREAD → READ / DISMISSED.
class LhAiAlert {
  const LhAiAlert({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.body,
    required this.status,
    required this.dedupKey,
    this.payload,
    required this.createdAt,
  });
  final String id;
  final String kind; // BUDGET_THRESHOLD | DUE_ITEM_UPCOMING | …
  final String severity; // INFORMATION | NORMAL | IMPORTANT
  final String title;
  final String body;
  final String status; // UNREAD | READ | DISMISSED
  final String dedupKey;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  factory LhAiAlert.fromJson(Map<String, dynamic> json) => LhAiAlert(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        severity: json['severity'] as String? ?? 'NORMAL',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        status: json['status'] as String? ?? 'UNREAD',
        dedupKey: json['dedupKey'] as String? ?? '',
        payload: json['payload'] == null
            ? null
            : Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: json['createdAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['createdAt'] as String),
      );
}

/// Consentement granulaire — périmètre sensible (journal de bien-être,
/// messagerie, notes) refusé par défaut, ouvert uniquement ici.
class LhAiConsent {
  const LhAiConsent({
    required this.scope,
    required this.module,
    required this.label,
    required this.description,
    required this.granted,
    this.grantedAt,
    this.revokedAt,
  });
  final String scope; // wellbeing.journal | messaging.read | notes.content
  final String module;
  final String label;
  final String description;
  final bool granted;
  final DateTime? grantedAt;
  final DateTime? revokedAt;

  factory LhAiConsent.fromJson(Map<String, dynamic> json) => LhAiConsent(
        scope: json['scope'] as String? ?? '',
        module: json['module'] as String? ?? '',
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
        granted: json['granted'] == true,
        grantedAt: json['grantedAt'] == null
            ? null
            : DateTime.parse(json['grantedAt'] as String),
        revokedAt: json['revokedAt'] == null
            ? null
            : DateTime.parse(json['revokedAt'] as String),
      );
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
