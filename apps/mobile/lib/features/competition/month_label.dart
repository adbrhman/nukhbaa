/// كيف يُسمّى الشهر وإلى أي موسم رياضي ينتمي — في موضع واحد.
///
/// التسمية المخزّنة في قاعدة البيانات هي `MM/YYYY`، لكن التطبيق يسمّي
/// الشهر "شهر 9". كانت هذه الترجمة داخل منتقي الشهر وحده، فظهر السجل
/// بالتسمية الخام. الترجمة هنا كي لا تتباعد الشاشتان مرة أخرى.
library;

/// Renders a stored `MM/YYYY` season label as the app names that month:
/// `09/2026` becomes `شهر 9`.
///
/// A label that is not in that shape is returned untouched. Only the
/// monthly contest uses `MM/YYYY`; a league edition (`2026/27`) must keep
/// reading as itself rather than being mangled into a month it is not.
String monthLabelFromStored(String stored) {
  final List<String> parts = stored.split('/');
  if (parts.length != 2) return stored;
  final int? month = int.tryParse(parts.first);
  final int? year = int.tryParse(parts.last);
  if (month == null || year == null || month < 1 || month > 12) {
    return stored;
  }
  return 'شهر $month';
}

/// The sporting season (`2026/27`) that owns the month starting at [start].
///
/// The same rule the database applies in `competition.cycle_label_for`
/// (migration 0037) and that migration 0035 backfilled `cycle_label`
/// with: months 8-12 open a cycle, months 1-7 close the one that began
/// the previous August.
///
/// Computed here rather than read from the server because the record
/// payload already carries `start_at`. Sending `cycle_label` too would
/// mean a second source for one fact, and two sources drift.
String cycleLabelFromStart(DateTime start) {
  final DateTime utc = start.toUtc();
  final int opensIn = utc.month >= 8 ? utc.year : utc.year - 1;
  final String closesIn = ((opensIn + 1) % 100).toString().padLeft(2, '0');
  return '$opensIn/$closesIn';
}
