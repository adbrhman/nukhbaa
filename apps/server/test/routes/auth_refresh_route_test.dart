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
import '../../routes/auth/refresh/index.dart' as route;

/// An [AuthGateway] that answers renewals with [_response] and records the
/// refresh tokens it was handed.
final class _FakeGateway implements AuthGateway {
  _FakeGateway(this._response);

  final Result<IssuedSession> _response;
  final List<String> received = <String>[];

  @override
  Future<Result<IssuedSession>> refreshSession({
    required String refreshToken,
  }) async {
    received.add(refreshToken);
    return _response;
  }

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
    CompositionRoot.forTesting(refreshSession: RefreshSession(gateway)),
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

const _renewed = IssuedSession(
  accessToken: 'access-2',
  refreshToken: 'refresh-2',
  emailConfirmationRequired: false,
);

void main() {
  group('POST /auth/refresh', () {
    test('returns the renewed pair for a live refresh token', () async {
      final gateway = _FakeGateway(const Result.ok(_renewed));
      final context = _wire(
        gateway,
        body: jsonEncode({'refresh_token': 'refresh-1'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await _decode(response);
      expect(body['access_token'], 'access-2');
      expect(body['refresh_token'], 'refresh-2');
      expect(gateway.received, ['refresh-1']);
    });

    test('answers a refused token with 400, never 401', () async {
      final gateway = _FakeGateway(
        const Result.err(
          AppError.validation('auth.rejected', 'Invalid Refresh Token'),
        ),
      );
      final context = _wire(
        gateway,
        body: jsonEncode({'refresh_token': 'spent'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await _decode(response))['code'], 'auth.rejected');
    });

    test('rejects a body without a refresh token before any upstream '
        'call', () async {
      final gateway = _FakeGateway(const Result.ok(_renewed));
      final context = _wire(gateway, body: jsonEncode(<String, Object?>{}));

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(gateway.received, isEmpty);
    });

    test('rejects non-POST methods with 405', () async {
      final gateway = _FakeGateway(const Result.ok(_renewed));
      final context = _wire(gateway, method: HttpMethod.get);

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(gateway.received, isEmpty);
    });
  });
}
