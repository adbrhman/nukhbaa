import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fakes.dart' show FakeFixtureResultRepository;
import 'fakes.dart';

const _fixtureId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _adminId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _auditId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

final _kickoff = DateTime.utc(2026, 9, 13, 15, 30);

FixtureSchedule _seeded({DateTime? kickoffAt}) {
  final result = FixtureSchedule.create(
    fixture: const FixtureRef(_fixtureId),
    homeTeam: 'Manchester United',
    awayTeam: 'Manchester City',
    kickoffAt: kickoffAt ?? _kickoff,
  );
  return (result as Ok<FixtureSchedule>).value;
}

({
  CorrectFixtureSchedule useCase,
  FakeFixtureScheduleRepository schedules,
  InMemoryAuditLogRepository audit,
})
_build(DateTime now, {RescoreEarlierKickoff? rescore}) {
  final schedules = FakeFixtureScheduleRepository();
  final audit = InMemoryAuditLogRepository();
  final useCase = CorrectFixtureSchedule(
    schedules,
    auditRecorder: AuditRecorder(
      auditLog: audit,
      idGenerator: FakeIdGenerator([_auditId]),
      clock: FixedClock(now),
    ),
    clock: FixedClock(now),
    rescoreEarlierKickoff: rescore,
  );
  return (useCase: useCase, schedules: schedules, audit: audit);
}

