import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One user whose day is still open and whose first unpredicted fixture of
/// today starts soon (plan P3-4b).
final class StreakSaverTarget {
  /// Creates a target.
  const StreakSaverTarget({
    required this.userId,
    required this.fixtureId,
    required this.tokens,
    required this.optedIn,
    this.utcOffsetMinutes,
  });

  /// The user whose day would fail at the next kickoff.
  final UserId userId;

  /// Their first fixture of today still unpredicted.
  final FixtureRef fixtureId;

  /// Their registered FCM tokens. Never empty.
  final List<String> tokens;

  /// Their `streak_saver` switch (0066); true when never changed.
  final bool optedIn;

  /// Minutes the user's clock is ahead of UTC, or null if never reported.
  final int? utcOffsetMinutes;
}

/// Read/write port for the streak-saver sweep (migrations 0039, 0066).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class StreakSaverRepository {
  /// Users with a device, active in a season that plays on [today] (a
  /// Riyadh day, `YYYY-MM-DD`), whose EARLIEST unpredicted fixture of that
  /// day kicks off in `(from, to]`, and who were not sent a streak saver on
  /// [today]. A day whose first gap already kicked off is lost, not saved,
  /// and never appears.
  Future<Result<List<StreakSaverTarget>>> dueTargets({
    required String today,
    required DateTime from,
    required DateTime to,
  });

  /// Records that [target] was pushed on [sendDate]. Idempotent.
  Future<Result<void>> markSent({
    required StreakSaverTarget target,
    required String sendDate,
    required DateTime now,
  });

  /// Deletes device tokens FCM reported as permanently invalid.
  Future<Result<void>> forgetTokens(List<String> tokens);
}
