import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/errors/report/index.dart' as route;

const _user = '11111111-2222-3333-4444-555555555555';

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 3, 12);
}

final class _FakeTokenVerifier implements TokenVerifier {
  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async =>
      bearerToken == 'good'
      ? const Result.ok(
          AuthenticatedUser(userId: UserId(_user), role: PlatformRole.user),
        )
      : const Result.err(
          AppError.authorization('auth.token_expired', 'Token expired'),
        );
}

final class _MemoryErrorLog implements ErrorLogRepository {
  final List<ErrorOccurrence> kept = [];

  @override
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence) async {
    kept.add(occurrence);
    return Result.ok(
      RecordedError(
        groupId: 1,
        occurrences: kept.length,
        status: 'new',
        severity: occurrence.severity.name,
        usersAffected: 0,
        isNew: kept.length == 1,
        reopened: false,
      ),
    );
  }
}

Future<Response> _post(
  _MemoryErrorLog log,
  Object body, {
  String? authorization,
  String address = '10.0.0.1',
  HttpMethod method = HttpMethod.post,
}) {
  final request = _MockRequest();
  final encoded = jsonEncode(body);
  when(() => request.method).thenReturn(method);
  when(request.body).thenAnswer((_) async => encoded);
  when(
    request.bytes,
  ).thenAnswer((_) => Stream<List<int>>.value(utf8.encode(encoded)));
  when(() => request.uri).thenReturn(Uri(path: '/errors/report'));
  when(() => request.headers).thenReturn({
    'x-forwarded-for': address,
    HttpHeaders.authorizationHeader: ?authorization,
  });
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      authenticateRequest: AuthenticateRequest(_FakeTokenVerifier()),
      recordError: RecordError(errors: log, clock: const _FixedClock()),
    ),
  );
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  return route.onRequest(context);
}

Map<String, Object?> _report({
  String installId = 'install-a',
  String message = 'Bad state: no element',
}) => {
  'schema_version': 1,
  'source': 'android',
  'error_type': 'StateError',
  'message': message,
  'build': 'abc1234',
  'stack':
      '#0      FixtureCard.build '
      '(package:mobile/features/fixtures/card.dart:88:7)',
  'route': 'building FixtureCard',
  'device': 'samsung SM-A105F',
  'os': 'Android 11',
  'install_id': installId,
  'fatal': true,
};

void main() {
  test('a report before sign-in is kept and answered with the code the '
      'app computed', () async {
    final log = _MemoryErrorLog();

    final response = await _post(log, _report(installId: 'install-anon'));

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.body()) as Map<String, Object?>;
    final expected = ErrorFingerprint.of(
      source: 'android',
      errorType: 'StateError',
      stack: _report()['stack']! as String,
    ).problemCode;
    expect(body['problem_code'], expected);
    final kept = log.kept.single;
    expect(kept.problemCode, expected);
    expect(kept.source, 'android');
    expect(kept.userId, isNull);
    expect(kept.severity, ErrorSeverity.high);
    expect(kept.route, 'building FixtureCard');
    expect(kept.device, 'samsung SM-A105F');
  });

  test('a valid token names the player; an expired one does not stop the '
      'report', () async {
    final log = _MemoryErrorLog();

    await _post(
      log,
      _report(installId: 'install-signed'),
      authorization: 'Bearer good',
    );
    await _post(
      log,
      _report(installId: 'install-expired'),
      authorization: 'Bearer stale',
    );

    expect(log.kept[0].userId, _user);
    expect(log.kept[1].userId, isNull);
  });

  test('secrets in the report are removed before it is kept', () async {
    final log = _MemoryErrorLog();

    await _post(
      log,
      _report(
        installId: 'install-secret',
        message: 'login failed for ali@example.com password=hunter2',
      ),
    );

    final kept = log.kept.single;
    expect(kept.message, isNot(contains('hunter2')));
    expect(kept.message, isNot(contains('ali@example.com')));
  });

  test('an unknown field is refused and nothing is kept', () async {
    final log = _MemoryErrorLog();

    final response = await _post(log, {
      ..._report(installId: 'install-unknown'),
      'password': 'x',
    });

    expect(response.statusCode, HttpStatus.badRequest);
    expect(log.kept, isEmpty);
  });

  test('a client cannot report as the server', () async {
    final log = _MemoryErrorLog();

    final response = await _post(log, {
      ..._report(installId: 'install-server'),
      'source': 'server',
    });

    expect(response.statusCode, HttpStatus.badRequest);
    expect(log.kept, isEmpty);
  });

  test('a field of the wrong type is refused', () async {
    final log = _MemoryErrorLog();

    final response = await _post(log, {
      ..._report(installId: 'install-type'),
      'fatal': 'yes',
    });

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('one device is limited, another is not', () async {
    final log = _MemoryErrorLog();

    for (var i = 0; i < 30; i++) {
      final ok = await _post(log, _report(installId: 'install-loop'));
      expect(ok.statusCode, HttpStatus.ok);
    }
    final limited = await _post(log, _report(installId: 'install-loop'));
    final other = await _post(log, _report(installId: 'install-other'));

    expect(limited.statusCode, HttpStatus.tooManyRequests);
    expect(other.statusCode, HttpStatus.ok);
    expect(log.kept, hasLength(31));
  });

  test('only POST', () async {
    final response = await _post(
      _MemoryErrorLog(),
      _report(),
      method: HttpMethod.get,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
