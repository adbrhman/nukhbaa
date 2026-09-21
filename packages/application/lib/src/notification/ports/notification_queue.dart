import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One push taken off the deferred queue for delivery (P3-2, migration 0064).
final class QueuedPush {
  /// Creates a claimed push.
  const QueuedPush({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.tokens,
  });

  /// The queue row id.
  final String id;

  /// The user it is for.
  final UserId userId;

  /// The notification title, as queued.
  final String title;

  /// The notification body, as queued.
  final String body;

  /// The user's devices at delivery time. Empty when the user has none left:
  /// the push is then claimed and dropped.
  final List<String> tokens;
}

/// Port over `notification.notification_queue` (0064): pushes deferred out
/// of a user's quiet hours.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Tier-3: nothing on the points path
/// reads or writes it.
abstract interface class NotificationQueue {
  /// Claims up to [limit] waiting pushes whose delivery time is at or before
  /// [now], oldest first, and answers them with their users' current
  /// devices. Claiming marks them sent in the same statement, so a push is
  /// delivered at most once even if two sweeps overlap.
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  });
}
