/// Rendering helpers for the ISO-8601 timestamp strings the API returns.
///
/// Contracts carry timestamps as opaque `String`s (`submitted_at`,
/// `occurred_at`) so the transport stays lossless and the client never
/// re-interprets a server instant. That is right for the DTO and wrong for a
/// widget: printing the string as-is puts `2026-09-06T02:29:45.121328Z` on
/// screen. These helpers parse once, convert to the viewer's own time zone,
/// and format through `intl` with the active locale -- the same idiom
/// `fotmob_match_card.dart` already uses for kickoff times.
///
/// An unparseable value falls back to the original string: a malformed
/// timestamp should look odd, not blank out the row it belongs to.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

import '../time/riyadh_clock.dart';

// NK299_06 owner decision 2026-11-21 (script 299): every time in the app
// is Riyadh's, on the 24-hour clock, whatever the phone's zone.

/// Date + time of day on Riyadh's clock, e.g. `6 Sep 2026 08:29`.
String formatTimestamp(BuildContext context, String isoTimestamp) {
  final DateTime? parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final String locale = Localizations.localeOf(context).toString();
  return intl.DateFormat.yMMMd(
    locale,
  ).add_Hm().format(RiyadhClock.wallOf(parsed));
}

/// Time of day only (`21:30`), on Riyadh's clock -- for lists where the
/// date is already implied.
String formatTimeOfDay(BuildContext context, String isoTimestamp) {
  final DateTime? parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final String locale = Localizations.localeOf(context).toString();
  return intl.DateFormat.Hm(locale).format(RiyadhClock.wallOf(parsed));
}

/// Time of day of a kickoff (`00:30`), for a list already filed under the
/// kickoff's Riyadh day (the matches tab, the home highlights, the admin's
/// day). The time is Riyadh's too, so it always falls on that day and no
/// weekday is added (the viewer's weekday followed it until script 299).
String formatKickoffTime(BuildContext context, String isoTimestamp) =>
    formatTimeOfDay(context, isoTimestamp);

/// Day + time of day without the year, e.g. `10 Sep · 22:00` on Riyadh's
/// clock -- for cards inside the current month, where the year is implied.
String formatDayAndTime(BuildContext context, String isoTimestamp) {
  final DateTime? parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final String locale = Localizations.localeOf(context).toString();
  final DateTime wall = RiyadhClock.wallOf(parsed);
  final String day = intl.DateFormat.MMMd(locale).format(wall);
  final String time = intl.DateFormat.Hm(locale).format(wall);
  return '$day · $time';
}
