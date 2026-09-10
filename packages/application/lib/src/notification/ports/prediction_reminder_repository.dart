import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read/write port for the prediction-reminder sweep (migrations 0039, 0040).
///
/// General contract (Application ADR §2): never throws, maps driver failures
/// to [ErrorKind.transient]. Tier-3 -- a failure here is confined to the
/// reminder use-case and never reaches the points path.
abstract interface class PredictionReminderRepository {
  /// The earliest kickoff scheduled inside `[windowStart, windowEnd)` among
  /// fixtures actually linked to a season, or `Ok(null)` when the day has no
  /// programme at all.
  Future<Result<DateTime?>> firstKickoffInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  });

  /// Users who are due a reminder: active participants of a season that owns
  /// at least one fixture in the window, who have submitted NO prediction for
  /// any of that window's fixtures, who have not already been reminded on
  /// [reminderDate], and who have at least one registered device.
  ///
  /// [reminderDate] is `YYYY-MM-DD` in the reminder's zone.
  Future<Result<List<ReminderTarget>>> pendingTargets({
    required DateTime windowStart,
    required DateTime windowEnd,
    required String reminderDate,
  });

  /// Records that [userIds] were reminded on [reminderDate]. Idempotent: a
  /// user already recorded for that day is left alone.
  Future<Result<void>> markSent({
    required List<UserId> userIds,
    required String reminderDate,
    required DateTime now,
  });

  /// Deletes device tokens FCM reported as permanently invalid.
  ///
  /// It lives here rather than on [DeviceTokenRepository] because the only
  /// thing that ever learns a token is dead is this sweep: the registration
  /// port writes tokens, this one retires them.
  Future<Result<void>> forgetTokens(List<String> tokens);
}
