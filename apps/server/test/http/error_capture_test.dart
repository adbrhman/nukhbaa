import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/http/error_capture.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/request_scope.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 3, 12);
}

final class _MemoryErrorLog implements ErrorLogRepository {
  _MemoryErrorLog({this.fail = false});

  final bool fail;
  final List<ErrorOccurrence> kept = [];

  @override
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence) async {
    if (fail) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
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

RequestContext _context(String url, {HttpMethod method = HttpMethod.get}) {
  final request = _MockRequest();
  when(() => request.method).thenReturn(method);
  when(() => request.uri).thenReturn(Uri.parse(url));
  when(() => request.headers).thenReturn({'user-agent': 'NukhbaaTest/1.0'});
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  return context;
}

Future<Response> _call(
  Handler inner,
  _MemoryErrorLog log, {
  String url = 'http://localhost/seasons',
}) {
  final record = RecordError(errors: log, clock: const _FixedClock());
  final handler = captureServerErrors(
    inner,
    recorder: () async => record,
    build: 'abc1234',
  );
  return Future<Response>.value(handler(_context(url)));
}

void main() {
  test('every response carries a fresh request id', () async {
    final log = _MemoryErrorLog();

    final first = await _call((_) => Response(body: 'ok'), log);
    final second = await _call((_) => Response(body: 'ok'), log);

    final id = first.headers[requestIdHeader];
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second.headers[requestIdHeader], isNot(id));
    expect(first.statusCode, HttpStatus.ok);
    expect(log.kept, isEmpty, reason: 'a success is not an error');
  });

  test('an escaped exception is answered 500 and kept with its request '
      'id, route, player and build', () async {
    final log = _MemoryErrorLog();

    final response = await _call(
      (_) {
        RequestScope.current!.userId = _user;
        throw StateError('no season for refresh_token=8f7a6b5c4d3e2f1a0b9c');
      },
      log,
      url:
          'http://localhost/seasons/6bf8134c-3eed-46ce-a0dc-e3dc5d4c57c2'
          '?token=abc123secret&page=2',
    );

    expect(response.statusCode, HttpStatus.internalServerError);
    final body = jsonDecode(await response.body()) as Map<String, Object?>;
    expect(body['code'], 'server.unexpected');
    final kept = log.kept.single;
    expect(kept.source, 'server');
    expect(kept.errorType, 'StateError');
    expect(kept.severity, ErrorSeverity.high);
    expect(kept.requestId, response.headers[requestIdHeader]);
    expect(kept.route, 'GET /seasons/:id');
    expect(kept.userId, _user);
    expect(kept.build, 'abc1234');
    expect(kept.browser, 'NukhbaaTest/1.0');
    expect(kept.stack, isNotEmpty);
    expect(kept.message, isNot(contains('8f7a6b5c4d3e2f1a0b9c')));
    expect(kept.requestInputJson, isNot(contains('abc123secret')));
    expect(kept.requestInputJson, contains('"page":"2"'));
  });

  test('a 5xx a route answered keeps its code and cause, redacted, located '
      'at the route rather than the envelope', () async {
    final log = _MemoryErrorLog();

    final response = await _call(
      (_) => errorResponse(
        const AppError.transient(
          'db.timeout',
          'Statement timed out',
          'postgres://postgres.ref:S3cretPw@pooler:6543/postgres',
        ),
      ),
      log,
    );

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    final kept = log.kept.single;
    expect(kept.errorType, 'AppError');
    expect(kept.errorCode, 'db.timeout');
    expect(kept.message, startsWith('Statement timed out: '));
    expect(kept.message, isNot(contains('S3cretPw')));
    expect(kept.severity, ErrorSeverity.medium);
    expect(kept.locationFile, isNot(contains('error_envelope.dart')));
  });

  test('the same failure on two ids is one error', () async {
    final log = _MemoryErrorLog();
    Response fail(RequestContext _) =>
        errorResponse(const AppError.transient('db.timeout', 'timed out'));

    await _call(
      fail,
      log,
      url: 'http://localhost/seasons/6bf8134c-3eed-46ce-a0dc-e3dc5d4c57c2',
    );
    await _call(
      fail,
      log,
      url: 'http://localhost/seasons/0686dde7-bfe9-4a29-997e-a6585c334ed7',
    );

    expect(log.kept, hasLength(2));
    expect(log.kept[0].fingerprint, log.kept[1].fingerprint);
    expect(log.kept[0].problemCode, log.kept[1].problemCode);
  });

  test('a 4xx answer is a decision, not an error', () async {
    final log = _MemoryErrorLog();

    final response = await _call(
      (_) => errorResponse(
        const AppError.invariant('prediction.locked', 'Kicked off'),
      ),
      log,
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(response.headers[requestIdHeader], isNotNull);
    expect(log.kept, isEmpty);
  });

  test('a bare 5xx without an AppError is kept by its status', () async {
    final log = _MemoryErrorLog();

    await _call((_) => Response(statusCode: HttpStatus.badGateway), log);

    expect(log.kept.single.errorType, 'HttpStatus');
    expect(log.kept.single.message, 'HTTP 502');
  });

  test('a failure to record never changes the response', () async {
    final log = _MemoryErrorLog(fail: true);

    final response = await _call((_) => throw StateError('boom'), log);

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(response.headers[requestIdHeader], isNotNull);
  });

  test('without a recorder nothing is kept and nothing breaks', () async {
    final handler = captureServerErrors(
      (_) => throw StateError('boom'),
      recorder: () async => null,
      build: 'abc1234',
    );

    final response = await handler(_context('http://localhost/x'));

    expect(response.statusCode, HttpStatus.internalServerError);
  });

  group('serverBuild', () {
    test('prefers the deployed commit, shortened', () {
      expect(
        serverBuild(const {
          'NF_DEPLOYMENT_SHA': '9483200aa11bb22cc33dd44ee55ff66778899',
          'NUKHBA_BUILD_SHA': 'ffffff0',
        }),
        '9483200',
      );
    });

    test('falls back to NUKHBA_BUILD_SHA, then to server-dev', () {
      expect(serverBuild(const {'NUKHBA_BUILD_SHA': 'abc1234'}), 'abc1234');
      expect(serverBuild(const {}), 'server-dev');
      expect(
        serverBuild(const {'NF_DEPLOYMENT_SHA': 'bad sha!'}),
        'server-dev',
      );
    });
  });
}
