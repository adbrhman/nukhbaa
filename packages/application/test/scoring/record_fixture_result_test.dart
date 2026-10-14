import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository, auditRecorderOver;
import '../competition/fakes.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _admin = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

void main() {
  late FakeFixtureResultRepository results;
  late FakeFixtureScheduleRepository schedules;
  late RecordFixtureResult useCase;

  setUp(() {
    results = FakeFixtureResultRepository();
    schedules = FakeFixtureScheduleRepository();
    useCase = RecordFixtureResult(
      resultRepository: results,
      fixtureScheduleRepository: schedules,
      clock: FixedClock(DateTime.utc(2026, 7, 11, 18)),
    );
  });

  test('admin records a valid result and it is stored', () async {
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 2,
      awayGoals: 1,
    );
    expect(r, isA<Ok<FixtureResult>>());
    expect((r as Ok<FixtureResult>).value.homeGoals, 2);
    expect(r.value.outcome, MatchOutcome.homeWin);
    expect(results.count, 1);
  });

  test(
    'a non-admin user is rejected (authorization) and nothing is stored',
    () async {
      final r = await useCase.call(
        principal: userPrincipal(_user),
        fixtureId: _fixture,
        homeGoals: 0,
        awayGoals: 0,
      );
      expect(r, isA<Err<FixtureResult>>());
      expect((r as Err<FixtureResult>).error.kind, ErrorKind.authorization);
      expect(results.count, 0);
    },
  );

  test('a malformed fixture id is a validation error', () async {
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: 'not-a-uuid',
      homeGoals: 1,
      awayGoals: 0,
    );
    expect(r, isA<Err<FixtureResult>>());
    expect((r as Err<FixtureResult>).error.kind, ErrorKind.validation);
    expect(results.count, 0);
  });

  test('a negative scoreline is rejected by the domain value object', () async {
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: -1,
      awayGoals: 0,
    );
    expect(r, isA<Err<FixtureResult>>());
    expect((r as Err<FixtureResult>).error.code, 'scoring.result_negative');
    expect(results.count, 0);
  });

  test('recording twice upserts in place (idempotent correction)', () async {
    await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 1,
      awayGoals: 1,
    );
    final corrected = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 3,
      awayGoals: 0,
    );
    expect(corrected, isA<Ok<FixtureResult>>());
    expect(results.count, 1);
    final stored = await results.findByFixture(const FixtureRef(_fixture));
    expect((stored as Ok<FixtureResult?>).value!.homeGoals, 3);
  });

  test('a transient storage failure propagates unchanged', () async {
    results.failNextWith(const AppError.transient('db.down', 'unavailable'));
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 0,
      awayGoals: 0,
    );
    expect((r as Err<FixtureResult>).error.kind, ErrorKind.transient);
  });

  test('a result before the registered kickoff is refused', () async {
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_fixture),
        homeTeam: 'Home FC',
        awayTeam: 'Away FC',
        kickoffAt: DateTime.utc(2026, 7, 11, 20),
      ),
    );
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 1,
      awayGoals: 0,
    );
    expect(r, isA<Err<FixtureResult>>());
    expect((r as Err<FixtureResult>).error.code, 'scoring.fixture_not_started');
    expect(results.count, 0);
  });

  test('a result after the registered kickoff is stored', () async {
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_fixture),
        homeTeam: 'Home FC',
        awayTeam: 'Away FC',
        kickoffAt: DateTime.utc(2026, 7, 11, 16),
      ),
    );
    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
      homeGoals: 1,
      awayGoals: 0,
    );
    expect(r, isA<Ok<FixtureResult>>());
    expect(results.count, 1);
  });

  // Audit M-25: a result an admin records or corrects leaves a trail.
  group('the audit trail', () {
    late InMemoryAuditLogRepository auditLog;
    late RecordFixtureResult audited;

    setUp(() {
      auditLog = InMemoryAuditLogRepository();
      audited = RecordFixtureResult(
        resultRepository: results,
        fixtureScheduleRepository: schedules,
        clock: FixedClock(DateTime.utc(2026, 7, 11, 18)),
        auditRecorder: auditRecorderOver(auditLog),
      );
    });

    Future<Result<FixtureResult>> record(
      AuthenticatedUser who,
      int home,
      int away,
    ) => audited.call(
      principal: who,
      fixtureId: _fixture,
      homeGoals: home,
      awayGoals: away,
    );

    test('a result names the admin and the score', () async {
      await record(adminPrincipal(_admin), 2, 1);

      final entry = auditLog.rows.single;
      expect(entry.action, AuditAction.fixtureResultRecorded);
      expect(entry.actorId, const UserId(_admin));
      expect(entry.targetRef, _fixture);
      expect(entry.reason, '2-1');
    });

    test('a correction keeps the score it replaced', () async {
      await record(adminPrincipal(_admin), 1, 1);
      await record(adminPrincipal(_admin), 2, 1);

      expect(auditLog.rows.map((e) => e.reason), <String?>[
        '1-1',
        '1-1 -> 2-1',
      ]);
    });

    test('the provider sync (service, not a user) is not audited', () async {
      final r = await record(
        const AuthenticatedUser(
          userId: UserId(_admin),
          role: PlatformRole.service,
        ),
        3,
        0,
      );

      expect(r, isA<Ok<FixtureResult>>());
      expect(auditLog.rows, isEmpty);
    });

    test('a trail that cannot be written is reported', () async {
      auditLog.failNextWith(
        const AppError.transient('admin.db_down', 'audit log is down'),
      );

      final r = await record(adminPrincipal(_admin), 2, 2);

      expect((r as Err<FixtureResult>).error.code, 'admin.db_down');
    });
  });
}
