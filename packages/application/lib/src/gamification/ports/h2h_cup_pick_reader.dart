// NK309_03
/// Read port for the fixtures of the Elite Cup's stages and the players'
/// picks on them (script 309).
///
/// Backed by `PostgresH2hCupPickReader` (script 311). It reads; it decides
/// nothing and scores nothing. A locked stage's fixtures are its frozen
/// list; an unlocked stage's are the visible, non-test fixtures of its day
/// as they stand now. A frozen fixture that left the stage's day, was
/// hidden or is a test fixture is returned with
/// [H2hCupStageFixture.counted] false: it is void for both sides.
///
/// **A pick of another player is the server's to withhold.** The adapter
/// returns the pick of the reader himself always, and the pick of any other
/// player only for a fixture whose kickoff is at or before `nowUtc` (the
/// server clock the caller passes); a fixture with no kickoff withholds
/// them. The use-case checks the same rule again before anything leaves it.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
library;

import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/h2h_round_fixture_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One fixture of a cup stage as the reader found it.
final class H2hCupStageFixture {
  /// Creates a fixture line.
  const H2hCupStageFixture({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.kickoffAt,
    required this.counted,
    required this.homeGoals,
    required this.awayGoals,
    required this.picks,
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

  /// Whether the fixture still counts for the stage: on the stage's day,
  /// visible and real.
  final bool counted;

  /// The recorded home goals, or null before a result.
  final int? homeGoals;

  /// The recorded away goals, or null before a result.
  final int? awayGoals;

  /// The picks the reader may hand over, by player: the reader's own, and
  /// another player's only once the fixture has kicked off. A player who
  /// made no pick is absent.
  final Map<UserId, H2hFixturePick> picks;
}

/// Read port for the fixtures of cup stages and the picks on them.
abstract interface class H2hCupPickReader {
  /// The fixtures of every stage of [stages], by kickoff (none registered
  /// last), keyed by stage id, in one reading. A stage with no fixture maps
  /// to an empty list. The picks are those of the players of the stage's
  /// pairs: [reader]'s own always, the others' only for fixtures already
  /// kicked off at [nowUtc].
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  });
}
