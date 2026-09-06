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

/// Date + time of day, e.g. `6 Sep 2026, 5:29 AM` in the viewer's zone.
String formatTimestamp(BuildContext context, String isoTimestamp) {
  final DateTime? parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final String locale = Localizations.localeOf(context).toString();
  return intl.DateFormat.yMMMd(locale).add_jm().format(parsed.toLocal());
}

/// Time of day only -- for lists where the date is already implied.
String formatTimeOfDay(BuildContext context, String isoTimestamp) {
  final DateTime? parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final String locale = Localizations.localeOf(context).toString();
  return intl.DateFormat.jm(locale).format(parsed.toLocal());
}
