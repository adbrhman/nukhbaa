import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

const _competitionA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _competitionB = 'bbbbbbbb-0000-0000-0000-000000000002';
const _seasonA = 'aaaaaaaa-0000-0000-0000-000000000011';
const _seasonB = 'bbbbbbbb-0000-0000-0000-000000000012';
const _roundA1 = 'aaaaaaaa-0000-0000-0000-000000000021';
const _roundA2Locked = 'aaaaaaaa-0000-0000-0000-000000000022';
const _roundB1 = 'bbbbbbbb-0000-0000-0000-000000000023';
const _roundPrivate = 'cccccccc-0000-0000-0000-000000000024';

const _fixtureX = 'ffffffff-0000-0000-0000-0000000000f1';
const _fixtureY = 'ffffffff-0000-0000-0000-0000000000f2';

Competition _competition(String id, String name, {bool public = true}) =>
    (Competition.create(
              id: CompetitionId(id),
              name: name,
              format: FormatType.footballScoreline,
              visibility: public
                  ? CompetitionVisibility.public
                  : CompetitionVisibility.private,
            )
            as Ok<Competition>)
        .value;

CompetitionSeason _season(String id, String competitionId) =>
    (CompetitionSeason.create(
              id: SeasonId(id),
              competitionId: CompetitionId(competitionId),
              label: '2026/27',
              startAt: DateTime.utc(2026, 8, 1),
              endAt: DateTime.utc(2026, 9, 1),
            )
            as Ok<CompetitionSeason>)
        .value;

Round _round(
  String id,
  String seasonId, {
  int sequence = 1,
  RoundStatus status = RoundStatus.open,
}) {
  final opened =
      (Round.open(
                id: RoundId(id),
                seasonId: SeasonId(seasonId),
                sequence: sequence,
                predictionDeadline: DateTime.utc(2026, 8, 20),
                ruleset: testSnapshot(),
              )
              as Ok<Round>)
          .value;
  if (status == RoundStatus.open) return opened;
  final locked = (opened.transitionTo(RoundStatus.locked) as Ok<Round>).value;
  return status == RoundStatus.locked
      ? locked
      : (locked.transitionTo(RoundStatus.scored) as Ok<Round>).value;
}

RoundFixture _link({
  required String roundId,
  required String fixtureId,
  required int order,
}) =>
    (RoundFixture.create(
              roundId: RoundId(roundId),
              fixture: FixtureRef(fixtureId),
              displayOrder: order,
            )
            as Ok<RoundFixture>)
        .value;

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixtureScheduleRepository scheduleRepo;
  late ListMatchesFeed useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    scheduleRepo = FakeFixtureScheduleRepository();
    useCase = ListMatchesFeed(
      competitionRepository: competitionRepo,
      fixtureScheduleRepository: scheduleRepo,
    );
  });

  test(
    'flattens open rounds of public competitions, in competition-name '
    'then round-sequence order, each round\'s fixtures in display order',
    () async {
      competitionRepo
        ..seedCompetition(_competition(_competitionB, 'Beta League'))
        ..seedCompetition(_competition(_competitionA, 'Alpha League'))
        ..seedSeason(_season(_seasonA, _competitionA))
        ..seedSeason(_season(_seasonB, _competitionB))
        ..seedRound(_round(_roundA1, _seasonA))
        ..seedRound(_round(_roundB1, _seasonB));
      await competitionRepo.saveRoundFixture(
        _link(roundId: _roundA1, fixtureId: _fixtureY, order: 1),
      );
      await competitionRepo.saveRoundFixture(
        _link(roundId: _roundA1, fixtureId: _fixtureX, order: 0),
      );
      await competitionRepo.saveRoundFixture(
        _link(roundId: _roundB1, fixtureId: _fixtureX, order: 0),
      );

      final r = await useCase.call(principal: userPrincipal(_user));

      final list = (r as Ok<List<MatchFeedEntry>>).value;
      expect(list.map((e) => (e.competitionName, e.fixture.fixtureId.value)), [
        ('Alpha League', _fixtureX),
        ('Alpha League', _fixtureY),
        ('Beta League', _fixtureX),
      ]);
    },
  );

  test('excludes rounds that are not open', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(_season(_seasonA, _competitionA))
      ..seedRound(_round(_roundA1, _seasonA))
      ..seedRound(
        _round(
          _roundA2Locked,
          _seasonA,
          sequence: 2,
          status: RoundStatus.locked,
        ),
      );
    await competitionRepo.saveRoundFixture(
      _link(roundId: _roundA1, fixtureId: _fixtureX, order: 0),
    );
    await competitionRepo.saveRoundFixture(
      _link(roundId: _roundA2Locked, fixtureId: _fixtureY, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final list = (r as Ok<List<MatchFeedEntry>>).value;
    expect(list.map((e) => e.roundId.value).toList(), [_roundA1]);
  });

  test('excludes rounds of private competitions', () async {
    competitionRepo
      ..seedCompetition(
        _competition(_competitionA, 'Private League', public: false),
      )
      ..seedSeason(_season(_seasonA, _competitionA))
      ..seedRound(_round(_roundPrivate, _seasonA));
    await competitionRepo.saveRoundFixture(
      _link(roundId: _roundPrivate, fixtureId: _fixtureX, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<MatchFeedEntry>>).value, isEmpty);
  });

  test('an open round with no linked fixtures contributes nothing (never an '
      'empty placeholder row)', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(_season(_seasonA, _competitionA))
      ..seedRound(_round(_roundA1, _seasonA));

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<MatchFeedEntry>>).value, isEmpty);
  });

  test('no open rounds anywhere is a legitimate empty list', () async {
    final r = await useCase.call(principal: userPrincipal(_user));

    expect(r, isA<Ok<List<MatchFeedEntry>>>());
    expect((r as Ok<List<MatchFeedEntry>>).value, isEmpty);
  });

  test('a linked fixture with a registered schedule carries its team names '
      'and kickoff', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(_season(_seasonA, _competitionA))
      ..seedRound(_round(_roundA1, _seasonA));
    await competitionRepo.saveRoundFixture(
      _link(roundId: _roundA1, fixtureId: _fixtureX, order: 0),
    );
    scheduleRepo.seed(
      (FixtureSchedule.create(
                fixture: const FixtureRef(_fixtureX),
                homeTeam: 'Al Hilal',
                awayTeam: 'Al Nassr',
                kickoffAt: DateTime.utc(2026, 8, 20, 18),
              )
              as Ok<FixtureSchedule>)
          .value,
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final entry = (r as Ok<List<MatchFeedEntry>>).value.single;
    expect(entry.fixture.homeTeam, 'Al Hilal');
    expect(entry.fixture.awayTeam, 'Al Nassr');
    expect(entry.fixture.kickoffAt, DateTime.utc(2026, 8, 20, 18));
  });

  test('a linked fixture with no registered schedule carries null fields '
      '(Axiom 3)', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(_season(_seasonA, _competitionA))
      ..seedRound(_round(_roundA1, _seasonA));
    await competitionRepo.saveRoundFixture(
      _link(roundId: _roundA1, fixtureId: _fixtureX, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final entry = (r as Ok<List<MatchFeedEntry>>).value.single;
    expect(entry.fixture.homeTeam, isNull);
    expect(entry.fixture.awayTeam, isNull);
    expect(entry.fixture.kickoffAt, isNull);
  });

  test('a transient competition-repository failure on the open-rounds query '
      'is propagated unchanged', () async {
    competitionRepo.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final err = (r as Err<List<MatchFeedEntry>>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });
}
