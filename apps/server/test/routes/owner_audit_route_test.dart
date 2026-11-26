import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/owner_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/owner/audit/index.dart' as route;

const _owner = '11111111-2222-4333-8444-555555555555';
const _admin = '66666666-7777-4888-8999-000000000000';
const _player = '99999999-aaaa-4bbb-8ccc-dddddddddddd';

final Map<String, AuthenticatedUser> _tokens = <String, AuthenticatedUser>{
  'owner-token': const AuthenticatedUser(
    userId: UserId(_owner),
    role: PlatformRole.admin,
  ),
  'admin-token': const AuthenticatedUser(
    userId: UserId(_admin),
    role: PlatformRole.admin,
  ),
  'player-token': const AuthenticatedUser(
    userId: UserId(_player),
    role: PlatformRole.user,
  ),
};

final class _Verifier implements TokenVerifier {
  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async {
    final AuthenticatedUser? who = _tokens[bearerToken];
    if (who == null) {
      return const Result.err(
        AppError.authorization('auth.bad_token', 'bad token'),
      );
    }
    return Result.ok(who);
  }
}

/// The owner seats: [_owner] alone.
final class _Seats implements OwnerNotices {
  const _Seats();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async =>
      Result.ok(user == const UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Reader implements OwnerAuditReader {
  final List<int> asked = <int>[];

  @override
  Future<Result<List<OwnerAuditLine>>> latest({int limit = 200}) async {
    asked.add(limit);
    return Result.ok(<OwnerAuditLine>[
      OwnerAuditLine(
        source: OwnerAuditLine.sourceAdmin,
        id: 7,
        actorName: 'Khalid',
        method: 'PUT',
        path: '/fixtures/f/result',
        at: DateTime.utc(2026, 11, 26, 18),
        target: 'Al Hilal x Al Nassr',
        result: '2-1',
      ),
      OwnerAuditLine(
        source: OwnerAuditLine.sourceOwner,
        id: 7,
        actorName: 'Khalid',
        method: 'POST',
        path: '/owner/switches/month-crowning',
        at: DateTime.utc(2026, 11, 26, 17),
      ),
    ]);
  }
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

// NK343_03
/// Script 343: `GET /owner/audit` through the owner gate the `/owner`
/// subtree installs and the real use-case, as the server runs them.
void main() {
  setUpAll(() {
    registerFallbackValue(_tokens['owner-token']!);
  });

  late _Reader reader;
  late List<AuthenticatedUser> reached;

  setUp(() {
    reader = _Reader();
    reached = <AuthenticatedUser>[];
  });

  Future<Response> call({
    String token = 'owner-token',
    HttpMethod method = HttpMethod.get,
    Map<String, String> query = const <String, String>{},
    bool wired = true,
  }) async {
    final root = Future<CompositionRoot>.value(
      CompositionRoot.forTesting(
        authenticateRequest: AuthenticateRequest(_Verifier()),
        ownerNotices: const _Seats(),
        listOwnerAudit: wired
            ? ListOwnerAudit(reader: reader, owners: const _Seats())
            : null,
      ),
    );
    final request = _MockRequest();
    when(() => request.method).thenReturn(method);
    when(() => request.uri).thenReturn(
      Uri(path: '/owner/audit', queryParameters: query.isEmpty ? null : query),
    );
    when(
      () => request.headers,
    ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer $token'});

    final inner = _MockRequestContext();
    when(() => inner.request).thenReturn(request);
    when(() => inner.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
    when(
      () => inner.read<AuthenticatedUser>(),
    ).thenReturn(_tokens[token] ?? _tokens['admin-token']!);

    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
    when(() => context.provide<AuthenticatedUser>(any())).thenAnswer((inv) {
      final create =
          inv.positionalArguments.first as AuthenticatedUser Function();
      reached.add(create());
      return inner;
    });

    final Handler handler = ownerGate()(route.onRequest);
    return handler(context);
  }

  Future<void> expectNoRoute(Response response) async {
    final Response none = Router.routeNotFound;
    expect(response.statusCode, none.statusCode);
    expect(await response.body(), await none.body());
    expect(await response.body(), routeNotFoundBody);
    expect(reached, isEmpty);
    expect(reader.asked, isEmpty);
  }

  test('an owner seat reads the lines of both sources', () async {
    final Response response = await call();

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.body()) as Map<String, Object?>;
    expect(body['schema_version'], 1);
    final entries = (body['entries']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(entries.map((e) => e['source']), ['admin', 'owner']);
    expect(entries.first['actor_name'], 'Khalid');
    expect(entries.first['target'], 'Al Hilal x Al Nassr');
    expect(entries.first['result'], '2-1');
    expect(entries.last['path'], '/owner/switches/month-crowning');
    expect(entries.last['target'], isNull);
    expect(reached.single.userId, const UserId(_owner));
  });

  test('the limit is passed on, clamped, or taken as absent', () async {
    await call(query: const {'limit': '5'});
    await call(query: const {'limit': '9999'});
    await call(query: const {'limit': 'abc'});
    await call();

    expect(reader.asked, [5, 200, 200, 200]);
  });

  test('an admin with no seat gets the answer of no route', () async {
    await expectNoRoute(await call(token: 'admin-token'));
  });

  test('a player gets the answer of no route', () async {
    await expectNoRoute(await call(token: 'player-token'));
  });

  test('a bad token gets the answer of no route', () async {
    await expectNoRoute(await call(token: 'no-such-token'));
  });

  test('any method but GET is refused with 405', () async {
    final Response response = await call(method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(reader.asked, isEmpty);
  });

  test('with no use-case wired the route answers 503', () async {
    final Response response = await call(wired: false);

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    final body = jsonDecode(await response.body()) as Map<String, Object?>;
    expect(body['code'], 'owner.audit_unavailable');
  });
}
