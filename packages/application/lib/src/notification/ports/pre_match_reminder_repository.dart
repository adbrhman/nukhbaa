import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One user due the pre-match push for one fixture (plan P3-4a).
final class PreMatchTarget {
  /// Creates a target.
  const PreMatchTarget({
    required this.userId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.tokens,
    required this.optedIn,
    this.utcOffsetMinutes,
  });

  /// The user to remind: they follow one of the two teams.
  final UserId userId;

  /// The fixture about to start, which they have not predicted.
  final FixtureRef fixtureId;

  /// The home side's display name, as the schedule stores it.
  final String homeTeam;

  /// The away side's display name, as the schedule stores it.
  final String awayTeam;

  /// Their registered FCM tokens. Never empty.
  final List<String> tokens;

  /// Their `pre_match` switch (0066); true when they never changed it.
  final bool optedIn;

  /// Minutes the user's clock is ahead of UTC, or null if never reported.
  final int? utcOffsetMinutes;
}

/// Read/write port for the pre-match sweep (migrations 0065, 0066).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Tier-3: nothing on the points path
/// reads or writes it.
abstract interface class PreMatchReminderRepository {
  /// Users due a push for a fixture kicking off in `(from, to]`: they follow
  /// its home or away team, are active participants of a season that owns
  /// it, have not predicted it, were not already pushed about it, and own a
  /// device. One target per (user, fixture).
  Future<Result<List<PreMatchTarget>>> dueTargets({
    required DateTime from,
    required DateTime to,
  });

  /// Records that [target] was pushed, on the Riyadh day [sendDate]
  /// (`YYYY-MM-DD`). Idempotent.
  Future<Result<void>> markSent({
    required PreMatchTarget target,
    required String sendDate,
    required DateTime now,
  });

  /// Deletes device tokens FCM reported as permanently invalid.
  Future<Result<void>> forgetTokens(List<String> tokens);
}
