import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Utilisateur du compte tel que renvoyé par le backend (contrat /auth).
class LhUser {
  const LhUser({
    required this.id,
    this.email,
    this.phone,
    required this.firstName,
    this.lastName,
    this.avatarUrl,
    this.emailVerifiedAt,
    this.phoneVerifiedAt,
    required this.twoFactorEnabled,
    required this.createdAt,
  });

  final String id;
  final String? email;
  final String? phone;
  final String firstName;
  final String? lastName;
  final String? avatarUrl;
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;
  final bool twoFactorEnabled;
  final DateTime createdAt;

  String get displayName =>
      '$firstName${lastName == null || lastName!.isEmpty ? '' : ' $lastName'}'
          .trim();

  factory LhUser.fromJson(Map<String, dynamic> json) => LhUser(
        id: json['id'] as String,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        firstName: (json['firstName'] as String?) ?? '',
        lastName: json['lastName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        emailVerifiedAt: json['emailVerifiedAt'] == null
            ? null
            : DateTime.parse(json['emailVerifiedAt'] as String),
        phoneVerifiedAt: json['phoneVerifiedAt'] == null
            ? null
            : DateTime.parse(json['phoneVerifiedAt'] as String),
        twoFactorEnabled: (json['twoFactorEnabled'] as bool?) ?? false,
        createdAt: json['createdAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'phone': phone,
        'firstName': firstName,
        'lastName': lastName,
        'avatarUrl': avatarUrl,
        'emailVerifiedAt': emailVerifiedAt?.toIso8601String(),
        'phoneVerifiedAt': phoneVerifiedAt?.toIso8601String(),
        'twoFactorEnabled': twoFactorEnabled,
        'createdAt': createdAt.toIso8601String(),
      };

  LhUser copyWith({bool? twoFactorEnabled}) => LhUser(
        id: id,
        email: email,
        phone: phone,
        firstName: firstName,
        lastName: lastName,
        avatarUrl: avatarUrl,
        emailVerifiedAt: emailVerifiedAt,
        phoneVerifiedAt: phoneVerifiedAt,
        twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
        createdAt: createdAt,
      );
}

/// Session persistée : jetons + expiration + profil.
class LhStoredSession {
  const LhStoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final LhUser? user;

  factory LhStoredSession.fromJson(Map<String, dynamic> json) =>
      LhStoredSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        user: json['user'] == null
            ? null
            : LhUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'user': user?.toJson(),
      };
}

/// Backend de persistance de la session (indépendant de l'appareil).
abstract class TokenStoreBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Stockage sécurisé natif (trousseau / Keystore / Keychain).
class SecureTokenBackend implements TokenStoreBackend {
  SecureTokenBackend([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stockage web (les Secure Storage ne sont pas fiables en navigateur).
class PrefsTokenBackend implements TokenStoreBackend {
  PrefsTokenBackend([SharedPreferences? prefs]) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _instance).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _instance).remove(key);
}

/// Stockage en mémoire — tests unitaires uniquement.
class MemoryTokenBackend implements TokenStoreBackend {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Wrapper de stockage des jetons {accessToken, refreshToken, expiresAt, user}.
///
/// - mobile (dart:io) : `flutter_secure_storage` ;
/// - web (kIsWeb) : `shared_preferences` sous la clé `lh_session`.
class TokenStore {
  TokenStore({TokenStoreBackend? backend})
      : _backend =
            backend ?? (kIsWeb ? PrefsTokenBackend() : SecureTokenBackend());

  static const String storageKey = 'lh_session';

  final TokenStoreBackend _backend;
  final _changes = StreamController<LhStoredSession?>.broadcast();
  LhStoredSession? _cached;

  /// Flux des changements de session (null = déconnecté).
  Stream<LhStoredSession?> get changes => _changes.stream;

  /// Session courante (lecture mémoire après le premier chargement).
  LhStoredSession? get current => _cached;

  /// Charge la session persistée une fois (à l'amorçage de l'app).
  Future<LhStoredSession?> load() async {
    if (_cached != null) return _cached;
    try {
      final raw = await _backend.read(storageKey);
      if (raw == null || raw.isEmpty) return null;
      _cached = LhStoredSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // JSON corrompu : on repart d'un état anonyme propre.
      _cached = null;
    }
    return _cached;
  }

  /// Enregistre la session (login, register, refresh).
  Future<void> save(LhStoredSession session) async {
    _cached = session;
    await _backend.write(storageKey, jsonEncode(session.toJson()));
    _changes.add(session);
  }

  /// Met à jour uniquement le profil conservé dans la session.
  Future<void> updateUser(LhUser user) async {
    final current = await load();
    if (current == null) return;
    await save(LhStoredSession(
      accessToken: current.accessToken,
      refreshToken: current.refreshToken,
      expiresAt: current.expiresAt,
      user: user,
    ));
  }

  /// Efface la session (déconnexion, refresh invalide).
  Future<void> clear() async {
    _cached = null;
    await _backend.delete(storageKey);
    _changes.add(null);
  }
}
