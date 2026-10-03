import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 3, 12);
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

CompositionRoot _root(_MemoryErrorLog log) => CompositionRoot.forTesting(
  recordError: RecordError(errors: log, clock: const _FixedClock()),
);

void main() {
  test('a job that answered an AppError is kept by job and code', () async {
    final log = _MemoryErrorLog();
    final root = _root(log);

    for (var tick = 0; tick < 3; tick++) {
      await reportJobFailure(
        root,
        job: 'rescore',
        error: const AppError.transient(
          'db.timeout',
          'timed out',
          'password=hunter2',
        ),
        critical: true,
      );
    }

    expect(log.kept, hasLength(3));
    final kept = log.kept.first;
    expect(kept.source, 'server');
    expect(kept.route, 'job rescore');
    expect(kept.errorType, 'AppError');
    expect(kept.errorCode, 'db.timeout');
    expect(kept.severity, ErrorSeverity.critical);
    expect(kept.message, isNot(contains('hunter2')));
    expect(
      log.kept.map((o) => o.fingerprint).toSet(),
      hasLength(1),
      reason: 'the same failure on every tick is one error',
    );
  });

  test('a job that threw is kept with its type and stack', () async {
    final log = _MemoryErrorLog();

    try {
      throw StateError('no open season');
    } on StateError catch (error, stackTrace) {
      await reportJobFailure(
        _root(log),
        job: 'monthly-season',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final kept = log.kept.single;
    expect(kept.errorType, 'StateError');
    expect(kept.errorCode, isNull);
    expect(kept.severity, ErrorSeverity.high);
    expect(kept.stack, isNotEmpty);
  });

  test('without a recorder a failure is only printed', () async {
    await reportJobFailure(
      CompositionRoot.forTesting(),
      job: 'rescore',
      error: const AppError.transient('db.timeout', 'timed out'),
    );
  });
}
