import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The production rules of script 159: 3 for an exact call, doubled by the
/// double, and 3 more for the only exact call from 1 November 2026.
ScoringRuleset _rules() =>
    (ScoringRuleset.fromSnapshot(
              (RulesetSnapshot.create(
                        payload: const {
                          'format': 'football_scoreline',
                          'points': {
                            'exact_scoreline': 3,
                            'correct_outcome': 0,
                            'incorrect': 0,
                          },
                          'double_multiplier': 2,
                          'solo_exact_bonus': 3,
                          'solo_exact_since': '2026-10-31T21:00:00.000Z',
                        },
                        rulesetVersion: 4,
                      )
                      as Ok<RulesetSnapshot>)
                  .value,
            )
            as Ok<ScoringRuleset>)
        .value;

const FixtureRef _fixture = FixtureRef('11111111-1111-1111-1111-111111111111');
const FixtureResult _result = FixtureResult.fromStored(
  fixture: _fixture,
  homeGoals: 2,
  awayGoals: 1,
);

ParticipantFixtureScore _graded(
  String participant,
  int home,
  int away, {
  bool isDouble = false,
}) =>
    (Scoring.scoreFixture(
              prediction: FixturePrediction.fromStored(
                id: PredictionId('p-$participant'),
                fixture: _fixture,
                participantId: ParticipantId(participant),
                homeGoals: home,
                awayGoals: away,
                isDouble: isDouble,
              ),
              result: _result,
              ruleset: _rules(),
              rulesetVersion: 4,
            )
            as Ok<ParticipantFixtureScore>)
        .value;

Map<String, (FixtureScoreGrade, int)> _byPlayer(
  List<ParticipantFixtureScore> scores,
) => <String, (FixtureScoreGrade, int)>{
  for (final s in scores) s.participantId.value: (s.result.grade, s.points),
};

void main() {
  final DateTime november = DateTime.utc(2026, 11, 1, 18);

  test('the only exact call: 6, the grade still exact', () {
    final scores = Scoring.applySoloExactBonus(
      scores: <ParticipantFixtureScore>[
        _graded('a', 2, 1),
        _graded('b', 1, 1),
        _graded('c', 0, 3, isDouble: true),
      ],
      ruleset: _rules(),
      kickoffAt: november,
    );
    expect(_byPlayer(scores), <String, (FixtureScoreGrade, int)>{
      'a': (FixtureScoreGrade.exactScoreline, 6),
      'b': (FixtureScoreGrade.incorrect, 0),
      'c': (FixtureScoreGrade.incorrect, 0),
    });
    expect(
      <String>[for (final s in scores) s.participantId.value],
      <String>['a', 'b', 'c'],
    );
  });

  test('the only exact call on the double: 9', () {
    final scores = Scoring.applySoloExactBonus(
      scores: <ParticipantFixtureScore>[
        _graded('a', 2, 1, isDouble: true),
        _graded('b', 1, 1),
      ],
      ruleset: _rules(),
      kickoffAt: november,
    );
    expect(_byPlayer(scores)['a'], (FixtureScoreGrade.exactScoreline, 9));
  });

  test('two exact calls: no bonus for either', () {
    final scores = Scoring.applySoloExactBonus(
      scores: <ParticipantFixtureScore>[
        _graded('a', 2, 1),
        _graded('b', 2, 1, isDouble: true),
      ],
      ruleset: _rules(),
      kickoffAt: november,
    );
    expect(_byPlayer(scores)['a']!.$2, 3);
    expect(_byPlayer(scores)['b']!.$2, 6);
  });

  test('a kickoff before 1 November 00:00 Riyadh, or unknown: no bonus', () {
    for (final DateTime? kickoff in <DateTime?>[
      DateTime.utc(2026, 10, 31, 20, 59),
      null,
    ]) {
      final scores = Scoring.applySoloExactBonus(
        scores: <ParticipantFixtureScore>[_graded('a', 2, 1, isDouble: true)],
        ruleset: _rules(),
        kickoffAt: kickoff,
      );
      expect(_byPlayer(scores)['a']!.$2, 6);
    }
  });

  test('no exact call: nothing changes', () {
    final List<ParticipantFixtureScore> before = <ParticipantFixtureScore>[
      _graded('a', 0, 0),
      _graded('b', 1, 2),
    ];
    expect(
      Scoring.applySoloExactBonus(
        scores: before,
        ruleset: _rules(),
        kickoffAt: november,
      ),
      before,
    );
  });
}
