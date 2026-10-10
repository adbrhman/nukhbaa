import 'package:shared/shared.dart';

/// Read port for how a head-to-head month went (migrations 0100/0101): its
/// draw, its groups, and its closing.
///
/// Backed by `PostgresH2hMonthReportReader`. It counts; it decides nothing.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hMonthReportReader {
  /// The report of the month opened by [monthStart].
  Future<Result<H2hMonthReport>> reportOf(DateTime monthStart);
}

/// How a month went.
final class H2hMonthReport {
  /// Creates a report.
  const H2hMonthReport({
    required this.monthStart,
    required this.drawnAt,
    required this.isPilot,
    required this.drawnSeats,
    required this.seats,
    required this.groupsByDivision,
    required this.closedAt,
    required this.closedMembers,
    required this.outcomes,
  });

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// When the month was drawn, or null when it was not.
  final DateTime? drawnAt;

  /// Whether it is the pilot month.
  final bool isPilot;

  /// Players the draw seated.
  final int drawnSeats;

  /// Seats held now (the draw's plus any added late).
  final int seats;

  /// Groups per division level.
  final Map<int, int> groupsByDivision;

  /// When the month was judged, or null when it was not.
  final DateTime? closedAt;

  /// Members it judged.
  final int closedMembers;

  /// Members per outcome (`promoted`, `held`, `relegated`, `out`, ...).
  final Map<String, int> outcomes;
}
