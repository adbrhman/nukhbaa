/// The batched read behind the match card's win shares.
///
/// [GetFixturePredictionDistribution] answers the same question for ONE
/// fixture and stays exactly as it is -- it backs
/// `GET /seasons/{id}/fixtures/{fixtureId}/prediction-distribution`, which
/// keeps working. This port exists because the current-month feed needs the
/// same answer for EVERY fixture at once: the client used to ask per card,
/// so a twenty-match day cost twenty round trips over a phone network to
/// learn twenty numbers the feed's own query could have produced in one.
///
/// A separate port rather than a method on [FixturePredictionRepository]
/// because that interface has ten implementers (one Postgres adapter and
/// nine test doubles); a single narrow read does not justify editing all of
/// them, and the feed use-case takes this dependency optionally, so every
/// existing construction of it keeps compiling unchanged.
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// How many DECISIVE predictions one fixture holds on each side.
///
/// Draws are counted on neither side and are excluded from the denominator,
/// so the two percentages describe the split between the two teams among the
/// people who picked a winner -- the same definition
/// [GetFixturePredictionDistribution] already uses, kept identical here on
/// purpose: two reads of the same fact must not disagree.
final class FixtureOutcomeTally {
  /// Creates a tally for [fixture].
  const FixtureOutcomeTally({
    required this.fixture,
    required this.homeWins,
    required this.awayWins,
    this.draws = 0,
  });

  /// The fixture this tally belongs to.
  final FixtureRef fixture;

  /// Predictions giving the home side more goals than the away side.
  final int homeWins;

  /// Predictions giving the away side more goals than the home side.
  final int awayWins;

  /// Predictions calling a draw. Not part of [homeWinPercentage] or
  /// [awayWinPercentage]; only of [outcomeShares].
  final int draws;

  /// Every prediction on the fixture: home wins, draws and away wins.
  int get total => homeWins + draws + awayWins;

  /// The three-way split of ALL predictions -- home win, draw, away win --
  /// as whole percentages that add up to exactly 100 (largest remainder),
  /// or all zero when nobody has predicted. The live card's "60% / 22% /
  /// 18%" line; the two decisive shares above keep their own meaning.
  ({int home, int draw, int away}) get outcomeShares {
    final int all = total;
    if (all == 0) return (home: 0, draw: 0, away: 0);
    final List<int> counts = <int>[homeWins, draws, awayWins];
    final List<int> shares = <int>[
      for (final int c in counts) (c * 100) ~/ all,
    ];
    final List<int> order = <int>[0, 1, 2]
      ..sort((a, b) {
        final int byRemainder = ((counts[b] * 100) % all).compareTo(
          (counts[a] * 100) % all,
        );
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    int left = 100 - shares.fold<int>(0, (sum, s) => sum + s);
    for (final int i in order) {
      if (left == 0) break;
      shares[i]++;
      left--;
    }
    return (home: shares[0], draw: shares[1], away: shares[2]);
  }

  /// The home share of decisive predictions, 0 when there are none.
  int get homeWinPercentage => _share(homeWins);

  /// The away share of decisive predictions, 0 when there are none.
  int get awayWinPercentage => _share(awayWins);

  int _share(int side) {
    final int decisive = homeWins + awayWins;
    if (decisive == 0) return 0;
    return (side * 100 / decisive).round();
  }
}

/// Reads the decisive outcome split for MANY fixtures in a single query.
///
/// An implementation MUST NOT issue one query per fixture, and MUST simply
/// omit a fixture nobody has predicted rather than inventing a zero row --
/// the caller treats an absent fixture and an all-draw fixture identically.
abstract interface class FixturePredictionTallyReader {
  /// The tally for each of [fixtures] that has at least one prediction.
  /// An empty [fixtures] is `Ok(<empty list>)` without touching storage.
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  );
}
