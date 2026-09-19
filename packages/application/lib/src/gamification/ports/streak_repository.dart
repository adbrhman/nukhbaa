import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the streak (P1-3): which match days exist, and which of them
/// a user completed.
///
/// Backed by `PostgresStreakRepository`. It reports facts; the run itself is
/// counted by [StreakTally.fromMatchDays], in Dart.
///
/// General contract (Application ADR §2): MUST NOT throw; MUST map
/// infrastructure failures to [ErrorKind.transient].
abstract interface class StreakRepository {
  /// The match days at or before [upToDay], newest first, at most
  /// [limitDays] of them, each marked with whether [userId] completed it.
  ///
  /// A day with no fixtures is not a match day and does not appear: the
  /// streak is a run of days the user could have played.
  ///
  /// [upToDay] is a UTC midnight carrying a Riyadh day's date, as produced
  /// by `riyadhDayOf`. Days after it are excluded even when already
  /// completed — predicting tomorrow early does not lengthen today's run; it
  /// counts when tomorrow arrives.
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  });
}

/// One match day, and whether the user completed its challenge.
final class MatchDayCompletion {
  /// Creates a calendar entry.
  const MatchDayCompletion({required this.day, required this.completed});

  /// The Riyadh day, as a UTC midnight.
  final DateTime day;

  /// Whether a `daily_challenge_completed` event exists for this user and
  /// this day.
  final bool completed;
}
