import 'package:application/src/notification/ports/notification_queue.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: deliver the pushes deferred out of quiet hours whose
/// time has come (P3-2).
///
/// Called on a timer, not by a request, so it takes no principal. Each batch
/// is claimed before it is sent (see [NotificationQueue.claimDue]): delivery
/// is at most once, and a push whose send fails is not retried -- the next
/// morning's push is a new row, never a replay of this one.
///
/// A push for a user with no device left is claimed and dropped.
///
/// Returns the number of pushes handed to the sender successfully.
final class FlushNotificationQueue {
  /// Creates the use-case over its collaborators.
  const FlushNotificationQueue({
    required NotificationQueue queue,
    required PushSender sender,
  }) : _queue = queue,
       _sender = sender;

  final NotificationQueue _queue;
  final PushSender _sender;

  /// Rows claimed per statement.
  static const int batchSize = 200;

  /// Batches per sweep at most; the next tick picks up whatever is left.
  static const int maxBatches = 10;

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final DateTime utcNow = now.toUtc();
    var delivered = 0;
    for (var batch = 0; batch < maxBatches; batch++) {
      final claimed = await _queue.claimDue(now: utcNow, limit: batchSize);
      if (claimed is Err<List<QueuedPush>>) {
        return Result.err(claimed.error);
      }
      final pushes = (claimed as Ok<List<QueuedPush>>).value;
      for (final push in pushes) {
        if (push.tokens.isEmpty) {
          continue;
        }
        final sent = await _sender.send(
          tokens: push.tokens,
          title: push.title,
          body: push.body,
        );
        if (sent is Ok<List<String>>) {
          delivered++;
        }
      }
      if (pushes.length < batchSize) {
        break;
      }
    }
    return Result.ok(delivered);
  }
}
