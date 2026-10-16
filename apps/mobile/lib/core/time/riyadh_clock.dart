/// Wall-clock time in Riyadh, the app's time everywhere (UTC+3, no daylight
/// saving): the admin enters a kickoff as Riyadh announces it, whatever
/// zone his phone is set to (audit L-12: the form read the phone's zone, so
/// a phone on the wrong zone saved the wrong kickoff, and the lock with it).
library;

/// Riyadh time.
abstract final class RiyadhClock {
  /// Riyadh's offset from UTC.
  static const Duration offset = Duration(hours: 3);

  /// The Riyadh wall time of [instant]: a UTC [DateTime] whose fields read
  /// as the clock in Riyadh.
  static DateTime wallOf(DateTime instant) => instant.toUtc().add(offset);

  /// The instant (UTC) a Riyadh wall time names.
  static DateTime instantOf(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) => DateTime.utc(year, month, day, hour, minute).subtract(offset);

  /// `2026-10-20 21:00`, read on Riyadh's clock.
  static String stamp(DateTime instant) => _stamp(wallOf(instant));

  /// The same instant on this phone's clock when its zone is not Riyadh's
  /// (`على جهازك: 2026-10-20 19:00`), else null.
  static String? deviceLabel(DateTime instant) {
    final DateTime local = instant.toLocal();
    if (local.timeZoneOffset == offset) return null;
    return 'على جهازك: ${_stamp(local)}';
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
