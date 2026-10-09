import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the months, groups and seats of the head-to-head league
/// (migration 0100).
///
/// Backed by `PostgresH2hLeagueStore`. It stores and finds; it decides
/// nothing. Who is drawn where, who meets whom and who moves at the end of
/// the month are `H2hLeaguePolicy`, in Dart.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hLeagueStore {
  /// The month opened by [monthStart] if it was drawn, else null.
  ///
  /// [monthStart] is the first day of a month as a UTC midnight.
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart);

  /// Whether the month opened by [monthStart] was judged.
  Future<Result<bool>> isClosed(DateTime monthStart);

  /// Writes the month's draw: every group with its seats, and the month
  /// row, in one transaction. Returns the number of seats written, or 0
  /// when the month was already drawn (nothing is written then).
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  });

  /// The seat [userId] holds in the month opened by [monthStart], or null.
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  });

  /// Every group of the month opened by [monthStart].
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart);

  /// The first day of the OLDEST drawn month that was not judged yet, or
  /// null. Says nothing about whether that month has ended.
  Future<Result<DateTime?>> nextUnclosedMonth();

  /// Records that the month opened by [monthStart] was judged. Insert-only
  /// and idempotent.
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  });
}

/// A drawn month.
final class H2hMonthInfo {
  /// Creates a month.
  const H2hMonthInfo({
    required this.monthStart,
    required this.isPilot,
    required this.seatedCount,
  });

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// Whether the month is the hidden trial whose results decide nothing.
  final bool isPilot;

  /// Seats handed out by the draw.
  final int seatedCount;
}

/// A group the draw opens, with the id it is stored under.
final class H2hDrawnGroup {
  /// Creates a drawn group.
  const H2hDrawnGroup({required this.leagueId, required this.group});

  /// The new group's id.
  final H2hLeagueId leagueId;

  /// The group as `H2hLeaguePolicy.draw` made it.
  final H2hDrawGroup group;
}

/// One group of a month, as the jobs need to see it.
final class H2hGroupRef {
  /// Creates a group reference.
  const H2hGroupRef({
    required this.leagueId,
    required this.division,
    required this.groupIndex,
    required this.capacity,
  });

  /// The group.
  final H2hLeagueId leagueId;

  /// The division the group plays in.
  final H2hDivision division;

  /// 0-based position among the groups of its division.
  final int groupIndex;

  /// Seats of the group's round-robin.
  final int capacity;
}

/// A player's seat in one month.
final class H2hSeat {
  /// Creates a seat.
  const H2hSeat({
    required this.leagueId,
    required this.monthStart,
    required this.division,
    required this.groupIndex,
    required this.slot,
    required this.capacity,
    required this.divisionGroups,
    required this.isPilot,
    required this.joinedAt,
  });

  /// The group the seat belongs to.
  final H2hLeagueId leagueId;

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// The division the group plays in.
  final H2hDivision division;

  /// 0-based position of the group among the groups of its division.
  final int groupIndex;

  /// The player's slot in the group's round-robin.
  final int slot;

  /// Seats of the group's round-robin.
  final int capacity;

  /// How many groups the division has this month.
  final int divisionGroups;

  /// Whether the month is the hidden trial.
  final bool isPilot;

  /// When the seat was taken.
  final DateTime joinedAt;
}
