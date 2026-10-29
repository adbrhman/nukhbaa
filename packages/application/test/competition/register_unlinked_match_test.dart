import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _newId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _orphanId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _adminId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

final _kickoff = DateTime.utc(2026, 10, 30, 20);

final class _Finder implements SameMatchFinder {
  const _Finder(this.answer);

  final SameMatch? answer;

  @override
  Future<Result<SameMatch?>> find({
    required String homeTeam,
    required String awayTeam,
    required String? homeTeamId,
    required String? awayTeamId,
    required DateTime from,
    required DateTime to,
  }) async => Result.ok(answer);
}

Future<(Result<FixtureSchedule>, FakeFixtureScheduleRepository)> _run({
  required bool linked,
  bool seeded = true,
}) async {
  final schedules = FakeFixtureScheduleRepository();
  if (seeded) {
    final orphan = FixtureSchedule.create(
      fixture: const FixtureRef(_orphanId),
      homeTeam: 'Villarreal',
      awayTeam: 'Espanyol',
      kickoffAt: _kickoff,
    );
    await schedules.upsert((orphan as Ok<FixtureSchedule>).value);
  }
  final useCase = RegisterFixtureSchedule(
    repository: schedules,
    idGenerator: FakeIdGenerator([_newId]),
    sameMatchFinder: _Finder(
      SameMatch(
        fixtureId: _orphanId,
        homeTeam: 'Villarreal',
        awayTeam: 'Espanyol',
        kickoffAt: _kickoff,
        linked: linked,
      ),
    ),
  );
  final result = await useCase(
    principal: adminPrincipal(_adminId),
    homeTeam: 'Villarreal',
    awayTeam: 'Espanyol',
    kickoffAt: _kickoff,
  );
  return (result, schedules);
}

void main() {
  group('RegisterFixtureSchedule -- a match linked to no season', () {
    test('is handed back, not refused, and no copy is written', () async {
      final (result, schedules) = await _run(linked: false);

      final schedule = (result as Ok<FixtureSchedule>).value;
      expect(schedule.fixture.value, _orphanId);
      final copy = await schedules.findByFixture(const FixtureRef(_newId));
      expect((copy as Ok<FixtureSchedule?>).value, isNull);
    });

    test('one already linked is still refused as a copy', () async {
      final (result, _) = await _run(linked: true);

      expect(
        (result as Err<FixtureSchedule>).error.code,
        RegisterFixtureSchedule.duplicateCode,
      );
    });

    test('whose schedule row cannot be read is still refused', () async {
      final (result, _) = await _run(linked: false, seeded: false);

      expect(
        (result as Err<FixtureSchedule>).error.code,
        RegisterFixtureSchedule.duplicateCode,
      );
    });
  });
}
