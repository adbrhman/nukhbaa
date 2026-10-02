import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/auth/login/index.dart' as login_route;
// ignore: always_use_package_imports
import '../../routes/auth/password-reset/request/index.dart' as reset_route;

/// An [AuthGateway] that refuses every password and accepts every reset
/// request, counting how many calls reached it.
final class _CountingGateway implements AuthGateway {
  int signIns = 0;
  int resets = 0;

  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signIns++;
    return const Result.err(
      AppError.validation('auth.invalid_credentials', 'Wrong password'),
    );
  }

  @override
  Future<Result<void>> requestPasswordReset({required String email}) async {
    resets++;
    return const Result.ok(null);
  }

  @override
  Future<Result<IssuedSession>> signInWithIdToken({
    required String provider,
    required String idToken,
  }) => throw UnimplementedError();

  @override
  Future<Result<IssuedSession>> refreshSession({
    required String refreshToken,
  }) => throw UnimplementedError();

  @override
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({
    required String recoveryToken,
    required String password,
  }) => throw UnimplementedError();
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire(_CountingGateway gateway, Map<String, Object?> body) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      login: LoginWithPassword(gateway),
      requestPasswordReset: RequestPasswordReset(gateway),
    ),
  );
  final encoded = jsonEncode(body);
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.post);
  when(request.body).thenAnswer((_) async => encoded);
  when(
    request.bytes,
  ).thenAnswer((_) => Stream<List<int>>.value(utf8.encode(encoded)));
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  return context;
}

Future<String?> _codeOf(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded['code'] as String?;
}

void main() {
  test('the 11th sign-in for one address within 10 minutes is refused '
      'before it reaches Supabase', () async {
    final gateway = _CountingGateway();
    Future<Response> attempt(String email) => login_route.onRequest(
      _wire(gateway, {'email': email, 'password': 'guess'}),
    );

    for (var i = 0; i < 10; i++) {
      final response = await attempt('Target@Example.com');
      expect(response.statusCode, HttpStatus.badRequest);
    }
    // The address is counted however it is spelt.
    final refused = await attempt(' target@example.com ');

    expect(refused.statusCode, HttpStatus.tooManyRequests);
    expect(refused.headers[HttpHeaders.retryAfterHeader], isNotNull);
    expect(await _codeOf(refused), 'request.rate_limited');
    expect(gateway.signIns, 10);

    // Another player is not affected.
    final other = await attempt('someone.else@example.com');
    expect(other.statusCode, HttpStatus.badRequest);
    expect(gateway.signIns, 11);
  });

  test(
    'a fourth reset e-mail to one address within 15 minutes is refused',
    () async {
      final gateway = _CountingGateway();
      Future<Response> attempt() =>
          reset_route.onRequest(_wire(gateway, {'email': 'inbox@example.com'}));

      for (var i = 0; i < 3; i++) {
        expect((await attempt()).statusCode, HttpStatus.ok);
      }
      final refused = await attempt();

      expect(refused.statusCode, HttpStatus.tooManyRequests);
      expect(await _codeOf(refused), 'request.rate_limited');
      expect(gateway.resets, 3);
    },
  );
}
