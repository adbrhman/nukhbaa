import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/errors/[id]/index.dart' as error_route;
// ignore: always_use_package_imports
import '../../routes/admin/errors/index.dart' as list_route;
import 'competition_route_harness.dart';

final class _Errors implements ErrorLogAdminRepository {
  String status = 'new';
  String? lastKind;
  String? lastCode;

  ErrorGroupView get view => ErrorGroupView(
    id: 7,
    problemCode: 'K7Q2',
    source: 'server',
    errorType: 'AppError',
    errorCode: 'db.timeout',
    message: 'timed out',
    severity: 'critical',
    status: status,
    firstBuild: 'abc1234',
    lastBuild: 'abc1234',
    firstSeenAt: DateTime.utc(2026, 10, 3),
    lastSeenAt: DateTime.utc(2026, 10, 3, 1),
    occurrences: 100,
    usersAffected: 4,
    reopenedCount: 0,
  );

  @override
  Future<Result<ErrorListCounts>> counts() async => const Result.ok(
    ErrorListCounts(all: 3, fresh: 2, recurring: 1, critical: 1),
  );

  @override
  Future<Result<List<ErrorGroupView>>> list({
    required ErrorListKind kind,
    required int limit,
    String? source,
    String? build,
    String? problemCode,
  }) async {
    lastKind = kind.wire;
    lastCode = problemCode;
    return Result.ok([view]);
  }

  @override
  Future<Result<ErrorGroupDetail?>> detail(int id) async => Result.ok(
    id == 7
        ? ErrorGroupDetail(
            group: view,
            samples: [
              ErrorSampleView(
                occurredAt: DateTime.utc(2026, 10, 3, 1),
                build: 'abc1234',
                message: 'timed out',
                requestId: '0123456789abcdef',
                route: 'GET /seasons/:id',
                stack: '#0 onRequest (routes/seasons/index.dart:4:1)',
              ),
            ],
            builds: [
              ErrorBuildView(
                build: 'abc1234',
                occurrences: 100,
                firstSeenAt: DateTime.utc(2026, 10, 3),
                lastSeenAt: DateTime.utc(2026, 10, 3, 1),
              ),
            ],
          )
        : null,
  );

  @override
  Future<Result<List<AdminRef>>> admins() async =>
      const Result.ok([AdminRef(id: kAdminId, displayName: 'مشرف')]);

  @override
  Future<Result<bool>> update(
    int id, {
    required DateTime at,
    String? status,
    String? severity,
    String? assigneeId,
    bool clearAssignee = false,
    bool setNotes = false,
    String? notes,
  }) async {
    if (status != null) this.status = status;
    return Result.ok(id == 7);
  }
}

void main() {
  late _Errors errors;
  late InMemoryAuditLogRepository audit;
  late CompositionRoot root;

  setUp(() {
    errors = _Errors();
    audit = InMemoryAuditLogRepository();
    root = CompositionRoot.forTesting(
      adminErrorLog: AdminErrorLog(
        errors: errors,
        auditRecorder: AuditRecorder(
          auditLog: audit,
          idGenerator: ScriptedIdGenerator([kAuditEntryId]),
          clock: FixedClock(DateTime.utc(2026, 10, 3, 12)),
        ),
        clock: FixedClock(DateTime.utc(2026, 10, 3, 12)),
      ),
    );
  });

  test('GET /admin/errors lists with the counts of every list', () async {
    final response = await list_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'list': 'critical'},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['counts'], {'all': 3, 'new': 2, 'recurring': 1, 'critical': 1});
    final first =
        (body['errors']! as List<Object?>).first! as Map<String, Object?>;
    expect(first['problem_code'], 'K7Q2');
    expect(first['occurrences'], 100);
    expect(errors.lastKind, 'critical');
  });

  test('a problem code is passed through to the search', () async {
    await list_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'code': 'k7q2'},
      ),
    );

    expect(errors.lastCode, 'K7Q2');
  });

  test('an unknown list is 400', () async {
    final response = await list_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'list': 'everything'},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('a player is refused', () async {
    final response = await list_route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('GET /admin/errors/{id} answers the samples and builds', () async {
    final response = await error_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      '7',
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final samples = body['samples']! as List<Object?>;
    expect(
      (samples.single! as Map<String, Object?>)['request_id'],
      '0123456789abcdef',
    );
    expect((body['builds']! as List<Object?>), hasLength(1));
  });

  test('POST /admin/errors/{id} changes the status and audits it', () async {
    final response = await error_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        body: const {'status': 'fixed'},
      ),
      '7',
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect((body['error']! as Map<String, Object?>)['status'], 'fixed');
    expect(audit.entries.single.action, AuditAction.errorUpdated);
    expect(audit.entries.single.reason, contains('new -> fixed'));
  });

  test('an unknown error is 409 and a bad id 400', () async {
    final missing = await error_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      '99',
    );
    final bad = await error_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      'abc',
    );

    expect(missing.statusCode, HttpStatus.conflict);
    expect(bad.statusCode, HttpStatus.badRequest);
  });
}
