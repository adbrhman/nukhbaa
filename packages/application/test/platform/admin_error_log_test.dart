import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart';

/// One stored error the fake changes in place.
final class _Stored {
  String status = 'new';
  String severity = 'high';
  String? assigneeId;
  String? notes;
}

final class _Errors implements ErrorLogAdminRepository {
  final _Stored stored = _Stored();
  final List<ErrorListKind> listed = [];
  String? lastCode;
  int updates = 0;

  static const AdminRef admin = AdminRef(id: adminUuid, displayName: 'مشرف');

  ErrorGroupView get view => ErrorGroupView(
    id: 7,
    problemCode: 'K7Q2',
    source: 'server',
    errorType: 'StateError',
    message: 'Bad state',
    severity: stored.severity,
    status: stored.status,
    assigneeId: stored.assigneeId,
    assigneeName: stored.assigneeId == null ? null : admin.displayName,
    adminNotes: stored.notes,
    firstBuild: 'abc1234',
    lastBuild: 'abc1234',
    firstSeenAt: DateTime.utc(2026, 10, 3),
    lastSeenAt: DateTime.utc(2026, 10, 3, 1),
    occurrences: 12,
    usersAffected: 3,
    reopenedCount: 0,
  );

  @override
  Future<Result<ErrorListCounts>> counts() async => const Result.ok(
    ErrorListCounts(all: 1, fresh: 1, recurring: 1, critical: 0),
  );

  @override
  Future<Result<List<ErrorGroupView>>> list({
    required ErrorListKind kind,
    required int limit,
    String? source,
    String? build,
    String? problemCode,
  }) async {
    listed.add(kind);
    lastCode = problemCode;
    return Result.ok([view]);
  }

  @override
  Future<Result<ErrorGroupDetail?>> detail(int id) async => Result.ok(
    id == 7
        ? ErrorGroupDetail(group: view, samples: const [], builds: const [])
        : null,
  );

  @override
  Future<Result<List<AdminRef>>> admins() async => const Result.ok([admin]);

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
    updates++;
    if (id != 7) return const Result.ok(false);
    if (status != null) stored.status = status;
    if (severity != null) stored.severity = severity;
    if (clearAssignee) stored.assigneeId = null;
    if (assigneeId != null) stored.assigneeId = assigneeId;
    if (setNotes) stored.notes = notes;
    return const Result.ok(true);
  }
}

void main() {
  late _Errors errors;
  late InMemoryAuditLogRepository audit;
  late AdminErrorLog log;
  final admin = principal(userId: adminUuid);
  final player = principal(userId: targetUuid, role: PlatformRole.user);

  setUp(() {
    errors = _Errors();
    audit = InMemoryAuditLogRepository();
    log = AdminErrorLog(
      errors: errors,
      auditRecorder: auditRecorderOver(audit),
      clock: FakeClock(DateTime.utc(2026, 10, 3, 12)),
    );
  });

  test('an admin reads a list with every count and the admins', () async {
    final result = await log.list(
      principal: admin,
      kind: ErrorListKind.recurring,
    );

    final page = (result as Ok<AdminErrorList>).value;
    expect(page.counts.recurring, 1);
    expect(page.errors.single.problemCode, 'K7Q2');
    expect(page.admins.single.id, adminUuid);
    expect(errors.listed.single, ErrorListKind.recurring);
  });

  test('a problem code is matched whatever its case', () async {
    await log.list(
      principal: admin,
      kind: ErrorListKind.all,
      problemCode: ' k7q2 ',
    );

    expect(errors.lastCode, 'K7Q2');
  });

  test('a malformed problem code is refused', () async {
    final result = await log.list(
      principal: admin,
      kind: ErrorListKind.all,
      problemCode: 'K7Q',
    );

    expect((result as Err<AdminErrorList>).error.kind, ErrorKind.validation);
  });

  test('a player cannot read or change the log', () async {
    expect(
      (await log.list(principal: player, kind: ErrorListKind.all)).isErr,
      isTrue,
    );
    expect((await log.detail(principal: player, id: 7)).isErr, isTrue);
    final changed = await log.update(principal: player, id: 7, status: 'fixed');
    expect(changed.isErr, isTrue);
    expect(errors.updates, 0);
  });

  test(
    'a change is written and recorded with the old and new values',
    () async {
      final result = await log.update(
        principal: admin,
        id: 7,
        status: 'fixed',
        assigneeId: adminUuid,
        notes: 'fixed in abc1235',
      );

      final detail = (result as Ok<ErrorGroupDetail>).value;
      expect(detail.group.status, 'fixed');
      expect(detail.group.assigneeId, adminUuid);
      expect(detail.group.adminNotes, 'fixed in abc1235');
      final entry = audit.rows.single;
      expect(entry.action, AuditAction.errorUpdated);
      expect(entry.targetRef, contains('K7Q2'));
      expect(entry.reason, contains('status: new -> fixed'));
      expect(entry.reason, contains('notes changed'));
    },
  );

  test('a change that changes nothing writes and records nothing', () async {
    final result = await log.update(principal: admin, id: 7, status: 'new');

    expect(result.isOk, isTrue);
    expect(errors.updates, 0);
    expect(audit.rows, isEmpty);
  });

  test('an unknown status, a non-admin assignee or an unknown error is '
      'refused', () async {
    expect(
      (await log.update(principal: admin, id: 7, status: 'closed')).isErr,
      isTrue,
    );
    expect(
      (await log.update(principal: admin, id: 7, assigneeId: targetUuid)).isErr,
      isTrue,
    );
    final missing = await log.update(principal: admin, id: 99, status: 'fixed');
    expect((missing as Err<ErrorGroupDetail>).error.code, 'errors.not_found');
    expect(audit.rows, isEmpty);
  });

  test('an empty assignee removes it', () async {
    errors.stored.assigneeId = adminUuid;

    final result = await log.update(principal: admin, id: 7, assigneeId: '');

    expect((result as Ok<ErrorGroupDetail>).value.group.assigneeId, isNull);
    expect(audit.rows.single.reason, contains('assignee'));
  });
}
