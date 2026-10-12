import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One player who predicted part of today's matches and left the rest open
/// (batch 117).
final class IncompleteDayTarget {
  /// Creates a target.
  const IncompleteDayTarget({
    required this.userId,
    required this.tokens,
    required this.remaining,
    required this.optedIn,
    this.utcOffsetMinutes,
  });

  /// The player.
  final UserId userId;

  /// Their registered FCM tokens. Never empty.
  final List<String> tokens;

  /// Today's matches they have not predicted that have not kicked off yet.
  /// At least one.
  final int remaining;

  /// Their `prediction_reminder` switch (0063); true when never changed.
  /// The daily reminder's switch covers this push too: both ask the player
  /// to predict today's matches.
  final bool optedIn;

  /// Minutes the player's clock is ahead of UTC, or null if never reported.
  final int? utcOffsetMinutes;
}

/// Read/write port for the "N matches still to predict" sweep (migrations
/// 0039, 0055, 0063, 0106).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class IncompleteDayReminderRepository {
  /// Players with a device, active in a season that plays on [today] (a
  /// Riyadh day, `YYYY-MM-DD`), who predicted at least one of that day's
  /// matches, whose EARLIEST unpredicted match still to kick off after [now]
  /// kicks off in `(from, to]`, and who were not sent this push on [today].
  /// [IncompleteDayTarget.remaining] counts that day's unpredicted matches
  /// kicking off after [now].
  Future<Result<List<IncompleteDayTarget>>> dueTargets({
    required String today,
    required DateTime now,
    required DateTime from,
    required DateTime to,
  });

  /// Records that [userId] was pushed on [sendDate]. Idempotent.
  Future<Result<void>> markSent({
    required UserId userId,
    required String sendDate,
    required DateTime now,
  });

  /// Deletes device tokens FCM reported as permanently invalid.
  Future<Result<void>> forgetTokens(List<String> tokens);
}
