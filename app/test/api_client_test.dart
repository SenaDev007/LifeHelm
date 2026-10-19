import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lifehelm/core/db/database.dart';
import 'package:lifehelm/core/net/api_client.dart';
import 'package:lifehelm/core/net/token_store.dart';

/// Client HTTP factice : aucun réseau réel, réponses scriptées par test.
class _MockClient extends http.BaseClient {
  _MockClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    final req = request as http.Request;
    final response = await handler(req);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(response.body)),
      response.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status);

const _user = {
  'id': 'u1',
  'email': 'awa@exemple.tg',
  'phone': null,
  'firstName': 'Awa',
  'lastName': 'Diallo',
  'avatarUrl': null,
  'emailVerifiedAt': '2026-01-02T10:00:00.000',
  'phoneVerifiedAt': null,
  'twoFactorEnabled': false,
  'createdAt': '2026-01-01T09:00:00.000',
};

void main() {
  late AppDatabase db;
  late TokenStore store;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    await db.setSetting('apiBaseUrl', 'http://serveur.test/api/v1');
    store = TokenStore(backend: MemoryTokenBackend());
  });

  tearDown(() async => db.close());

  test('login 200 : session persistée et profil analysé', () async {
    final client = ApiClient(
        database: db,
        tokenStore: store,
        httpClient: _MockClient((req) async {
          expect(req.url.toString(), 'http://serveur.test/api/v1/auth/login');
          return _json(200, {
            'user': _user,
            'accessToken': 'a1',
            'refreshToken': 'r1',
            'expiresIn': 3600,
          });
        }));

    final result = await client.login(
        identifier: 'awa@exemple.tg', password: 'secret');

    expect(result.user.firstName, 'Awa');
    expect(result.user.emailVerifiedAt, isNotNull);
    expect(result.accessToken, 'a1');

    // Comme le fait l'écran de connexion : persistance de la session.
    await store.save(result.toSession());
    final session = await store.load();
    expect(session, isNotNull);
    expect(session!.refreshToken, 'r1');
    expect(session.user?.id, 'u1');
    expect(
        session.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 55))),
        isTrue);
  });

  test('login 401 INVALID_CREDENTIALS : exception typée + message français',
      () async {
    final client = ApiClient(
        database: db,
        tokenStore: store,
        httpClient: _MockClient((req) async =>
            _json(401, {'code': 'INVALID_CREDENTIALS', 'message': ''})));

    await expectLater(
      client.login(identifier: 'x', password: 'y'),
      throwsA(isA<LhApiException>()
          .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')
          .having((e) => e.statusCode, 'status', 401)),
    );
    expect(apiErrorText(LhApiException(401, 'INVALID_CREDENTIALS', '')),
        'Identifiants incorrects.');
  });

  test('login 428 TOTP_REQUIRED : code TOTP requis', () async {
    final client = ApiClient(
        database: db,
        tokenStore: store,
        httpClient: _MockClient(
            (req) async => _json(428, {'code': 'TOTP_REQUIRED'})));

    await expectLater(
      client.login(identifier: 'x', password: 'y'),
      throwsA(isA<LhApiException>()
          .having((e) => e.statusCode, 'status', 428)
          .having((e) => e.code, 'code', 'TOTP_REQUIRED')),
    );
  });

  test('register 409 EMAIL_TAKEN : code métier exposé', () async {
    final client = ApiClient(
        database: db,
        tokenStore: store,
        httpClient: _MockClient(
            (req) async => _json(409, {'code': 'EMAIL_TAKEN'})));

    await expectLater(
      client.register(
          email: 'awa@exemple.tg',
          password: 'secret123',
          firstName: 'Awa'),
      throwsA(isA<LhApiException>()
          .having((e) => e.statusCode, 'status', 409)
          .having((e) => e.code, 'code', 'EMAIL_TAKEN')),
    );
  });

  test('401 authentifié → refresh → UNE retry : la requête aboutit', () async {
    await store.save(LhStoredSession(
      accessToken: 'expiré',
      refreshToken: 'r1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      user: LhUser.fromJson(_user),
    ));

    final mock = _MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/auth/refresh')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['refreshToken'], 'r1');
        return _json(200, {
          'accessToken': 'a2',
          'refreshToken': 'r2',
          'expiresIn': 3600,
        });
      }
      final auth = req.headers['Authorization'];
      if (auth == 'Bearer a2') {
        return _json(200, {'user': _user});
      }
      return _json(401, {'code': 'UNAUTHORIZED', 'message': ''});
    });
    final client =
        ApiClient(database: db, tokenStore: store, httpClient: mock);

    final user = await client.me();
    expect(user.id, 'u1');
    expect(mock.requestCount, 3); // 401 + refresh + retry

    // La session a été mise à jour avec les nouveaux jetons.
    final session = await store.load();
    expect(session!.accessToken, 'a2');
    expect(session.refreshToken, 'r2');
  });

  test('refresh refusé → session effacée + événement sessionExpired', () async {
    await store.save(LhStoredSession(
      accessToken: 'expiré',
      refreshToken: 'révoqué',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      user: LhUser.fromJson(_user),
    ));

    var expiredEvent = false;
    final client = ApiClient(
        database: db,
        tokenStore: store,
        httpClient: _MockClient((req) async =>
            req.url.path.endsWith('/auth/refresh')
                ? _json(401, {'code': 'INVALID_TOKEN', 'message': ''})
                : _json(401, {'code': 'UNAUTHORIZED', 'message': ''})));
    client.onSessionExpired.listen((_) => expiredEvent = true);

    await expectLater(
      client.me(),
      throwsA(isA<LhApiException>()
          .having((e) => e.statusCode, 'status', 401)),
    );
    // Le temps que l'événement broadcast soit livré.
    await Future<void>.delayed(Duration.zero);
    expect(expiredEvent, isTrue);
    expect(await store.load(), isNull, reason: 'La session doit être effacée.');
  });

  test('baseUrl relative sur mobile → exception réseau explicite', () async {
    await db.setSetting('apiBaseUrl', '/api/v1');
    final client = ApiClient(
        database: db,
        tokenStore: store,
        // ignore: unnecessary_lambdas
        httpClient: _MockClient((req) async => _json(200, {})));

    await expectLater(
      client.get('/auth/me'),
      throwsA(isA<LhNetworkException>().having(
          (e) => e.message, 'message', contains('URL du serveur'))),
    );
  });
}
