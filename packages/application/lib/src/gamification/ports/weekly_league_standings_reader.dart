import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the standing of one weekly-league group (P2-4).
///
/// Backed by `PostgresWeeklyLeagueStandingsReader`. It sums; it decides
/// nothing. Who ranks above whom is `WeeklyLeaguePolicy.order`, in Dart,
/// where it is tested without a database.
///
/// The points come from the ONE source the monthly board reads:
/// `scoring.fixture_scores` plus the `streak_bonus` entries of
/// `ledger.fixture_point_entries`, restricted to the fixtures that kicked
/// off inside the Riyadh week. Nothing is stored per week, so a corrected
/// result moves the standing of a week that is still open and cannot touch
/// one that has been judged (the judgement is frozen in events).
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class WeeklyLeagueStandingsReader {
  /// One [WeeklyLeagueEntry] per member of [leagueId], in no particular
  /// order, carrying what that member earned inside the week opened by
  /// [weekStart].
  ///
  /// Every member appears, including one who earned nothing: a member with
  /// no scored fixture is a zero, not an absence.
  ///
  /// Membership is by user, points are by participant, so a member's week is
  /// the sum over every participation the user holds. [weekStart] is a
  /// Monday as a UTC midnight, as `WeeklyLeaguePolicy` produces.
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  });
}
