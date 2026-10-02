import 'dart:async';
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
import '../../routes/auth/register/index.dart' as route;

final class _FakeGateway implements AuthGateway {
  _FakeGateway(this._response);

  final Result<IssuedSession> _response;

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
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) async => _response;

  @override
  Future<Result<void>> requestPasswordReset({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({
    required String recoveryToken,
    required String password,
  }) => throw UnimplementedError();
}

final class _FakeTargets implements AdminPushTargetReader {
  _FakeTargets(this._tokens);

  final List<String> _tokens;

  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      Result.ok(List<String>.unmodifiable(_tokens));
}

final class _ThrowingTargets implements AdminPushTargetReader {
  final Completer<void> called = Completer<void>();

  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async {
    if (!called.isCompleted) {
      called.complete();
    }
    throw StateError('boom');
  }
}

final class _FakeSender implements PushSender {
  final List<List<String>> tokens = <List<String>>[];
  final Completer<void> called = Completer<void>();

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    this.tokens.add(List<String>.from(tokens));
    if (!called.isCompleted) {
      called.complete();
    }
    return const Result.ok(<String>[]);
  }
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire(
  _FakeGateway gateway,
  _FakeSender sender,
  AdminPushTargetReader targets, {
  HttpMethod method = HttpMethod.post,
  String body = '',
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      register: RegisterWithPassword(gateway),
      notifyNewUserRegistered: NotifyNewUserRegistered(
        targets: targets,
        sender: sender,
      ),
    ),
  );
  final request = _MockRequest();
  when(() => request.method).thenReturn(method);
  when(request.body).thenAnswer((_) async => body);
  when(
    request.bytes,
  ).thenAnswer((_) => Stream<List<int>>.value(utf8.encode(body)));
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  return context;
}

IssuedSession _session({required bool confirmationRequired}) => IssuedSession(
  accessToken: confirmationRequired ? null : 'access-r',
  refreshToken: confirmationRequired ? null : 'refresh-r',
  emailConfirmationRequired: confirmationRequired,
);

void main() {
  group('POST /auth/register', () {
    test('successful registration triggers an admin-only push', () async {
      final sender = _FakeSender();
      final context = _wire(
        _FakeGateway(Result.ok(_session(confirmationRequired: false))),
        sender,
        _FakeTargets(const <String>['admin-device']),
        body: jsonEncode({
          'email': 'new@example.com',
          'password': 'password-123',
          'display_name': 'New User',
        }),
      );

      final response = await route.onRequest(context);
      await sender.called.future;

      expect(response.statusCode, HttpStatus.ok);
      expect(sender.tokens.single, ['admin-device']);
    });

    test('email-confirmation registrations still alert the admin', () async {
      final sender = _FakeSender();
      final context = _wire(
        _FakeGateway(Result.ok(_session(confirmationRequired: true))),
        sender,
        _FakeTargets(const <String>['admin-device']),
        body: jsonEncode({
          'email': 'confirm@example.com',
          'password': 'password-123',
          'display_name': 'Confirm User',
        }),
      );

      final response = await route.onRequest(context);
      await sender.called.future;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(sender.tokens.single, ['admin-device']);
    });

    test('a failing admin push never breaks the signup', () async {
      final sender = _FakeSender();
      final targets = _ThrowingTargets();
      final context = _wire(
        _FakeGateway(Result.ok(_session(confirmationRequired: false))),
        sender,
        targets,
        body: jsonEncode({
          'email': 'boom@example.com',
          'password': 'password-123',
          'display_name': 'Boom User',
        }),
      );

      final response = await route.onRequest(context);
      await targets.called.future;
      await Future<void>.delayed(Duration.zero);

      expect(response.statusCode, HttpStatus.ok);
      expect(sender.tokens, isEmpty);
    });

    test('rejected registration never triggers the admin push', () async {
      final sender = _FakeSender();
      final context = _wire(
        _FakeGateway(
          const Result.err(AppError.validation('auth.rejected', 'rejected')),
        ),
        sender,
        _FakeTargets(const <String>['admin-device']),
        body: jsonEncode({
          'email': 'rejected@example.com',
          'password': 'password-123',
          'display_name': 'Rejected User',
        }),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(sender.tokens, isEmpty);
    });
  });
}
