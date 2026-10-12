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
import '../../routes/auth/password-reset/verify/index.dart' as verify_route;

/// An [AuthGateway] whose code check answers [next], counting the calls.
final class _CodeGateway implements AuthGateway {
  _CodeGateway(this.next);

  Result<String> next;
  int verifications = 0;
  String? lastCode;

  @override
  Future<Result<String>> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    verifications++;
    lastCode = code;
    return next;
  }

  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> requestPasswordReset({required String email}) =>
      throw UnimplementedError();

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

_MockRequestContext _wire(_CodeGateway gateway, Map<String, Object?> body) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(verifyRecoveryCode: VerifyRecoveryCode(gateway)),
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

Future<Map<Object?, Object?>> _body(Response response) async =>
    await response.json() as Map<Object?, Object?>;

void main() {
  test('a right code is traded for the recovery token', () async {
    final gateway = _CodeGateway(const Result.ok('recovery-access-token'));

    final response = await verify_route.onRequest(
      _wire(gateway, {'email': 'right@example.com', 'code': ' 123 456 '}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect((await _body(response))['recovery_token'], 'recovery-access-token');
    expect(gateway.lastCode, '123456', reason: 'spaces are dropped');
  });

  test('a code that is not digits never reaches Supabase', () async {
    final gateway = _CodeGateway(const Result.ok('unused'));

    final response = await verify_route.onRequest(
      _wire(gateway, {'email': 'format@example.com', 'code': '12ab'}),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_code_format');
    expect(gateway.verifications, 0);
  });

  test('a wrong code is refused in the gateway\'s words', () async {
    final gateway = _CodeGateway(
      const Result.err(
        AppError.validation('auth.recovery_code_invalid', 'wrong'),
      ),
    );

    final response = await verify_route.onRequest(
      _wire(gateway, {'email': 'wrong@example.com', 'code': '000000'}),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_code_invalid');
  });

  test('a sixth code for one address within 15 minutes is refused', () async {
    final gateway = _CodeGateway(
      const Result.err(
        AppError.validation('auth.recovery_code_invalid', 'wrong'),
      ),
    );
    Future<Response> attempt() => verify_route.onRequest(
      _wire(gateway, {'email': 'guess@example.com', 'code': '111111'}),
    );

    for (var i = 0; i < 5; i++) {
      expect((await attempt()).statusCode, HttpStatus.badRequest);
    }
    final refused = await attempt();

    expect(refused.statusCode, HttpStatus.tooManyRequests);
    expect((await _body(refused))['code'], 'request.rate_limited');
    expect(gateway.verifications, 5);
  });
}
