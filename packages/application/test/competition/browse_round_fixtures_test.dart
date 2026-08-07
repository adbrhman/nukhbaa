import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _round = '33333333-3333-3333-3333-333333333333';
const _otherRound = '44444444-4444-4444-4444-444444444444';

const _fa = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _fb = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _fc = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

RoundFixture _link({
  required String roundId,
  required String fixtureId,
  required int order,
}) => RoundFixture.fromStored(
  roundId: RoundId(roundId),
  fixture: FixtureRef(fixtureId),
  displayOrder: order,
);

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixtureScheduleRepository scheduleRepo;
  late BrowseRoundFixtures useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    scheduleRepo = FakeFixtureScheduleRepository();
    useCase = BrowseRoundFixtures(
      competitionRepository: competitionRepo,
      fixtureScheduleRepository: scheduleRepo,
    );
  });

  Future<void> seed(RoundFixture link) async {
    final r = await competitionRepo.saveRoundFixture(link);
    expect(r.isOk, isTrue);
  }

  test(
    'an authenticated user browses a round\'s fixtures in display order',
    () async {
      // Saved out of order to prove the read imposes display_order ordering.
      await seed(_link(roundId: _round, fixtureId: _fb, order: 1));
      await seed(_link(roundId: _round, fixtureId: _fa, order: 0));
      await seed(_link(roundId: _round, fixtureId: _fc, order: 2));

      final r = await useCase.call(
        principal: userPrincipal(_user),
        roundId: _round,
      );

      final list = (r as Ok<List<RoundFixtureCard>>).value;
      expect(list.map((x) => x.displayOrder).toList(), [0, 1, 2]);
      expect(list.map((x) => x.fixtureId.value).toList(), [_fa, _fb, _fc]);
    },
  );

  test('a linked fixture with a registered schedule carries its team names '
      'and kickoff', () async {
    await seed(_link(roundId: _round, fixtureId: _fa, order: 0));
    final schedule =
        (FixtureSchedule.create(
                  fixture: FixtureRef(_fa),
                  homeTeam: 'Al Hilal',
                  awayTeam: 'Al Nassr',
                  kickoffAt: DateTime.utc(2026, 8, 20, 18),
                )
                as Ok<FixtureSchedule>)
            .value;
    scheduleRepo.seed(schedule);

    final r = await useCase.call(
      principal: userPrincipal(_user),
      roundId: _round,
    );

    final card = (r as Ok<List<RoundFixtureCard>>).value.single;
    expect(card.homeTeam, 'Al Hilal');
    expect(card.awayTeam, 'Al Nassr');
    expect(card.kickoffAt, DateTime.utc(2026, 8, 20, 18));
  });

  test('a linked fixture with no registered schedule yet carries null fields '
      '(Axiom 3 — the link never verifies a schedule exists)', () async {
    await seed(_link(roundId: _round, fixtureId: _fa, order: 0));

    final r = await useCase.call(
      principal: userPrincipal(_user),
      roundId: _round,
    );

    final card = (r as Ok<List<RoundFixtureCard>>).value.single;
    expect(card.homeTeam, isNull);
    expect(card.awayTeam, isNull);
    expect(card.kickoffAt, isNull);
  });

  test('only the requested round\'s fixtures are returned', () async {
    await seed(_link(roundId: _round, fixtureId: _fa, order: 0));
    await seed(_link(roundId: _otherRound, fixtureId: _fb, order: 0));

    final r = await useCase.call(
      principal: userPrincipal(_user),
      roundId: _round,
    );

    final list = (r as Ok<List<RoundFixtureCard>>).value;
    expect(list.map((x) => x.fixtureId.value).toList(), [_fa]);
  });

  test(
    'an absent/empty round is a legitimate empty list, never not-found',
    () async {
      final r = await useCase.call(
        principal: userPrincipal(_user),
        roundId: _round,
      );

      expect(r, isA<Ok<List<RoundFixtureCard>>>());
      expect((r as Ok<List<RoundFixtureCard>>).value, isEmpty);
    },
  );

  test('a malformed id is a validation error before any lookup', () async {
    final r = await useCase.call(
      principal: userPrincipal(_user),
      roundId: 'not-a-uuid',
    );

    expect((r as Err<List<RoundFixtureCard>>).error.kind, ErrorKind.validation);
  });

  test(
    'a transient competition-repository failure is propagated unchanged',
    () async {
      competitionRepo.failNextWith(
        const AppError.transient('db.unavailable', 'connection reset'),
      );

      final r = await useCase.call(
        principal: userPrincipal(_user),
        roundId: _round,
      );

      final err = (r as Err<List<RoundFixtureCard>>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, 'db.unavailable');
    },
  );
}
