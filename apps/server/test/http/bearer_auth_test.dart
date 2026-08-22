import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bearer_auth.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';

final class _FakeTokenVerifier implements TokenVerifier {
  _FakeTokenVerifier(this._response);
  final Result<AuthenticatedUser> _response;

  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async =>
      _response;
}

final class _FakeUserDirectory implements UserDirectory {
  _FakeUserDirectory(this._response);
  final Result<User> _response;

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      _response;

  @override
  Future<Result<User>> updateDisplayName(UserId userId, String displayName) =>
      throw UnimplementedError();
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

AuthenticatedUser _principal() =>
    const AuthenticatedUser(userId: UserId(_uuid), role: PlatformRole.user);

User _user({
  PlatformRole role = PlatformRole.user,
  UserStatus status = UserStatus.active,
}) => User(
  id: const UserId(_uuid),
  email: 'a@example.com',
  displayName: 'Human',
  role: role,
  status: status,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_principal());
    registerFallbackValue(_user());
  });

  ({_MockRequestContext context, List<AuthenticatedUser> provided}) wire({
    required Result<AuthenticatedUser> verifierResult,
    Result<User>? directoryResult,
    String? authorizationHeader,
  }) {
    final root = Future<CompositionRoot>.value(
      CompositionRoot.forTesting(
        authenticateRequest: AuthenticateRequest(
          _FakeTokenVerifier(verifierResult),
        ),
        getCurrentUser: GetCurrentUser(
          _FakeUserDirectory(directoryResult ?? Result.ok(_user())),
        ),
      ),
    );

    final request = _MockRequest();
    when(
      () => request.headers,
    ).thenReturn({HttpHeaders.authorizationHeader: ?authorizationHeader});

    final provided = <AuthenticatedUser>[];
    final finalContext = _MockRequestContext();
    final afterPrincipal = _MockRequestContext();
    when(() => afterPrincipal.provide<User>(any())).thenReturn(finalContext);

    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
    when(() => context.provide<AuthenticatedUser>(any())).thenAnswer((inv) {
      final create =
          inv.positionalArguments.first as AuthenticatedUser Function();
      provided.add(create());
      return afterPrincipal;
    });

    return (context: context, provided: provided);
  }

  ({Handler handler, List<bool> ran}) okHandler() {
    final ran = <bool>[];
    Response handler(RequestContext _) {
      ran.add(true);
      return Response(body: 'ok');
    }

    return (handler: handler, ran: ran);
  }

  group('bearerAuth middleware', () {
    test('passes a valid token through and provides the principal', () async {
      final wired = wire(
        verifierResult: Result.ok(_principal()),
        authorizationHeader: 'Bearer good-token',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.ok);
      expect(downstream.ran, [true]);
      expect(wired.provided.single.userId.value, _uuid);
    });

    test('promotes the STORED admin role over the token claim', () async {
      final wired = wire(
        verifierResult: Result.ok(_principal()),
        directoryResult: Result.ok(_user(role: PlatformRole.admin)),
        authorizationHeader: 'Bearer good-token',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.ok);
      expect(wired.provided.single.role, PlatformRole.admin);
      expect(wired.provided.single.hasRole(PlatformRole.admin), isTrue);
    });

    test('rejects a suspended user with 401 auth.user_suspended', () async {
      final wired = wire(
        verifierResult: Result.ok(_principal()),
        directoryResult: Result.ok(_user(status: UserStatus.suspended)),
        authorizationHeader: 'Bearer good-token',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.unauthorized);
      final body = (await response.json() as Map).cast<String, Object?>();
      expect(body['code'], 'auth.user_suspended');
      expect(downstream.ran, isEmpty);
    });

    test('rejects a missing Authorization header with 401', () async {
      final wired = wire(verifierResult: Result.ok(_principal()));
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(downstream.ran, isEmpty);
    });

    test('rejects an invalid token with 401', () async {
      final wired = wire(
        verifierResult: const Result.err(
          AppError.authorization('auth.token_invalid', 'bad'),
        ),
        authorizationHeader: 'Bearer bad-token',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(downstream.ran, isEmpty);
    });

    test('maps a transient verification failure to 503, not 401', () async {
      final wired = wire(
        verifierResult: const Result.err(
          AppError.transient('auth.jwks_fetch_failed', 'unreachable'),
        ),
        authorizationHeader: 'Bearer any',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(downstream.ran, isEmpty);
    });

    test('maps a transient directory failure to 503', () async {
      final wired = wire(
        verifierResult: Result.ok(_principal()),
        directoryResult: const Result.err(
          AppError.transient('identity.upsert_no_row', 'no row'),
        ),
        authorizationHeader: 'Bearer good-token',
      );
      final downstream = okHandler();

      final response = await bearerAuth()(downstream.handler)(wired.context);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(downstream.ran, isEmpty);
    });
  });
}
