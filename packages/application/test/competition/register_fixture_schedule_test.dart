import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _newId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _syncedId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _adminId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _lyonId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _palaceId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

// Thursday 2026-10-15 19:45 in Riyadh.
final _kickoff = DateTime.utc(2026, 10, 15, 16, 45);

/// A scripted [SameMatchFinder] that records what it was asked.
final class _FakeSameMatchFinder implements SameMatchFinder {
  _FakeSameMatchFinder(this._answer);

  final Result<SameMatch?> _answer;
  int calls = 0;
  String? homeTeam;
  String? awayTeam;
  String? homeTeamId;
  String? awayTeamId;
  DateTime? from;
  DateTime? to;

  @override
  Future<Result<SameMatch?>> find({
    required String homeTeam,
    required String awayTeam,
    required String? homeTeamId,
    required String? awayTeamId,
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    this.homeTeam = homeTeam;
    this.awayTeam = awayTeam;
    this.homeTeamId = homeTeamId;
    this.awayTeamId = awayTeamId;
    this.from = from;
    this.to = to;
    return _answer;
  }
}

({
  RegisterFixtureSchedule useCase,
  FakeFixtureScheduleRepository schedules,
  _FakeSameMatchFinder finder,
})
_build(Result<SameMatch?> answer) {
  final schedules = FakeFixtureScheduleRepository();
  final finder = _FakeSameMatchFinder(answer);
  final useCase = RegisterFixtureSchedule(
    repository: schedules,
    idGenerator: FakeIdGenerator([_newId]),
    sameMatchFinder: finder,
  );
  return (useCase: useCase, schedules: schedules, finder: finder);
}

Future<FixtureSchedule?> _stored(
  FakeFixtureScheduleRepository schedules,
) async {
  final found = await schedules.findByFixture(const FixtureRef(_newId));
  return (found as Ok<FixtureSchedule?>).value;
}

void main() {
  group('RegisterFixtureSchedule -- one match is added once', () {
    test(
      'a match the sync already added is refused, and nothing is stored',
      () async {
        final setup = _build(
          Result.ok(
            SameMatch(
              fixtureId: _syncedId,
              homeTeam: 'ليون',
              awayTeam: 'كريستال بالاس',
              kickoffAt: _kickoff,
            ),
          ),
        );

        final result = await setup.useCase(
          principal: adminPrincipal(_adminId),
          homeTeam: 'ليون',
          awayTeam: 'كريستال بالاس',
          kickoffAt: _kickoff,
          homeTeamId: _lyonId,
          awayTeamId: _palaceId,
        );

        final error = (result as Err<FixtureSchedule>).error;
        expect(error.kind, ErrorKind.invariant);
        expect(error.code, RegisterFixtureSchedule.duplicateCode);
        expect(error.message, contains('ليون - كريستال بالاس'));
        // The stored kickoff in Riyadh time, as the admin entered it.
        expect(error.message, contains('15/10'));
        expect(error.message, contains('19:45'));
        expect(await _stored(setup.schedules), isNull);
      },
    );

    test('the finder is asked about both sides within 12 hours', () async {
      final setup = _build(const Result.ok(null));

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: '  ليون  ',
        awayTeam: 'كريستال بالاس',
        kickoffAt: _kickoff,
        homeTeamId: _lyonId,
        awayTeamId: _palaceId,
      );

      expect(result, isA<Ok<FixtureSchedule>>());
      expect(setup.finder.calls, 1);
      expect(setup.finder.homeTeam, 'ليون');
      expect(setup.finder.awayTeam, 'كريستال بالاس');
      expect(setup.finder.homeTeamId, _lyonId);
      expect(setup.finder.awayTeamId, _palaceId);
      expect(setup.finder.from, _kickoff.subtract(const Duration(hours: 12)));
      expect(setup.finder.to, _kickoff.add(const Duration(hours: 12)));
      expect((await _stored(setup.schedules))?.homeTeam, 'ليون');
    });

    test(
      'a match typed by hand, with no team found, is still checked',
      () async {
        final setup = _build(const Result.ok(null));

        await setup.useCase(
          principal: adminPrincipal(_adminId),
          homeTeam: 'ليون',
          awayTeam: 'كريستال بالاس',
          kickoffAt: _kickoff,
        );

        expect(setup.finder.calls, 1);
        expect(setup.finder.homeTeamId, isNull);
        expect(setup.finder.awayTeamId, isNull);
      },
    );

    test('a test fixture is never checked', () async {
      final setup = _build(
        Result.ok(
          SameMatch(
            fixtureId: _syncedId,
            homeTeam: 'ليون',
            awayTeam: 'كريستال بالاس',
            kickoffAt: _kickoff,
          ),
        ),
      );

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'ليون',
        awayTeam: 'كريستال بالاس',
        kickoffAt: _kickoff,
        isTest: true,
      );

      expect(result, isA<Ok<FixtureSchedule>>());
      expect(setup.finder.calls, 0);
      expect((await _stored(setup.schedules))?.isTest, isTrue);
    });

    test('a failed check stores nothing and says why', () async {
      const failure = AppError.transient('db.query_timeout', 'timed out');
      final setup = _build(const Result.err(failure));

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'ليون',
        awayTeam: 'كريستال بالاس',
        kickoffAt: _kickoff,
      );

      expect((result as Err<FixtureSchedule>).error, failure);
      expect(await _stored(setup.schedules), isNull);
    });

    test('a player is refused before anything is looked up', () async {
      final setup = _build(const Result.ok(null));

      final result = await setup.useCase(
        principal: userPrincipal(_adminId),
        homeTeam: 'ليون',
        awayTeam: 'كريستال بالاس',
        kickoffAt: _kickoff,
      );

      expect(result, isA<Err<FixtureSchedule>>());
      expect(setup.finder.calls, 0);
    });

    test('without a finder the match is stored as before', () async {
      final schedules = FakeFixtureScheduleRepository();
      final useCase = RegisterFixtureSchedule(
        repository: schedules,
        idGenerator: FakeIdGenerator([_newId]),
      );

      final result = await useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'ليون',
        awayTeam: 'كريستال بالاس',
        kickoffAt: _kickoff,
      );

      expect(result, isA<Ok<FixtureSchedule>>());
      expect((await _stored(schedules))?.awayTeam, 'كريستال بالاس');
    });
  });
}
