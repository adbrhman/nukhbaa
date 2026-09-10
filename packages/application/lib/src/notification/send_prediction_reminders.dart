import 'package:application/src/notification/ports/prediction_reminder_repository.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: remind everyone who has not predicted yet, three hours
/// before the first kickoff of the day.
///
/// It is called on a timer, not by a request, so it takes no principal: there
/// is no caller to authorise. Every decision is made from the clock and the
/// database.
///
/// **The day** is the calendar day at [zoneOffset] (UTC+3, the audience's
/// zone), not UTC -- a 01:00 UTC kickoff belongs to the day the reader lives
/// in, not the one the server does.
///
/// **Firing window:** the sweep does nothing unless the first kickoff is
/// [leadTime] away, give or take [tolerance]. The scheduler ticks more often
/// than the window is wide, so [PredictionReminderRepository.markSent] -- not
/// the timing -- is what prevents a second notification.
///
/// Returns the number of users notified (`0` is the common, healthy answer).
final class SendPredictionReminders {
  /// Creates the use-case over its collaborators.
  const SendPredictionReminders({
    required PredictionReminderRepository reminders,
    required PushSender sender,
  }) : _reminders = reminders,
       _sender = sender;

  final PredictionReminderRepository _reminders;
  final PushSender _sender;

  /// The audience's zone. Fixed rather than per-user: the contest is one
  /// monthly table for one regional audience, and a per-user zone would need
  /// a column nobody fills.
  static const Duration zoneOffset = Duration(hours: 3);

  /// How far ahead of the first kickoff the reminder goes out.
  static const Duration leadTime = Duration(hours: 3);

  /// How far either side of [leadTime] still counts as "now".
  static const Duration tolerance = Duration(minutes: 20);

  /// The notification title.
  static const String title = 'نُخبة';

  /// The notification body.
  static const String body = 'لم تسجّل توقعاتك بعد — أول مباراة بعد ٣ ساعات';

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final utcNow = now.toUtc();
    final local = utcNow.add(zoneOffset);
    final windowStart = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(zoneOffset);
    final windowEnd = windowStart.add(const Duration(days: 1));
    final reminderDate =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';

    final kickoffResult = await _reminders.firstKickoffInWindow(
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
    if (kickoffResult is Err<DateTime?>) {
      return Result.err(kickoffResult.error);
    }
    final kickoff = (kickoffResult as Ok<DateTime?>).value;
    if (kickoff == null) {
      return const Result.ok(0);
    }

    // A day with no fixtures, a day whose first match already started, and a
    // day still hours away all land here.
    final lead = kickoff.difference(utcNow);
    if (lead > leadTime + tolerance || lead < leadTime - tolerance) {
      return const Result.ok(0);
    }

    final targetsResult = await _reminders.pendingTargets(
      windowStart: windowStart,
      windowEnd: windowEnd,
      reminderDate: reminderDate,
    );
    if (targetsResult is Err<List<ReminderTarget>>) {
      return Result.err(targetsResult.error);
    }
    final targets = (targetsResult as Ok<List<ReminderTarget>>).value;
    if (targets.isEmpty) {
      return const Result.ok(0);
    }

    final tokens = <String>[for (final target in targets) ...target.tokens];
    final sendResult = await _sender.send(
      tokens: tokens,
      title: title,
      body: body,
    );
    if (sendResult is Err<List<String>>) {
      return Result.err(sendResult.error);
    }

    // Mark first, retire second: the ledger is what stops a repeat, and a
    // failure while cleaning up dead tokens must not cause one.
    final marked = await _reminders.markSent(
      userIds: [for (final target in targets) target.userId],
      reminderDate: reminderDate,
      now: utcNow,
    );
    if (marked is Err<void>) {
      return Result.err(marked.error);
    }

    final dead = (sendResult as Ok<List<String>>).value;
    if (dead.isNotEmpty) {
      await _reminders.forgetTokens(dead);
    }

    return Result.ok(targets.length);
  }
}
