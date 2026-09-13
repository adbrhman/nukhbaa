import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../prediction/fake_fixture_schedule_repository.dart';
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
_build(DateTime now) {
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
