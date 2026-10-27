import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

RulesetSnapshot _snapshot(Map<String, Object?> payload, {int version = 1}) =>
    (RulesetSnapshot.create(payload: payload, rulesetVersion: version)
            as Ok<RulesetSnapshot>)
        .value;

/// The exact payload shape `ConfiguredRulesetProvider` freezes today.
RulesetSnapshot _defaultSnapshot({int version = 1}) => _snapshot(const {
  'format': 'football_scoreline',
  'points': {'exact_scoreline': 5, 'correct_outcome': 2, 'incorrect': 0},
}, version: version);

void main() {
  group('ScoringRuleset.fromSnapshot', () {
    test('interprets the configured default snapshot', () {
      final result = ScoringRuleset.fromSnapshot(_defaultSnapshot(version: 3));
      final ruleset = (result as Ok<ScoringRuleset>).value;
      expect(ruleset.rulesetVersion, 3);
      expect(ruleset.exactScorelinePoints, 5);
      expect(ruleset.correctOutcomePoints, 2);
      expect(ruleset.incorrectPoints, 0);
    });

    test('reads the sole exact bonus and its first kickoff (v4)', () {
      final ruleset =
          (ScoringRuleset.fromSnapshot(
                    _snapshot(const {
                      'format': 'football_scoreline',
                      'points': {
                        'exact_scoreline': 3,
                        'correct_outcome': 0,
                        'incorrect': 0,
                      },
                      'double_multiplier': 2,
                      'solo_exact_bonus': 3,
                      'solo_exact_since': '2026-10-31T21:00:00.000Z',
                    }, version: 4),
                  )
                  as Ok<ScoringRuleset>)
              .value;
      expect(ruleset.soloExactBonusPoints, 3);
      expect(ruleset.soloExactSince, DateTime.utc(2026, 10, 31, 21));
      expect(
        ruleset.soloExactBonusAppliesTo(DateTime.utc(2026, 10, 31, 21)),
        isTrue,
      );
      expect(
        ruleset.soloExactBonusAppliesTo(DateTime.utc(2026, 10, 31, 20, 59)),
        isFalse,
      );
      expect(ruleset.soloExactBonusAppliesTo(null), isFalse);
    });

    test('a snapshot before the bonus pays none', () {
      final ruleset =
          (ScoringRuleset.fromSnapshot(_defaultSnapshot())
                  as Ok<ScoringRuleset>)
              .value;
      expect(ruleset.soloExactBonusPoints, 0);
      expect(ruleset.soloExactSince, isNull);
      expect(
        ruleset.soloExactBonusAppliesTo(DateTime.utc(2027, 1, 1)),
        isFalse,
      );
    });

    test('rejects a negative bonus or a since that is not a UTC instant', () {
      Map<String, Object?> payload(Object? bonus, Object? since) => {
        'format': 'football_scoreline',
        'points': {'exact_scoreline': 3, 'correct_outcome': 0, 'incorrect': 0},
        'solo_exact_bonus': bonus,
        'solo_exact_since': since,
      };
      expect(
        (ScoringRuleset.fromSnapshot(_snapshot(payload(-1, null)))
                as Err<ScoringRuleset>)
            .error
            .code,
        'scoring.ruleset_solo_exact_bonus_invalid',
      );
      for (final since in <Object?>['2026-11-01', 'soon', 20261101]) {
        expect(
          (ScoringRuleset.fromSnapshot(_snapshot(payload(3, since)))
                  as Err<ScoringRuleset>)
              .error
              .code,
          'scoring.ruleset_solo_exact_since_invalid',
        );
      }
    });

    test('rejects a snapshot for an unsupported format', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'survivor',
          'points': {
            'exact_scoreline': 5,
            'correct_outcome': 2,
            'incorrect': 0,
          },
        }),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_format_unsupported');
    });

    test('rejects a snapshot missing the points map', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {'format': 'football_scoreline'}),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_points_missing');
    });

    test('rejects a non-integer award', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'football_scoreline',
          'points': {
            'exact_scoreline': '5',
            'correct_outcome': 2,
            'incorrect': 0,
          },
        }),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_award_invalid');
    });

    test('rejects a missing award key', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'football_scoreline',
          'points': {'exact_scoreline': 5, 'correct_outcome': 2},
        }),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_award_invalid');
    });

    test('rejects a negative award', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'football_scoreline',
          'points': {
            'exact_scoreline': 5,
            'correct_outcome': -1,
            'incorrect': 0,
          },
        }),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_award_negative');
    });

    test('rejects non-monotonic awards (outcome worth more than exact)', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'football_scoreline',
          'points': {
            'exact_scoreline': 2,
            'correct_outcome': 5,
            'incorrect': 0,
          },
        }),
      );
      final error = (result as Err<ScoringRuleset>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'scoring.ruleset_non_monotonic');
    });

    test(
      'rejects non-monotonic awards (incorrect worth more than outcome)',
      () {
        final result = ScoringRuleset.fromSnapshot(
          _snapshot(const {
            'format': 'football_scoreline',
            'points': {
              'exact_scoreline': 5,
              'correct_outcome': 1,
              'incorrect': 3,
            },
          }),
        );
        final error = (result as Err<ScoringRuleset>).error;
        expect(error.kind, ErrorKind.validation);
        expect(error.code, 'scoring.ruleset_non_monotonic');
      },
    );

    test('accepts equal awards (monotonicity is non-strict)', () {
      final result = ScoringRuleset.fromSnapshot(
        _snapshot(const {
          'format': 'football_scoreline',
          'points': {
            'exact_scoreline': 3,
            'correct_outcome': 3,
            'incorrect': 3,
          },
        }),
      );
      expect(result.isOk, isTrue);
    });
  });

  group('ScoringRuleset equality', () {
    test('identical rulesets compare equal and share a hashCode', () {
      final a = ScoringRuleset.fromSnapshot(_defaultSnapshot());
      final b = ScoringRuleset.fromSnapshot(_defaultSnapshot());
      expect((a as Ok<ScoringRuleset>).value, (b as Ok<ScoringRuleset>).value);
      expect(a.value.hashCode, b.value.hashCode);
    });

    test('a differing version breaks equality', () {
      final a =
          (ScoringRuleset.fromSnapshot(_defaultSnapshot(version: 1))
                  as Ok<ScoringRuleset>)
              .value;
      final b =
          (ScoringRuleset.fromSnapshot(_defaultSnapshot(version: 2))
                  as Ok<ScoringRuleset>)
              .value;
      expect(a, isNot(b));
    });
  });
}
