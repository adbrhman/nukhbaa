import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_my_streak.dart';
import 'package:application/src/gamification/ports/streak_repository.dart';
import 'package:application/src/notification/ports/push_budget_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/notification/ports/streak_saver_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: warn a player whose run is about to break (plan
/// P3-4b, the "streak saver").
///
/// A day is complete once every fixture of it is predicted, and a fixture
/// locks at kickoff, so a day is lost the moment its first unpredicted
/// fixture kicks off. The saver fires when that kickoff is [leadMin] to
/// [leadMax] away, for a player carrying a run of at least [minRun] match
/// days -- counted exactly as `GET /me/streak` counts it, today still open.
///
/// Every push passes [NotificationGate] (the `streak_saver` switch, the
/// quiet hours, the shared weekly budget), at most one per player per
/// Riyadh day, recorded in `proactive_sends` right after it is sent.
///
/// Returns the number of pushes sent.
final class SendStreakSavers {
  /// Creates the use-case over its collaborators.
  const SendStreakSavers({
    required StreakSaverRepository savers,
    required StreakRepository streaks,
    required PushBudgetReader budget,
    required PushSender sender,
  }) : _savers = savers,
       _streaks = streaks,
       _budget = budget,
       _sender = sender;

  final StreakSaverRepository _savers;
  final StreakRepository _streaks;
  final PushBudgetReader _budget;
  final PushSender _sender;

  /// The nearest kickoff still warned about.
  static const Duration leadMin = Duration(minutes: 45);

  /// The furthest kickoff already warned about.
  static const Duration leadMax = Duration(minutes: 75);

  /// The shortest run worth a warning.
  static const int minRun = 2;

  /// The notification title.
  static const String title = 'نُخبة';

  /// The notification body for a run of [days].
  static String bodyFor(int days) =>
      'سلسلتك $days أيام في خطر، توقّع مباريات اليوم قبل أن تبدأ';

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final DateTime utcNow = now.toUtc();
    final String today = NotificationGate.riyadhDate(utcNow);
    final dueResult = await _savers.dueTargets(
      today: today,
      from: utcNow.add(leadMin),
      to: utcNow.add(leadMax),
    );
    if (dueResult is Err<List<StreakSaverTarget>>) {
      return Result.err(dueResult.error);
    }
    final due = (dueResult as Ok<List<StreakSaverTarget>>).value;
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

    final DateTime todayDay = riyadhDayOf(utcNow);
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
      final runResult = await _currentRun(target.userId, todayDay);
      if (runResult is Err<int>) {
        return Result.err(runResult.error);
      }
      final int run = (runResult as Ok<int>).value;
      if (run < minRun) {
        continue;
      }
      final result = await _sender.send(
        tokens: target.tokens,
        title: title,
        body: bodyFor(run),
        link: PushLink.fixtures,
      );
      if (result is! Ok<List<String>>) {
        continue;
      }
      dead.addAll(result.value);
      sent[target.userId.value] = used + 1;
      delivered++;
      final marked = await _savers.markSent(
        target: target,
        sendDate: today,
        now: utcNow,
      );
      if (marked is Err<void>) {
        return Result.err(marked.error);
      }
    }

    if (dead.isNotEmpty) {
      await _savers.forgetTokens(dead);
    }
    return Result.ok(delivered);
  }

  /// The run [userId] carries into [today], today still open: the same
  /// count `GetMyStreak` answers.
  Future<Result<int>> _currentRun(UserId userId, DateTime today) async {
    final calendarResult = await _streaks.completionCalendar(
      userId: userId,
      upToDay: today,
      limitDays: GetMyStreak.windowDays,
    );
    if (calendarResult is Err<List<MatchDayCompletion>>) {
      return Result.err(calendarResult.error);
    }
    final calendar = (calendarResult as Ok<List<MatchDayCompletion>>).value;
    if (calendar.isEmpty) {
      return const Result.ok(0);
    }
    final newest = calendar.first;
    final pendingToday =
        newest.day.isAtSameMomentAs(today) && !newest.completed;
    return Result.ok(
      StreakTally.fromMatchDays(<bool>[
        for (final entry in calendar) entry.completed,
      ], newestIsPendingToday: pendingToday).current,
    );
  }
}
