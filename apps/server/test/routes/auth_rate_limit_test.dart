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
import '../../routes/auth/google/index.dart' as google_route;
// ignore: always_use_package_imports
import '../../routes/auth/login/index.dart' as login_route;
// ignore: always_use_package_imports
import '../../routes/auth/password-reset/request/index.dart' as reset_route;
// ignore: always_use_package_imports
import '../../routes/auth/password-reset/verify/index.dart' as code_route;
// ignore: always_use_package_imports
import '../../routes/auth/refresh/index.dart' as refresh_route;

/// An [AuthGateway] that refuses every password but [_rightPassword] and
/// accepts every reset request, renewal and Google sign-in, refuses every
/// reset code, and counts how many calls reached it.
final class _CountingGateway implements AuthGateway {
  int signIns = 0;
  int resets = 0;
  int renewals = 0;
  int googleSignIns = 0;
  int codes = 0;

  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signIns++;
    if (password == _rightPassword) {
      return const Result.ok(
        IssuedSession(
          accessToken: 'jwt',
          refreshToken: 'refresh',
          emailConfirmationRequired: false,
        ),
      );
    }
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
  }) async {
    googleSignIns++;
    return const Result.ok(_session);
  }

  @override
  Future<Result<IssuedSession>> refreshSession({
    required String refreshToken,
  }) async {
    renewals++;
    return const Result.ok(_session);
  }

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

  @override
  Future<Result<String>> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    codes++;
    return const Result.err(
      AppError.validation('auth.recovery_code_invalid', 'wrong'),
    );
  }
}

const String _rightPassword = 'right-password';

const IssuedSession _session = IssuedSession(
  accessToken: 'jwt',
  refreshToken: 'refresh',
  emailConfirmationRequired: false,
);

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire(
  _CountingGateway gateway,
  Map<String, Object?> body, {
  String? address,
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      login: LoginWithPassword(gateway),
      requestPasswordReset: RequestPasswordReset(gateway),
      refreshSession: RefreshSession(gateway),
      signInWithGoogle: SignInWithGoogle(gateway),
      verifyRecoveryCode: VerifyRecoveryCode(gateway),
    ),
  );
  final encoded = jsonEncode(body);
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.post);
  when(() => request.headers).thenReturn(<String, String>{
    if (address != null) 'x-forwarded-for': '10.0.0.1, $address',
  });
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

  // Audit M-16: the count is per e-mail AND network, so a stranger's
  // failures do not lock the real player out.
  group('a stranger cannot lock a player out', () {
    test('failures from one network leave the real network free', () async {
      final gateway = _CountingGateway();
      Future<Response> from(String address, String password) =>
          login_route.onRequest(
            _wire(gateway, {
              'email': 'rival@example.com',
              'password': password,
            }, address: address),
          );

      for (var i = 0; i < 10; i++) {
        await from('203.0.113.7', 'guess');
      }
      expect(
        (await from('203.0.113.7', 'guess')).statusCode,
        HttpStatus.tooManyRequests,
      );

      final own = await from('198.51.100.2', _rightPassword);
      expect(own.statusCode, HttpStatus.ok);
    });

    test('a successful sign-in clears the failures before it', () async {
      final gateway = _CountingGateway();
      Future<Response> attempt(String password) => login_route.onRequest(
        _wire(gateway, {
          'email': 'forgetful@example.com',
          'password': password,
        }, address: '198.51.100.9'),
      );

      for (var i = 0; i < 9; i++) {
        await attempt('guess');
      }
      expect((await attempt(_rightPassword)).statusCode, HttpStatus.ok);
      for (var i = 0; i < 9; i++) {
        expect((await attempt('guess')).statusCode, HttpStatus.badRequest);
      }
    });

    test('reset e-mails asked elsewhere do not block the real one', () async {
      final gateway = _CountingGateway();
      Future<Response> from(String address) => reset_route.onRequest(
        _wire(gateway, {'email': 'victim@example.com'}, address: address),
      );

      for (var i = 0; i < 3; i++) {
        await from('203.0.113.8');
      }
      expect(
        (await from('203.0.113.8')).statusCode,
        HttpStatus.tooManyRequests,
      );
      expect((await from('198.51.100.3')).statusCode, HttpStatus.ok);
    });

    test('one network trying many reset codes is bounded', () async {
      final gateway = _CountingGateway();
      Response? last;
      for (var i = 0; i < 31; i++) {
        last = await code_route.onRequest(
          _wire(gateway, {
            'email': 'code$i@example.com',
            'code': '123456',
          }, address: '203.0.113.31'),
        );
      }
      expect(last!.statusCode, HttpStatus.tooManyRequests);
      expect(gateway.codes, 30);

      final elsewhere = await code_route.onRequest(
        _wire(gateway, {
          'email': 'code0@example.com',
          'code': '123456',
        }, address: '198.51.100.31'),
      );
      expect(elsewhere.statusCode, HttpStatus.badRequest);
    });

    test('one network trying many accounts is still bounded', () async {
      final gateway = _CountingGateway();
      Response? last;
      for (var i = 0; i < 101; i++) {
        last = await login_route.onRequest(
          _wire(gateway, {
            'email': 'player$i@example.com',
            'password': 'guess',
          }, address: '203.0.113.99'),
        );
      }
      expect(last!.statusCode, HttpStatus.tooManyRequests);
      expect(gateway.signIns, 100);
    });
  });

  // Audit C-02: every renewal and Google sign-in spends this server's one
  // GoTrue quota, so one network address gets a share of it.
  group('calls that name no account are counted per address', () {
    test('the 101st renewal from one address within 10 minutes is refused '
        'before it reaches Supabase', () async {
      final gateway = _CountingGateway();
      Future<Response> renew(String address) => refresh_route.onRequest(
        _wire(gateway, {'refresh_token': 'made-up'}, address: address),
      );

      for (var i = 0; i < 100; i++) {
        expect((await renew('203.0.113.40')).statusCode, HttpStatus.ok);
      }
      final refused = await renew('203.0.113.40');

      expect(refused.statusCode, HttpStatus.tooManyRequests);
      expect(refused.headers[HttpHeaders.retryAfterHeader], isNotNull);
      expect(await _codeOf(refused), 'request.rate_limited');
      expect(gateway.renewals, 100);

      // Another network renews as before.
      expect((await renew('198.51.100.40')).statusCode, HttpStatus.ok);
      expect(gateway.renewals, 101);
    });

    test('the 31st Google sign-in from one address within 10 minutes is '
        'refused', () async {
      final gateway = _CountingGateway();
      Future<Response> google(String address) => google_route.onRequest(
        _wire(gateway, {'id_token': 'made-up'}, address: address),
      );

      for (var i = 0; i < 30; i++) {
        expect((await google('203.0.113.41')).statusCode, HttpStatus.ok);
      }
      final refused = await google('203.0.113.41');

      expect(refused.statusCode, HttpStatus.tooManyRequests);
      expect(await _codeOf(refused), 'request.rate_limited');
      expect(gateway.googleSignIns, 30);
      expect((await google('198.51.100.41')).statusCode, HttpStatus.ok);
    });

    test('a request with no address is not counted', () async {
      final gateway = _CountingGateway();
      for (var i = 0; i < 101; i++) {
        final response = await refresh_route.onRequest(
          _wire(gateway, {'refresh_token': 'made-up'}),
        );
        expect(response.statusCode, HttpStatus.ok);
      }
      expect(gateway.renewals, 101);
    });
  });
}