void main() {
  group('CorrectFixtureSchedule — the kickoff freeze rule', () {
    test('moves the kickoff while the stored one is still ahead', () async {
      final setup = _build(_kickoff.subtract(const Duration(hours: 2)));
      setup.schedules.seed(_seeded());

      final moved = _kickoff.add(const Duration(hours: 3));
      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        fixtureId: _fixtureId,
        homeTeam: 'Manchester United',
        awayTeam: 'Manchester City',
        kickoffAt: moved,
      );

      expect((result as Ok<FixtureSchedule>).value.kickoffAt, moved);
    });

    test(
      'refuses to move the kickoff once the stored one has passed',
      () async {
        // The match started two hours ago; pushing it forward would re-open the
        // prediction lock on a fixture whose result is already public.
        final setup = _build(_kickoff.add(const Duration(hours: 2)));
        setup.schedules.seed(_seeded());

        final result = await setup.useCase(
          principal: adminPrincipal(_adminId),
          fixtureId: _fixtureId,
          homeTeam: 'Manchester United',
          awayTeam: 'Manchester City',
          kickoffAt: _kickoff.add(const Duration(hours: 8)),
        );

        expect(
          (result as Err<FixtureSchedule>).error.kind,
          ErrorKind.invariant,
        );
        expect(result.error.code, 'competition.kickoff_frozen');
        expect(setup.audit.rows, isEmpty);
      },
    );

    test(
      'still corrects team names after kickoff, leaving the time alone',
      () async {
        final setup = _build(_kickoff.add(const Duration(hours: 2)));
        setup.schedules.seed(_seeded());

        final result = await setup.useCase(
          principal: adminPrincipal(_adminId),
          fixtureId: _fixtureId,
          homeTeam: 'Man United',
          awayTeam: 'Man City',
          kickoffAt: _kickoff,
        );

        expect((result as Ok<FixtureSchedule>).value.homeTeam, 'Man United');
      },
    );
  });

  // Audit C-03: an earlier kickoff never re-opens the lock, so it is taken
  // even after the stored one passed, and a scored fixture is scored again.
  group('CorrectFixtureSchedule — a kickoff brought forward', () {
    late FakeFixtureResultRepository results;
    late List<String> rescored;
    late Result<void> answer;

    RescoreEarlierKickoff rescorer() => RescoreEarlierKickoff(
      resultRepository: results,
      rescore: ({required String fixtureId}) async {
        rescored.add(fixtureId);
        return answer;
      },
    );

    setUp(() {
      results = FakeFixtureResultRepository();
      rescored = <String>[];
      answer = const Result.ok(null);
    });

    Future<Result<FixtureSchedule>> bringForward(
      CorrectFixtureSchedule useCase,
    ) => useCase(
      principal: adminPrincipal(_adminId),
      fixtureId: _fixtureId,
      homeTeam: 'Manchester United',
      awayTeam: 'Manchester City',
      kickoffAt: _kickoff.subtract(const Duration(hours: 1)),
    );

    test('is accepted after the stored kickoff passed', () async {
      final setup = _build(
        _kickoff.add(const Duration(hours: 2)),
        rescore: rescorer(),
      );
      setup.schedules.seed(_seeded());

      final result = await bringForward(setup.useCase);

      expect(
        (result as Ok<FixtureSchedule>).value.kickoffAt,
        _kickoff.subtract(const Duration(hours: 1)),
      );
      expect(setup.audit.rows, hasLength(1));
      expect(rescored, isEmpty, reason: 'no result yet: nothing to rescore');
    });

    test('scores the fixture again once its result is in', () async {
      results.seed(
        const FixtureResult.fromStored(
          fixture: FixtureRef(_fixtureId),
          homeGoals: 1,
          awayGoals: 0,
        ),
      );
      final setup = _build(
        _kickoff.add(const Duration(hours: 3)),
        rescore: rescorer(),
      );
      setup.schedules.seed(_seeded());

      final result = await bringForward(setup.useCase);

      expect(result, isA<Ok<FixtureSchedule>>());
      expect(rescored, [_fixtureId]);
    });

    test('a rescore that fails says so, and the kickoff stays moved', () async {
      results.seed(
        const FixtureResult.fromStored(
          fixture: FixtureRef(_fixtureId),
          homeGoals: 1,
          awayGoals: 0,
        ),
      );
      answer = const Result.err(AppError.transient('db.timeout', 'timed out'));
      final setup = _build(
        _kickoff.add(const Duration(hours: 3)),
        rescore: rescorer(),
      );
      setup.schedules.seed(_seeded());

      final result = await bringForward(setup.useCase);

      expect(
        (result as Err<FixtureSchedule>).error.code,
        'competition.rescore_failed',
      );
      final stored =
          ((await setup.schedules.findByFixture(const FixtureRef(_fixtureId)))
                  as Ok<FixtureSchedule?>)
              .value!;
      expect(stored.kickoffAt, _kickoff.subtract(const Duration(hours: 1)));
    });
  });

  group('CorrectFixtureSchedule — the audit trace', () {
    test('records the actor, the fixture and both kickoff values', () async {
      final setup = _build(_kickoff.subtract(const Duration(hours: 2)));
      setup.schedules.seed(_seeded());

      final moved = _kickoff.add(const Duration(hours: 3));
      await setup.useCase(
        principal: adminPrincipal(_adminId),
        fixtureId: _fixtureId,
        homeTeam: 'Manchester United',
        awayTeam: 'Manchester City',
        kickoffAt: moved,
      );

      expect(setup.audit.rows, hasLength(1));
      final entry = setup.audit.rows.single;
      expect(entry.action, AuditAction.fixtureScheduleCorrected);
      expect(entry.actorId.value, _adminId);
      expect(entry.targetRef, _fixtureId);
      expect(entry.reason, contains(_kickoff.toIso8601String()));
      expect(entry.reason, contains(moved.toIso8601String()));
    });

    test('refuses a non-admin caller and writes nothing', () async {
      final setup = _build(_kickoff.subtract(const Duration(hours: 2)));
      setup.schedules.seed(_seeded());

      final result = await setup.useCase(
        principal: userPrincipal(_adminId),
        fixtureId: _fixtureId,
        homeTeam: 'X',
        awayTeam: 'Y',
        kickoffAt: _kickoff,
      );

      expect(result, isA<Err<FixtureSchedule>>());
      expect(setup.audit.rows, isEmpty);
    });
  });
}
