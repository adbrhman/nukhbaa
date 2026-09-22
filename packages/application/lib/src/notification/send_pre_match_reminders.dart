import 'package:application/src/notification/ports/pre_match_reminder_repository.dart';
import 'package:application/src/notification/ports/push_budget_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: push the followers of a team whose match starts soon
/// and who have not predicted it (plan P3-4a).
///
/// **The window:** a fixture kicking off between [leadMin] and [leadMax] from
/// now. The scheduler ticks more often than the window is wide, so every
/// fixture is seen at least once; `proactive_sends` (0066), not the timing,
/// is what keeps a second push away.
///
/// **The gate:** every target passes [NotificationGate] -- the `pre_match`
/// switch, the quiet hours on their own clock, and the weekly budget shared
/// with the daily reminder. Two followed teams in the window count as two
/// pushes against that budget, counted as they go.
///
/// Each push is recorded right after it is sent. If recording fails the
/// sweep stops and answers the error, so nothing more goes out unrecorded.
///
/// Returns the number of pushes sent.
final class SendPreMatchReminders {
  /// Creates the use-case over its collaborators.
  const SendPreMatchReminders({
    required PreMatchReminderRepository reminders,
    required PushBudgetReader budget,
    required PushSender sender,
  }) : _reminders = reminders,
       _budget = budget,
       _sender = sender;

  final PreMatchReminderRepository _reminders;
  final PushBudgetReader _budget;
  final PushSender _sender;

  /// The nearest kickoff still announced.
  static const Duration leadMin = Duration(minutes: 90);

  /// The furthest kickoff already announced.
  static const Duration leadMax = Duration(minutes: 120);

  /// The notification title.
  static const String title = 'نُخبة';

  /// The notification body for a [home] against [away] fixture.
  static String bodyFor(String home, String away) =>
      '$home × $away تبدأ قريباً، سجّل توقعك قبل صافرة البداية';

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final DateTime utcNow = now.toUtc();
    final dueResult = await _reminders.dueTargets(
      from: utcNow.add(leadMin),
      to: utcNow.add(leadMax),
    );
    if (dueResult is Err<List<PreMatchTarget>>) {
      return Result.err(dueResult.error);
    }
    final due = (dueResult as Ok<List<PreMatchTarget>>).value;
    if (due.isEmpty) {
      return const Result.ok(0);
    }

    final countsResult = await _budget.sentCountsSince(
      userIds: <UserId>{for (final target in due) target.userId}.toList(),
      fromDate: NotificationGate.weekStartDate(utcNow),
    );
    if (countsResult is Err<Map<String, int>>) {
      return Result.err(countsResult.error);
    }
    final sent = Map<String, int>.of(
      (countsResult as Ok<Map<String, int>>).value,
    );

    final String sendDate = NotificationGate.riyadhDate(utcNow);
    final dead = <String>[];
    var delivered = 0;
    for (final target in due) {
      final int used = sent[target.userId.value] ?? 0;
      if (!NotificationGate.allows(
        optedIn: target.optedIn,
        now: utcNow,
        sentThisWeek: used,
        utcOffsetMinutes: target.utcOffsetMinutes,
      )) {
        continue;
      }
      final result = await _sender.send(
        tokens: target.tokens,
        title: title,
        body: bodyFor(target.homeTeam, target.awayTeam),
        link: PushLink.fixtures,
      );
      if (result is! Ok<List<String>>) {
        continue;
      }
      dead.addAll(result.value);
      sent[target.userId.value] = used + 1;
      delivered++;
      final marked = await _reminders.markSent(
        target: target,
        sendDate: sendDate,
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
