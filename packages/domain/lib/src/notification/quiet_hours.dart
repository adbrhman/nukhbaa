/// The hours in which the server sends a user no push notification (P3-2).
///
/// **23:00 to 08:00 on the reader's own clock** (decided 2026-09-21), the
/// clock the app reports on every launch as `identity.users
/// .utc_offset_minutes`. A user who never reported one is read on Riyadh
/// time, the zone of the audience and of every other schedule in the
/// system.
///
/// The window is fixed, not a setting: one rule for everyone is one rule to
/// test, and a per-user window can come later as an additive column without
/// changing what this answers for users who never set one.
///
/// Pure: the caller passes the instant and the offset, nothing is read here.
final class QuietHours {
  const QuietHours._();

  /// Local minute of the day at which the quiet hours begin (23:00).
  static const int startMinute = 23 * 60;

  /// Local minute of the day at which they end (08:00), exclusive.
  static const int endMinute = 8 * 60;

  /// The offset used for a user who never reported one: Riyadh, UTC+3.
  static const int fallbackOffsetMinutes = 180;

  /// Whether [instant] falls inside the quiet hours of a reader whose clock
  /// is [utcOffsetMinutes] ahead of UTC (null: [fallbackOffsetMinutes]).
  static bool covers(DateTime instant, {int? utcOffsetMinutes}) {
    final DateTime local = instant.toUtc().add(
      Duration(minutes: utcOffsetMinutes ?? fallbackOffsetMinutes),
    );
    final int minute = local.hour * 60 + local.minute;
    return minute >= startMinute || minute < endMinute;
  }

  /// The next 08:00 on the clock of a reader whose offset is
  /// [utcOffsetMinutes] (null: [fallbackOffsetMinutes]), as a UTC instant:
  /// the moment the quiet hours that cover [instant] end, and the earliest a
  /// push held back from [instant] may go out.
  ///
  /// Before 08:00 local that is this morning; from 08:00 on it is tomorrow's,
  /// so the answer is always after [instant]. Outside the quiet hours nothing
  /// needs holding back, and callers check [covers] first.
  static DateTime endsAt(DateTime instant, {int? utcOffsetMinutes}) {
    final Duration offset = Duration(
      minutes: utcOffsetMinutes ?? fallbackOffsetMinutes,
    );
    final DateTime local = instant.toUtc().add(offset);
    final int minute = local.hour * 60 + local.minute;
    final int days = minute < endMinute ? 0 : 1;
    return DateTime.utc(
      local.year,
      local.month,
      local.day + days,
      endMinute ~/ 60,
      endMinute % 60,
    ).subtract(offset);
  }
}
