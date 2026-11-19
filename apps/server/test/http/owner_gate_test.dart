import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/owner_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '11111111-2222-4333-8444-555555555555';
const _admin = '66666666-7777-4888-8999-000000000000';

final class _Verifier implements TokenVerifier {
  _Verifier(this.answer);

  Result<AuthenticatedUser> answer;

  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async => answer;
}

/// The owner seats: [_owner] alone, or a failed read.
final class _Seats implements OwnerNotices {
  bool fails = false;

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async => fails
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(user == const UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Audit implements OwnerAuditLog {
  final List<(String, String, String, int)> kept = [];

  @override
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  }) async {
    kept.add((actor.value, method, path, status));
    return const Result.ok(null);
  }
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

AuthenticatedUser _as(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.admin);

/// Script 287 (decision Q01): the gate the `/owner` subtree's
/// `_middleware.dart` installs, run as the server runs it.
void main() {
  setUpAll(() {
    registerFallbackValue(_as(_owner));
  });

  late _Verifier verifier;
  late _Seats seats;
  late _Audit audit;
  late List<AuthenticatedUser> reached;

  setUp(() {
    verifier = _Verifier(Result.ok(_as(_owner)));
    seats = _Seats();
    audit = _Audit();
    reached = [];
  });

  Future<Response> call({
    HttpMethod method = HttpMethod.post,
    String path = '/owner/hidden-accounts/abc',
    int answer = HttpStatus.ok,
    bool wired = true,
  }) async {
    final root = Future<CompositionRoot>.value(
      CompositionRoot.forTesting(
        authenticateRequest: AuthenticateRequest(verifier),
        ownerNotices: wired ? seats : null,
        ownerAuditLog: audit,
      ),
    );
    final request = _MockRequest();
    when(() => request.method).thenReturn(method);
    when(() => request.uri).thenReturn(Uri.parse('http://localhost$path'));
    when(
      () => request.headers,
    ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer token'});

    final inner = _MockRequestContext();
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
    when(() => context.provide<AuthenticatedUser>(any())).thenAnswer((inv) {
      final create =
          inv.positionalArguments.first as AuthenticatedUser Function();
      reached.add(create());
      return inner;
    });

    final Handler handler = ownerGate()(
      (_) => Response(statusCode: answer, body: 'owner page'),
    );
    return handler(context);
  }

  Future<void> expectNoRoute(Response response) async {
    final Response none = Router.routeNotFound;
    expect(response.statusCode, none.statusCode);
    expect(await response.body(), await none.body());
    expect(await response.body(), routeNotFoundBody);
    expect(reached, isEmpty);
    expect(audit.kept, isEmpty);
  }

  test('an owner seat reaches the route, and his change is kept', () async {
    final response = await call();

    expect(response.statusCode, HttpStatus.ok);
    expect(await response.body(), 'owner page');
    expect(reached.single.userId, const UserId(_owner));
    expect(audit.kept, [(_owner, 'POST', '/owner/hidden-accounts/abc', 200)]);
  });

  test('an owner reading changes nothing in the log', () async {
    final response = await call(method: HttpMethod.get, path: '/owner/crests');

    expect(response.statusCode, HttpStatus.ok);
    expect(audit.kept, isEmpty);
  });

  test('a refused change is not kept', () async {
    final response = await call(
      method: HttpMethod.put,
      path: '/owner/crests',
      answer: HttpStatus.badRequest,
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(audit.kept, isEmpty);
  });

  test('an admin who holds no seat gets a path with no route', () async {
    verifier.answer = Result.ok(_as(_admin));

    await expectNoRoute(await call());
  });

  test('a player gets a path with no route', () async {
    verifier.answer = const Result.ok(
      AuthenticatedUser(userId: UserId(_admin), role: PlatformRole.user),
    );

    await expectNoRoute(await call(method: HttpMethod.get));
  });

  test('no token, or a bad one, is not told 401', () async {
    verifier.answer = const Result.err(
      AppError.authorization('auth.invalid_token', 'bad token'),
    );

    await expectNoRoute(await call());
  });

  test('a seat that cannot be read lets nobody in', () async {
    seats.fails = true;

    await expectNoRoute(await call());
  });

  test('no seats wired lets nobody in', () async {
    await expectNoRoute(await call(wired: false));
  });
}
