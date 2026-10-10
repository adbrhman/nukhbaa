import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the fixtures of one head-to-head round and the two players'
/// picks on them (migration 0100).
///
/// Backed by `PostgresH2hRoundFixtureReader`. It reads; it decides nothing
/// and scores nothing. A locked round's fixtures are its frozen list; an
/// unlocked round's are the visible, non-test fixtures of its day as they
/// stand now. A frozen fixture that left the round's day, was hidden or is a
/// test fixture is returned with [H2hRoundFixture.counted] false: it is void
/// for both sides, exactly as `H2hSheetReader` sums the round.
///
/// **The opponent's picks are the server's to withhold.** The adapter
/// returns a pick of [opponent] only for a fixture whose kickoff is at or
/// before `nowUtc` (the server clock the caller passes); the use-case checks
/// the same rule again with `FixtureLock` before anything leaves it.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hRoundFixtureReader {
  /// The fixtures of [round], by kickoff, with the picks of [reader] and,
  /// for fixtures already kicked off at [nowUtc], of [opponent].
  Future<Result<List<H2hRoundFixture>>> fixturesOf({
    required H2hRound round,
    required UserId reader,
    required UserId? opponent,
    required DateTime nowUtc,
  });
}

/// One player's prediction for one fixture, with its stored score.
final class H2hFixturePick {
  /// Creates a pick.
  const H2hFixturePick({
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    required this.points,
    required this.exact,
  });

  /// The predicted home goals.
  final int homeGoals;

  /// The predicted away goals.
  final int awayGoals;

  /// Whether the player doubled this fixture.
  final bool isDouble;

  /// The stored points (the double included), summed over the player's
  /// participations; null while no final score is stored.
  final int? points;

  /// Whether a stored score graded it an exact scoreline.
  final bool exact;
}

/// One fixture of a round as the reader found it.
final class H2hRoundFixture {
  /// Creates a fixture line.
  const H2hRoundFixture({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.kickoffAt,
    required this.counted,
    required this.homeGoals,
    required this.awayGoals,
    required this.mine,
    required this.theirs,
  });

  /// The fixture (UUID string).
  final String fixtureId;

  /// The home team's name.
  final String homeTeam;

  /// The away team's name.
  final String awayTeam;

  /// The home team's catalogue id, when known.
  final String? homeTeamId;

  /// The away team's catalogue id, when known.
  final String? awayTeamId;

  /// The kickoff (UTC), or null when none is registered.
  final DateTime? kickoffAt;

  /// Whether the fixture still counts for the round: on the round's day,
  /// visible and real.
  final bool counted;

  /// The recorded home goals, or null before a result.
  final int? homeGoals;

  /// The recorded away goals, or null before a result.
  final int? awayGoals;

  /// The reader's pick, or null.
  final H2hFixturePick? mine;

  /// The opponent's pick, or null (none asked, none made, or not kicked off).
  final H2hFixturePick? theirs;
}
