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
import '../../routes/auth/google/index.dart' as route;

/// An [AuthGateway] that answers ID-token sign-ins with [_response] and
/// records what it was handed.
final class _FakeGateway implements AuthGateway {
  _FakeGateway(this._response);

  final Result<IssuedSession> _response;
  final List<String> received = <String>[];

  @override
  Future<Result<IssuedSession>> signInWithIdToken({
    required String provider,
    required String idToken,
  }) async {
    received.add('$provider:$idToken');
    return _response;
  }

  @override
  Future<Result<IssuedSession>> refreshSession({
    required String refreshToken,
  }) => throw UnimplementedError();

  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> requestPasswordReset({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({
    required String recoveryToken,
    required String password,
  }) => throw UnimplementedError();
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire(
  _FakeGateway gateway, {
  HttpMethod method = HttpMethod.post,
  String body = '',
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(signInWithGoogle: SignInWithGoogle(gateway)),
  );
  final request = _MockRequest();
  when(() => request.method).thenReturn(method);
  when(request.body).thenAnswer((_) async => body);
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  return context;
}

Future<Map<String, Object?>> _decode(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded.cast<String, Object?>();
}

const _session = IssuedSession(
  accessToken: 'access-g',
  refreshToken: 'refresh-g',
  emailConfirmationRequired: false,
);

void main() {
  group('POST /auth/google', () {
    test('returns a session for a Google ID token', () async {
      final gateway = _FakeGateway(const Result.ok(_session));
      final context = _wire(
        gateway,
        body: jsonEncode({'id_token': 'google-id-token'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await _decode(response);
      expect(body['access_token'], 'access-g');
      expect(body['refresh_token'], 'refresh-g');
      expect(gateway.received, ['google:google-id-token']);
    });

    test('a refused token becomes one readable 400', () async {
      final gateway = _FakeGateway(
        const Result.err(
          AppError.validation('auth.rejected', 'Provider is not enabled'),
        ),
      );
      final context = _wire(
        gateway,
        body: jsonEncode({'id_token': 'google-id-token'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await _decode(response))['code'], 'auth.google_rejected');
    });

    test(
      'rejects a body without an ID token before any upstream call',
      () async {
        final gateway = _FakeGateway(const Result.ok(_session));
        final context = _wire(gateway, body: jsonEncode(<String, Object?>{}));

        final response = await route.onRequest(context);

        expect(response.statusCode, HttpStatus.badRequest);
        expect(gateway.received, isEmpty);
      },
    );

    test('rejects non-POST methods with 405', () async {
      final gateway = _FakeGateway(const Result.ok(_session));
      final context = _wire(gateway, method: HttpMethod.get);

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(gateway.received, isEmpty);
    });
  });
}
