import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_fixture_score_repository.dart';
import 'fakes.dart';

const String _fixture = '11111111-1111-1111-1111-111111111111';
const String _hero = '21111111-1111-1111-1111-111111111111';
const String _banned = '22222222-1111-1111-1111-111111111111';
const String _other = '23333333-1111-1111-1111-111111111111';

/// The rules shipped since script 159: 3 for the exact score, doubled by
/// the double, and 3 more for the only exact call from 1 November 2026.
final RulesetSnapshot _rules =
    (RulesetSnapshot.create(
              payload: const {
                'format': 'football_scoreline',
                'double_multiplier': 2,
                'solo_exact_bonus': 3,
                'solo_exact_since': '2026-10-31T21:00:00.000Z',
                'points': {
                  'exact_scoreline': 3,
                  'correct_outcome': 0,
                  'incorrect': 0,
                },
              },
              rulesetVersion: 4,
            )
            as Ok<RulesetSnapshot>)
        .value;

final class _Suspended implements SuspendedPredictorsReader {
  _Suspended(this.ids);

  final Set<ParticipantId> ids;
  int reads = 0;

  @override
  Future<Result<Set<ParticipantId>>> suspendedOn(FixtureRef fixture) async {
    reads++;
    return Result.ok(ids);
  }
}

final class _Failing implements SuspendedPredictorsReader {
  @override
  Future<Result<Set<ParticipantId>>> suspendedOn(FixtureRef fixture) async =>
      const Result.err(AppError.transient('db.down', 'down'));
}

typedef _Harness = ({ScoreFixture useCase, FakeFixtureScoreRepository scores});

/// The fixture kicked off on 2 November 2026 and ended 2-1. Every entry of
/// [calls] is a participant and the score he called.
_Harness _harness(
  List<(String, int, int, bool)> calls, {
  SuspendedPredictorsReader? suspended,
}) {
  final predictions = FakeFixturePredictionRepository();
  final DateTime kickoff = DateTime.utc(2026, 11, 2, 18);
  var n = 0;
  for (final (String who, int home, int away, bool isDouble) in calls) {
    n++;
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: PredictionId('3111111$n-1111-1111-1111-111111111111'),
        fixture: const FixtureRef(_fixture),
        participantId: ParticipantId(who),
        homeGoals: home,
        awayGoals: away,
        isDouble: isDouble,
      ),
      kickoff.subtract(const Duration(hours: 2)),
    );
  }
  final results = FakeFixtureResultRepository()
    ..seed(
      const FixtureResult.fromStored(
        fixture: FixtureRef(_fixture),
        homeGoals: 2,
        awayGoals: 1,
      ),
    );
  final schedules = FakeFixtureScheduleRepository()
    ..seed(
      (FixtureSchedule.create(
                fixture: const FixtureRef(_fixture),
                homeTeam: 'A',
                awayTeam: 'B',
                kickoffAt: kickoff,
              )
              as Ok<FixtureSchedule>)
          .value,
    );
  final scores = FakeFixtureScoreRepository();
  return (
    useCase: ScoreFixture(
      fixturePredictionRepository: predictions,
      resultRepository: results,
      scoreRepository: scores,
      rulesetProvider: FakeRulesetProvider(Result.ok(_rules)),
      fixtureScheduleRepository: schedules,
      suspendedPredictors: suspended,
    ),
    scores: scores,
  );
}

Future<Map<String, int>> _points(_Harness h) async {
  final result = await h.useCase(
    principal: adminPrincipal('admin-1'),
    fixtureId: _fixture,
  );
  return <String, int>{
    for (final s in (result as Ok<List<ParticipantFixtureScore>>).value)
      s.participantId.value: s.result.points,
  };
}

void main() {
  group('a suspended account and the sole exact call (2026-11-01)', () {
    test('a suspended exact call no longer takes the bonus from the real '
        'sole caller: 6, and 9 on his double', () async {
      final single = await _points(
        _harness([
          (_hero, 2, 1, false),
          (_banned, 2, 1, false),
          (_other, 0, 0, false),
        ], suspended: _Suspended({const ParticipantId(_banned)})),
      );
      expect(single[_hero], 6);
      expect(single[_banned], 3, reason: 'its stored points stay, unboarded');

      final doubled = await _points(
        _harness([
          (_hero, 2, 1, true),
          (_banned, 2, 1, false),
        ], suspended: _Suspended({const ParticipantId(_banned)})),
      );
      expect(doubled[_hero], 9);
    });

    test(
      'a suspended account alone on the exact score gets no bonus',
      () async {
        final points = await _points(
          _harness([
            (_banned, 2, 1, false),
            (_other, 1, 1, false),
          ], suspended: _Suspended({const ParticipantId(_banned)})),
        );
        expect(points[_banned], 3);
        expect(points[_other], 0);
      },
    );

    test('two active exact calls still share no bonus', () async {
      final points = await _points(
        _harness([
          (_hero, 2, 1, false),
          (_other, 2, 1, false),
          (_banned, 0, 0, false),
        ], suspended: _Suspended({const ParticipantId(_banned)})),
      );
      expect((points[_hero], points[_other]), (3, 3));
    });

    test('without an exact call nobody is looked up', () async {
      final reader = _Suspended({const ParticipantId(_banned)});
      await _points(_harness([(_hero, 0, 0, false)], suspended: reader));
      expect(reader.reads, 0);
    });

    test('an unreadable suspension list scores nothing rather than paying '
        'the wrong player', () async {
      final h = _harness([
        (_hero, 2, 1, false),
        (_banned, 2, 1, false),
      ], suspended: _Failing());
      final result = await h.useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: _fixture,
      );
      expect(
        (result as Err<List<ParticipantFixtureScore>>).error.code,
        'db.down',
      );
    });
  });
}
