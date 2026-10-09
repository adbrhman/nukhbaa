import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for what the members of a head-to-head group did in its rounds
/// (migration 0100).
///
/// Backed by `PostgresH2hSheetReader`. It sums; it decides nothing. A
/// round's points are the stored fixture scores (the double included) over
/// its frozen fixtures that are still on the round's day, visible and real;
/// a fixture that is not is void for both sides. Nothing is stored per
/// round, so a corrected result moves a round until the month is judged.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hSheetReader {
  /// The members of [leagueId] and what each did in [rounds].
  ///
  /// Suspended members are left out: their seat plays the group average.
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  });

  /// How many Riyadh days of the month opened by [monthStart] each player
  /// predicted on. A player who predicted on none is absent.
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart);
}

/// A group's members and their rounds.
final class H2hGroupSheet {
  /// Creates a sheet.
  const H2hGroupSheet({
    required this.members,
    required this.scores,
    required this.settledRounds,
    required this.voidRounds,
  });

  /// The seats, suspended members left out.
  final List<H2hMember> members;

  /// What each member did in each locked round. A member missing from a
  /// round did not play it.
  final List<H2hRoundScore> scores;

  /// Numbers of the locked rounds whose every remaining fixture is scored.
  final Set<int> settledRounds;

  /// Numbers of the locked rounds with no fixture left (all moved, hidden or
  /// test): they count for nobody.
  final Set<int> voidRounds;
}
