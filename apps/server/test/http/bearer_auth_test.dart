import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bearer_auth.dart';
import 'package:server/http/rate_limit.dart';
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

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User?>> findUser(UserId id) async =>
      throw StateError('findUser not wired in this test fake');
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
    HttpMethod method = HttpMethod.get,
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
    when(() => request.method).thenReturn(method);

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
  });

  group('the write limit', () {
    const admin = AuthenticatedUser(
      userId: UserId(_uuid),
      role: PlatformRole.admin,
    );

    Future<List<Response>> send(
      int times, {
      required RateLimiter limiter,
      required HttpMethod method,
      AuthenticatedUser? principal,
      List<bool>? ran,
    }) async {
      final wired = wire(
        verifierResult: Result.ok(principal ?? _principal()),
        authorizationHeader: 'Bearer good-token',
        method: method,
      );
      final downstream = okHandler();
      final guarded = bearerAuth(writeLimiter: limiter)(downstream.handler);
      final responses = <Response>[
        for (var i = 0; i < times; i++) await guarded(wired.context),
      ];
      ran?.addAll(downstream.ran);
      return responses;
    }

    test('a player\'s writes over the limit are refused with 429', () async {
      final ran = <bool>[];
      final responses = await send(
        3,
        limiter: RateLimiter(limit: 2, window: const Duration(minutes: 1)),
        method: HttpMethod.post,
        ran: ran,
      );

      expect(
        [for (final r in responses) r.statusCode],
        [HttpStatus.ok, HttpStatus.ok, HttpStatus.tooManyRequests],
      );
      expect(responses.last.headers[HttpHeaders.retryAfterHeader], isNotNull);
      final body = await responses.last.json() as Map<Object?, Object?>;
      expect(body['code'], 'request.rate_limited');
      expect(ran, hasLength(2));
    });

    test('reads are never counted', () async {
      final responses = await send(
        3,
        limiter: RateLimiter(limit: 1, window: const Duration(minutes: 1)),
        method: HttpMethod.get,
      );

      expect(responses.every((r) => r.statusCode == HttpStatus.ok), isTrue);
    });

    test('an admin\'s writes are not counted', () async {
      final responses = await send(
        3,
        limiter: RateLimiter(limit: 1, window: const Duration(minutes: 1)),
        method: HttpMethod.post,
        principal: admin,
      );

      expect(responses.every((r) => r.statusCode == HttpStatus.ok), isTrue);
    });
  });

  group('RateLimiter', () {
    test('a window resets once it has passed', () {
      var now = DateTime.utc(2026, 10, 2, 12);
      final limiter = RateLimiter(
        limit: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

      expect(limiter.hit('k'), isNull);
      expect(limiter.hit('k'), const Duration(minutes: 1));
      expect(limiter.hit('other'), isNull);
      now = now.add(const Duration(seconds: 61));
      expect(limiter.hit('k'), isNull);
    });
  });
}
