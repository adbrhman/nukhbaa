import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the new players of the head-to-head league and its waiting
/// group (NK277, migration 0213; December 2026 on).
///
/// Backed by `PostgresH2hNewcomerStore`. It stores and finds; who joins,
/// where and from which round is `SeatH2hNewcomers`. The database refuses
/// a seat taken twice, a player in two groups, a group started before it
/// holds twenty players or from a round that has started, and two waiting
/// groups open at once: every such refusal is the invariant
/// `h2h.newcomer_refused`, and a freeze by the owner
/// (`supabase/queries/h2h_newcomers_freeze.sql`) is `h2h.newcomers_frozen`.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hNewcomerStore {
  /// The players who should join the month opened by [monthStart] now,
  /// first prediction first: a prediction made since the month was drawn,
  /// on a real match, no seat in the month, and an account neither
  /// suspended nor hidden.
  Future<Result<List<UserId>>> newcomersOf(DateTime monthStart);

  /// The month's waiting group that has not started, or null.
  Future<Result<H2hWaitingGroup?>> waitingGroupOf(DateTime monthStart);

  /// The group index the month's next extra group takes.
  Future<Result<int>> nextExtraIndexOf(DateTime monthStart);

  /// Opens the waiting group [leagueId] at [groupIndex] of the extra
  /// division, twenty seats, with its secret order of the turns, in one
  /// transaction.
  Future<Result<void>> openWaitingGroup({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required int groupIndex,
  });

  /// Seats [userId] at [slot] of the waiting group [leagueId], with the
  /// record that he joined as a new player; with [startFrom], the group
  /// starts from that round in the same transaction.
  Future<Result<void>> seat({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required UserId userId,
    required int slot,
    int? startFrom,
  });
}

/// The month's waiting group, as the seating needs to see it.
final class H2hWaitingGroup {
  /// Creates a waiting group.
  const H2hWaitingGroup({
    required this.leagueId,
    required this.groupIndex,
    required this.seated,
    this.freeSlot,
  });

  /// The group.
  final H2hLeagueId leagueId;

  /// Its index in the extra division.
  final int groupIndex;

  /// Players who hold its seats now.
  final int seated;

  /// NK278: the lowest seat nobody holds now (a filler who left frees his
  /// seat), or null when read without it.
  final int? freeSlot;

  /// The seat the next player takes: [freeSlot], else the one after the
  /// seats taken (0213, where no seat was ever freed).
  int get nextSlot => freeSlot ?? seated;
}
