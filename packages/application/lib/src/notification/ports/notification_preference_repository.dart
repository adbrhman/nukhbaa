import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One user's notification switches (P3-1, migration 0063).
///
/// A user who never changed anything has no stored row and reads as
/// [defaults]; every default is on, so the reminder keeps reaching the
/// people it reached before the switch existed.
final class NotificationPreferences {
  /// Creates a set of switches.
  const NotificationPreferences({required this.predictionReminder});

  /// What a user who never changed anything has.
  static const NotificationPreferences defaults = NotificationPreferences(
    predictionReminder: true,
  );

  /// Whether the daily prediction reminder may reach this user.
  final bool predictionReminder;

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.predictionReminder == predictionReminder;

  @override
  int get hashCode => predictionReminder.hashCode;
}

/// Read/write port over `notification.notification_preferences` (0063).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Tier-3: a failure here is confined to
/// the preference routes and the reminder sweep, never the points path.
abstract interface class NotificationPreferenceRepository {
  /// [userId]'s switches, or [NotificationPreferences.defaults] when the
  /// user has no stored row.
  Future<Result<NotificationPreferences>> preferencesOf(UserId userId);

  /// Stores [preferences] as [userId]'s switches, creating the row on first
  /// change, and returns what was stored.
  Future<Result<NotificationPreferences>> save(
    UserId userId,
    NotificationPreferences preferences,
  );

  /// The ids (`UserId.value`) of every user who turned the prediction
  /// reminder off. Read once per reminder firing; users with no row are
  /// never in it.
  Future<Result<Set<String>>> predictionReminderOptOuts();
}
