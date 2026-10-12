import 'package:application/src/notification/ports/incomplete_day_reminder_repository.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: tell a player who predicted part of today's matches
/// how many are still open (batch 117, decided with the owner 2026-10-12).
///
/// The daily reminder (`SendPredictionReminders`) reaches only a player who
/// predicted none of the day's matches. A player who predicted some and
/// forgot the rest gets this push instead, once a day, [leadMin] to
/// [leadMax] before the first match they left open -- so after the daily
/// reminder, never with it, and before the streak saver's hour.
///
/// It passes the player's `prediction_reminder` switch and their quiet
/// hours ([QuietHours]), but NOT the weekly budget of [NotificationGate]:
/// the owner decided this push stays outside it, and it is recorded in its
/// own table (0106), which the budget does not count.
///
/// Returns the number of pushes sent.
final class SendIncompleteDayReminders {
  /// Creates the use-case over its collaborators.
  const SendIncompleteDayReminders({
    required IncompleteDayReminderRepository reminders,
    required PushSender sender,
  }) : _reminders = reminders,
       _sender = sender;

  final IncompleteDayReminderRepository _reminders;
  final PushSender _sender;

  /// The nearest first open match still warned about.
  static const Duration leadMin = Duration(minutes: 75);

  /// The furthest first open match already warned about: an hour and a
  /// half, give or take a quarter, for a sweep that wakes every ten
  /// minutes.
  static const Duration leadMax = Duration(minutes: 105);

  /// The notification title.
  static const String title = 'نُخبة';

  /// The notification body for [remaining] open matches, the count in the
  /// grammatical form Arabic gives it.
  static String bodyFor(int remaining) {
    final String count = switch (remaining) {
      1 => 'مباراة واحدة لم تتوقعها',
      2 => 'مباراتان لم تتوقعهما',
      >= 3 && <= 10 => '$remaining مباريات لم تتوقعها',
      _ => '$remaining مباراة لم تتوقعها',
    };
    return 'تبقى لديك $count اليوم، أكمل توقعاتك قبل أن تبدأ';
  }

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final DateTime utcNow = now.toUtc();
    final String today = NotificationGate.riyadhDate(utcNow);
    final dueResult = await _reminders.dueTargets(
      today: today,
      now: utcNow,
      from: utcNow.add(leadMin),
      to: utcNow.add(leadMax),
    );
    if (dueResult is Err<List<IncompleteDayTarget>>) {
      return Result.err(dueResult.error);
    }
    final due = (dueResult as Ok<List<IncompleteDayTarget>>).value;

    final dead = <String>[];
    var delivered = 0;
    for (final target in due) {
      if (!target.optedIn ||
          target.remaining < 1 ||
          QuietHours.covers(
            utcNow,
            utcOffsetMinutes: target.utcOffsetMinutes,
          )) {
        continue;
      }
      final result = await _sender.send(
        tokens: target.tokens,
        title: title,
        body: bodyFor(target.remaining),
        link: PushLink.fixtures,
      );
      if (result is! Ok<List<String>>) {
        continue;
      }
      dead.addAll(result.value);
      delivered++;
      // Recorded right after the send: the key of 0106 is what keeps it to
      // one a day, whatever the next tick finds.
      final marked = await _reminders.markSent(
        userId: target.userId,
        sendDate: today,
        now: utcNow,
      );
      if (marked is Err<void>) {
        return Result.err(marked.error);
      }
    }

    if (dead.isNotEmpty) {
      await _reminders.forgetTokens(dead);
    }
    return Result.ok(delivered);
  }
}
