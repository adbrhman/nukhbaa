import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// How to reach one overtaken member (plan P3-4c).
final class OvertakenRecipient {
  /// Creates a recipient.
  const OvertakenRecipient({
    required this.tokens,
    required this.optedIn,
    required this.alreadySent,
    this.utcOffsetMinutes,
  });

  /// Their registered FCM tokens. Never empty.
  final List<String> tokens;

  /// Their `overtaken` switch (0066); true when never changed.
  final bool optedIn;

  /// Whether they were already told they were overtaken in this group.
  final bool alreadySent;

  /// Minutes the user's clock is ahead of UTC, or null if never reported.
  final int? utcOffsetMinutes;
}

/// Read/write port for the overtaken sweep (migrations 0061, 0066, 0067).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class OvertakenRepository {
  /// Every group of the week opened by [weekStart] (a Monday as a UTC
  /// midnight).
  Future<Result<List<WeeklyLeagueId>>> openLeagues({
    required DateTime weekStart,
  });

  /// The rank each member of [leagueId] had at the previous sweep.
  Future<Result<Map<UserId, int>>> rankMarks(WeeklyLeagueId leagueId);

  /// Overwrites the marks of [leagueId] with [ranks].
  Future<Result<void>> saveRankMarks({
    required WeeklyLeagueId leagueId,
    required Map<UserId, int> ranks,
    required DateTime now,
  });

  /// How to reach each of [userIds] about [leagueId]; users with no device
  /// are absent.
  Future<Result<Map<UserId, OvertakenRecipient>>> recipients({
    required WeeklyLeagueId leagueId,
    required List<UserId> userIds,
  });

  /// Records that [userId] was told about [leagueId] on [sendDate]. At most
  /// one such push per member per group, so one per week.
  Future<Result<void>> markSent({
    required UserId userId,
    required WeeklyLeagueId leagueId,
    required String sendDate,
    required DateTime now,
  });

  /// Deletes device tokens FCM reported as permanently invalid.
  Future<Result<void>> forgetTokens(List<String> tokens);
}
