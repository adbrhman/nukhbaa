import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// [Scoring.gradeScoreline] grades a scoreline against a result with nothing
/// stored: the live view grades every prediction against the running score
/// with it, under the same rules as the recorded result.
void main() {
  final ScoringRuleset ruleset =
      (ScoringRuleset.fromSnapshot(
                (RulesetSnapshot.create(
                          payload: const {
                            'format': 'football_scoreline',
                            'double_multiplier': 2,
                            'points': {
                              'exact_scoreline': 3,
                              'correct_outcome': 1,
                              'incorrect': 0,
                            },
                          },
                          rulesetVersion: 1,
                        )
                        as Ok<RulesetSnapshot>)
                    .value,
              )
              as Ok<ScoringRuleset>)
          .value;

  const FixtureRef fixture = FixtureRef('11111111-1111-1111-1111-111111111111');

  FixtureResult running(int home, int away) =>
      (FixtureResult.create(fixture: fixture, homeGoals: home, awayGoals: away)
              as Ok<FixtureResult>)
          .value;

  FixtureScoreResult grade(
    int home,
    int away,
    FixtureResult result, {
    bool isDouble = false,
  }) => Scoring.gradeScoreline(
    prediction: FixtureScorePrediction.fromStored(
      fixture: fixture,
      homeGoals: home,
      awayGoals: away,
      isDouble: isDouble,
    ),
    result: result,
    ruleset: ruleset,
  );

  test('the exact score earns the exact points', () {
    final FixtureScoreResult graded = grade(1, 0, running(1, 0));
    expect(graded.grade, FixtureScoreGrade.exactScoreline);
    expect(graded.points, 3);
  });

  test('the right outcome earns the outcome points', () {
    final FixtureScoreResult graded = grade(2, 0, running(1, 0));
    expect(graded.grade, FixtureScoreGrade.correctOutcome);
    expect(graded.points, 1);
  });

  test('a wrong outcome earns the incorrect points', () {
    expect(grade(0, 1, running(1, 0)).grade, FixtureScoreGrade.incorrect);
  });

  test('the double multiplies, as on the recorded result', () {
    expect(grade(1, 0, running(1, 0), isDouble: true).points, 6);
  });
}
