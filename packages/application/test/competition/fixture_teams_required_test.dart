/// Script 93 through the real use-cases: with `requireTeamIds` (the server's
/// root) a match that is not a test needs both its teams from the catalog,
/// on registration and on correction; and a match of a club that already
/// has one within 12 hours is refused, naming the match on file -- the
/// 2026-10-15 copy "هوفنهايم - بيشتكاش" beside "هوفنهايم - بشكتاش".
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _newId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _syncedId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _adminId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _hoffenheimId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _benficaId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _auditId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

// Thursday 2026-10-15 22:00 in Riyadh.
final _kickoff = DateTime.utc(2026, 10, 15, 19);

/// Answers [answer] and counts the calls.
final class _Finder implements SameMatchFinder {
  _Finder(this.answer);

  final SameMatch? answer;
  int calls = 0;

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
    return Result.ok(answer);
  }
}

({
  RegisterFixtureSchedule useCase,
  _Finder finder,
  FakeFixtureScheduleRepository schedules,
})
_register({SameMatch? found}) {
  final schedules = FakeFixtureScheduleRepository();
  final finder = _Finder(found);
  return (
    useCase: RegisterFixtureSchedule(
      repository: schedules,
      idGenerator: FakeIdGenerator([_newId]),
      sameMatchFinder: finder,
      requireTeamIds: true,
    ),
    finder: finder,
    schedules: schedules,
  );
}

Future<FixtureSchedule?> _stored(
  FakeFixtureScheduleRepository schedules,
) async =>
    ((await schedules.findByFixture(const FixtureRef(_newId)))
            as Ok<FixtureSchedule?>)
        .value;

void main() {
  group('RegisterFixtureSchedule with requireTeamIds', () {
    test('a side the catalog does not know is refused before anything is '
        'looked up', () async {
      final setup = _register();

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'هوفنهايم',
        awayTeam: 'بيشتكاش',
        kickoffAt: _kickoff,
        homeTeamId: _hoffenheimId,
      );

      final AppError error = (result as Err<FixtureSchedule>).error;
      expect(error.code, RegisterFixtureSchedule.teamsRequiredCode);
      expect(error.kind, ErrorKind.validation);
      expect(error.message, contains('قائمة الأندية'));
      expect(setup.finder.calls, 0);
      expect(await _stored(setup.schedules), isNull);
    });

    test('both teams from the catalog: checked and stored', () async {
      final setup = _register();

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'هوفنهايم',
        awayTeam: 'بنفيكا',
        kickoffAt: _kickoff,
        homeTeamId: _hoffenheimId,
        awayTeamId: _benficaId,
      );

      expect(result, isA<Ok<FixtureSchedule>>());
      expect(setup.finder.calls, 1);
      expect((await _stored(setup.schedules))?.awayTeamId?.value, _benficaId);
    });

    test('a test fixture may keep names the list does not know', () async {
      final setup = _register();

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'فريق أ',
        awayTeam: 'فريق ب',
        kickoffAt: _kickoff,
        isTest: true,
      );

      expect(result, isA<Ok<FixtureSchedule>>());
      expect(setup.finder.calls, 0);
    });

    test('a club with a match within 12 hours is refused, naming it', () async {
      final setup = _register(
        found: SameMatch(
          fixtureId: _syncedId,
          homeTeam: 'هوفنهايم',
          awayTeam: 'بشكتاش',
          kickoffAt: _kickoff,
          bothSides: false,
        ),
      );

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'هوفنهايم',
        awayTeam: 'بنفيكا',
        kickoffAt: _kickoff,
        homeTeamId: _hoffenheimId,
        awayTeamId: _benficaId,
      );

      final AppError error = (result as Err<FixtureSchedule>).error;
      expect(error.code, RegisterFixtureSchedule.duplicateCode);
      expect(error.message, contains('لأحد الفريقين'));
      expect(error.message, contains('هوفنهايم - بشكتاش'));
      expect(error.message, contains('15/10'));
      expect(error.message, contains('22:00'));
      expect(await _stored(setup.schedules), isNull);
    });

    test('the same match is still told as the same match', () async {
      final setup = _register(
        found: SameMatch(
          fixtureId: _syncedId,
          homeTeam: 'هوفنهايم',
          awayTeam: 'بنفيكا',
          kickoffAt: _kickoff,
        ),
      );

      final result = await setup.useCase(
        principal: adminPrincipal(_adminId),
        homeTeam: 'هوفنهايم',
        awayTeam: 'بنفيكا',
        kickoffAt: _kickoff,
        homeTeamId: _hoffenheimId,
        awayTeamId: _benficaId,
      );

      expect(
        (result as Err<FixtureSchedule>).error.message,
        contains('هذه المباراة مضافة من قبل'),
      );
    });
  });

  group('CorrectFixtureSchedule with requireTeamIds', () {
    CorrectFixtureSchedule correct(FakeFixtureScheduleRepository schedules) =>
        CorrectFixtureSchedule(
          schedules,
          auditRecorder: AuditRecorder(
            auditLog: InMemoryAuditLogRepository(),
            idGenerator: FakeIdGenerator([_auditId]),
            clock: FixedClock(DateTime.utc(2026, 10, 14)),
          ),
          clock: FixedClock(DateTime.utc(2026, 10, 14)),
          requireTeamIds: true,
        );

    test(
      'a side the catalog does not know is refused, nothing written',
      () async {
        final schedules = FakeFixtureScheduleRepository()
          ..seed(
            FixtureSchedule.fromStored(
              fixture: const FixtureRef(_syncedId),
              homeTeam: 'هوفنهايم',
              awayTeam: 'بيشتكاش',
              kickoffAt: _kickoff,
            ),
          );

        final result = await correct(schedules)(
          principal: adminPrincipal(_adminId),
          fixtureId: _syncedId,
          homeTeam: 'هوفنهايم',
          awayTeam: 'بيشتكاش',
          kickoffAt: _kickoff.add(const Duration(minutes: 30)),
          homeTeamId: _hoffenheimId,
        );

        expect(
          (result as Err<FixtureSchedule>).error.code,
          RegisterFixtureSchedule.teamsRequiredCode,
        );
        final FixtureSchedule? kept =
            ((await schedules.findByFixture(const FixtureRef(_syncedId)))
                    as Ok<FixtureSchedule?>)
                .value;
        expect(kept?.kickoffAt, _kickoff);
      },
    );

    test('a test fixture is corrected with its names as they are', () async {
      final schedules = FakeFixtureScheduleRepository()
        ..seed(
          FixtureSchedule.fromStored(
            fixture: const FixtureRef(_syncedId),
            homeTeam: 'فريق أ',
            awayTeam: 'فريق ب',
            kickoffAt: _kickoff,
            isTest: true,
          ),
        );

      final result = await correct(schedules)(
        principal: adminPrincipal(_adminId),
        fixtureId: _syncedId,
        homeTeam: 'فريق أ',
        awayTeam: 'فريق ب',
        kickoffAt: _kickoff.add(const Duration(minutes: 30)),
      );

      expect(result, isA<Ok<FixtureSchedule>>());
    });
  });
}
