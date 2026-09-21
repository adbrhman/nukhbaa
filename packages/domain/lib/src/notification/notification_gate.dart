import 'package:domain/src/notification/quiet_hours.dart';

/// The one rule every proactive push passes (plan P3-3): the daily
/// reminder, the pre-match push and, from batch 3, the streak saver and the
/// overtaken push.
///
/// A push goes out only when the reader has the type switched on, is not in
/// their quiet hours ([QuietHours]), and has had fewer than [weeklyBudget]
/// proactive pushes this Riyadh week (Monday to Sunday). Rewards (an exact
/// hit) and admin announcements are not proactive and never pass here.
///
/// Pure: the caller passes the instant, the switch, the clock and the count.
final class NotificationGate {
  const NotificationGate._();

  /// The most proactive pushes one user receives in one Riyadh week,
  /// every type together (decided 2026-09-22).
  static const int weeklyBudget = 5;

  /// The zone every day and week boundary here is read in: Riyadh, UTC+3.
  static const Duration riyadhOffset = Duration(hours: 3);

  /// Whether a proactive push may reach a reader now.
  static bool allows({
    required bool optedIn,
    required DateTime now,
    required int sentThisWeek,
    int? utcOffsetMinutes,
  }) =>
      optedIn &&
      !QuietHours.covers(now, utcOffsetMinutes: utcOffsetMinutes) &&
      sentThisWeek < weeklyBudget;

  /// The Riyadh calendar day of [now], as `YYYY-MM-DD`.
  static String riyadhDate(DateTime now) =>
      _format(now.toUtc().add(riyadhOffset));

  /// The Monday opening the Riyadh week of [now], as `YYYY-MM-DD`: the day
  /// the weekly budget counts from.
  static String weekStartDate(DateTime now) {
    final DateTime local = now.toUtc().add(riyadhOffset);
    final DateTime day = DateTime.utc(local.year, local.month, local.day);
    return _format(day.subtract(Duration(days: day.weekday - DateTime.monday)));
  }

  static String _format(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
