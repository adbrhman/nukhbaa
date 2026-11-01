import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart' show FixedClock, userPrincipal;

const String _season = '11111111-1111-1111-1111-111111111111';
const String _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('22222222-2222-2222-2222-222222222222'),
  role: PlatformRole.user,
);

/// A season link and [homeCalls] calls of a home win.
FakeFixturePredictionRepository _calls(int homeCalls) {
  final repo = FakeFixturePredictionRepository()
    ..seedSeasonFixture(
      (SeasonFixture.create(
                seasonId: const SeasonId(_season),
                fixture: const FixtureRef(_fixture),
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value,
    );
  for (var i = 0; i < homeCalls; i++) {
    repo.seedPrediction(
      FixturePrediction.fromStored(
        id: PredictionId('3333333$i-3333-3333-3333-333333333333'),
        fixture: const FixtureRef(_fixture),
        participantId: ParticipantId('4444444$i-4444-4444-4444-444444444444'),
        homeGoals: 2,
        awayGoals: 0,
      ),
      DateTime.utc(2026, 11, 1),
    );
  }
  return repo;
}

FixtureSchedule _schedule({bool hidden = false, bool test = false}) =>
    FixtureSchedule.fromStored(
      fixture: const FixtureRef(_fixture),
      homeTeam: 'A',
      awayTeam: 'B',
      kickoffAt: DateTime.utc(2026, 11, 3, 18),
      hiddenAt: hidden ? DateTime.utc(2026, 11, 1) : null,
      isTest: test,
    );

Future<Result<FixturePredictionDistribution>> _split(
  FakeFixturePredictionRepository repo, {
  FixtureSchedule? schedule,
}) => GetFixturePredictionDistribution(
  fixturePredictionRepository: repo,
  fixtureScheduleRepository: schedule == null
      ? null
      : (FakeFixtureScheduleRepository()..seed(schedule)),
).call(principal: _player, seasonId: _season, fixtureId: _fixture);

const String _month = 'aaaaaaaa-0000-0000-0000-000000000011';
const String _few = 'ffffffff-0000-0000-0000-0000000000f1';
const String _many = 'ffffffff-0000-0000-0000-0000000000f2';

final class _Tallies implements FixturePredictionTallyReader {
  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async => const Result.ok(<FixtureOutcomeTally>[
    // Four calls: three home wins and a draw.
    FixtureOutcomeTally(
      fixture: FixtureRef(_few),
      homeWins: 3,
      awayWins: 0,
      draws: 1,
    ),
    // Five calls: the minimum.
    FixtureOutcomeTally(
      fixture: FixtureRef(_many),
      homeWins: 3,
      awayWins: 1,
      draws: 1,
    ),
  ]);
}

/// The real feed over a month holding [_few] and [_many].
Future<Map<String, CurrentMonthFixtureEntry>> _feed() async {
  const competition = 'aaaaaaaa-0000-0000-0000-000000000001';
  final competitions = FakeCompetitionRepository()
    ..seedCompetition(
      (Competition.create(
                id: const CompetitionId(competition),
                name: 'League',
                format: FormatType.footballScoreline,
                visibility: CompetitionVisibility.public,
              )
              as Ok<Competition>)
          .value,
    )
    ..seedSeason(
      (CompetitionSeason.create(
                id: const SeasonId(_month),
                competitionId: const CompetitionId(competition),
                label: '11/2026',
                startAt: DateTime.utc(2026, 10, 31, 21),
                endAt: DateTime.utc(2026, 11, 30, 21),
              )
              as Ok<CompetitionSeason>)
          .value,
    );
  final fixtures = FakeFixturePredictionRepository();
  for (final (String id, int order) in [(_few, 0), (_many, 1)]) {
    fixtures.seedSeasonFixture(
      (SeasonFixture.create(
                seasonId: const SeasonId(_month),
                fixture: FixtureRef(id),
                displayOrder: order,
              )
              as Ok<SeasonFixture>)
          .value,
    );
  }
  final result = await ListCurrentMonthFixtures(
    competitionRepository: competitions,
    fixturePredictionRepository: fixtures,
    fixtureScheduleRepository: FakeFixtureScheduleRepository(),
    clock: FixedClock(DateTime.utc(2026, 11, 1, 12)),
    predictionTallyReader: _Tallies(),
  )(principal: userPrincipal('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'));
  return <String, CurrentMonthFixtureEntry>{
    for (final e in (result as Ok<List<CurrentMonthFixtureEntry>>).value)
      e.fixture.fixtureId.value: e,
  };
}

void main() {
  test('the minimum is the app\'s: five calls', () {
    expect(crowdShareMinimum, 5);
  });

  group('the feed (M-2)', () {
    test('under five calls the counts are sent and every share is 0', () async {
      final CurrentMonthFixtureEntry few = (await _feed())[_few]!;
      expect((few.totalPredictions, few.decisivePredictions), (4, 3));
      expect(
        (few.homeOutcomeShare, few.drawOutcomeShare, few.awayOutcomeShare),
        (0, 0, 0),
      );
      expect((few.homeWinPercentage, few.awayWinPercentage), (0, 0));
    });

    test('from five calls the shares are sent', () async {
      final CurrentMonthFixtureEntry many = (await _feed())[_many]!;
      expect(many.totalPredictions, 5);
      expect(
        (many.homeOutcomeShare, many.drawOutcomeShare, many.awayOutcomeShare),
        (60, 20, 20),
      );
      expect(many.homeWinPercentage, 75);
    });
  });

  group('GET .../prediction-distribution (M-2, M-3)', () {
    test(
      'one to four calls show no share: they would tell each pick',
      () async {
        for (final int n in <int>[1, 4]) {
          final split =
              (await _split(_calls(n)) as Ok<FixturePredictionDistribution>)
                  .value;
          expect(
            (split.homeWinPercentage, split.awayWinPercentage),
            (0, 0),
            reason: '$n calls',
          );
        }
      },
    );

    test('from five calls the split is shown', () async {
      final split =
          (await _split(_calls(5)) as Ok<FixturePredictionDistribution>).value;
      expect(split.homeWinPercentage, 100);
    });

    test('a hidden fixture, or a test fixture asked by a player, is '
        'refused', () async {
      for (final FixtureSchedule schedule in <FixtureSchedule>[
        _schedule(hidden: true),
        _schedule(test: true),
      ]) {
        final result = await _split(_calls(6), schedule: schedule);
        expect(
          (result as Err<FixturePredictionDistribution>).error.code,
          'prediction.fixture_unavailable',
        );
      }
      final open = await _split(_calls(6), schedule: _schedule());
      expect(open, isA<Ok<FixturePredictionDistribution>>());
    });
  });
}
