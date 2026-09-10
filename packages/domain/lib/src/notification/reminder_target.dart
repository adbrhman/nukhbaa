import 'package:domain/src/identity/user_id.dart';

/// One user who is due the prediction reminder, with every device registered
/// to them.
///
/// A user with several handsets is ONE target with several tokens: the
/// "already reminded" ledger is per user per day, not per device, so a person
/// is reminded once however many phones they carry.
final class ReminderTarget {
  /// Creates a target.
  const ReminderTarget({required this.userId, required this.tokens});

  /// The user to remind.
  final UserId userId;

  /// Their registered FCM tokens. Never empty -- a user with no device is not
  /// a target at all.
  final List<String> tokens;
}
