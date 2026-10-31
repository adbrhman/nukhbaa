/// Every group of a head-to-head month read together, for the months with
/// seat swaps (NK183, migration 0189).
library;

import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Whether [sheet] holds a seat that changed hands this month: a member who
/// came in after round 1 or left before the end.
bool h2hSheetHasSwaps(H2hGroupSheet sheet) => sheet.members.any(
  (member) => member.fromRound > 1 || member.untilRound != null,
);

/// The members of [sheet] who hold their seat in round [round].
List<H2hMember> h2hMembersIn(H2hGroupSheet sheet, int round) => [
  for (final member in sheet.members)
    if (member.activeIn(round)) member,
];

/// The members of [sheet] who hold their seat now (no swap took it).
List<H2hMember> h2hCurrentMembers(H2hGroupSheet sheet) => [
  for (final member in sheet.members)
    if (member.current) member,
];

/// Every group of a month with its sheet.
///
/// A seat swap moves a player to another group, and he keeps his own month
/// (the owner's decision of 2026-10-31): his league points, prediction
/// points and exact scorelines are the sum of what he did in every group he
/// played in. A round is played in the group where the player held a seat
/// in it ([H2hLeaguePolicy.table] with the members' rounds), so each match
/// is counted once; this book adds the parts up per player
/// ([H2hLeaguePolicy.mergeStandings]) and ranks a group by the players who
/// hold its seats now.
///
/// Without a swap a player's month is his one group's table, and the
/// readers keep reading one sheet; this book is loaded only when the
/// group read has a swap ([h2hSheetHasSwaps]).
final class H2hMonthBook {
  H2hMonthBook._(this.groups, this.sheets);

  /// The groups of the month.
  final List<H2hGroupRef> groups;

  /// Each group's sheet, keyed by group.
  final Map<H2hLeagueId, H2hGroupSheet> sheets;

  /// A book of sheets already read, one per group of [groups].
  factory H2hMonthBook.of({
    required List<H2hGroupRef> groups,
    required Map<H2hLeagueId, H2hGroupSheet> sheets,
  }) => H2hMonthBook._(
    List<H2hGroupRef>.unmodifiable(groups),
    Map<H2hLeagueId, H2hGroupSheet>.unmodifiable(sheets),
  );

  /// Reads every group of [monthStart] over [rounds]. [known] is a sheet
  /// already read, reused for its group.
  static Future<Result<H2hMonthBook>> load({
    required H2hLeagueStore leagues,
    required H2hSheetReader reader,
    required DateTime monthStart,
    required List<H2hRound> rounds,
    Map<H2hLeagueId, H2hGroupSheet> known = const {},
  }) async {
    final groupsResult = await leagues.groupsOf(monthStart);
    if (groupsResult is Err<List<H2hGroupRef>>) {
      return Result.err(groupsResult.error);
    }
    final groups = (groupsResult as Ok<List<H2hGroupRef>>).value;
    final sheets = <H2hLeagueId, H2hGroupSheet>{};
    for (final group in groups) {
      final have = known[group.leagueId];
      if (have != null) {
        sheets[group.leagueId] = have;
        continue;
      }
      final sheetResult = await reader.sheetOf(
        leagueId: group.leagueId,
        rounds: rounds,
      );
      if (sheetResult is Err<H2hGroupSheet>) {
        return Result.err(sheetResult.error);
      }
      sheets[group.leagueId] = (sheetResult as Ok<H2hGroupSheet>).value;
    }
    return Result.ok(H2hMonthBook._(groups, sheets));
  }

  /// Every player's month over [rounds], put together from every group he
  /// held a seat in, read at the seat he holds now (else his last one).
  Map<UserId, H2hStanding> standings(List<H2hRoundRef> rounds) {
    final parts = <UserId, List<H2hStanding>>{};
    final seatOf = <UserId, H2hMember>{};
    for (final group in groups) {
      final sheet = sheets[group.leagueId];
      if (sheet == null) {
        continue;
      }
      for (final standing in H2hLeaguePolicy.table(
        capacity: group.capacity,
        members: sheet.members,
        rounds: rounds,
        scores: sheet.scores,
        turns: sheet.turns,
      )) {
        (parts[standing.userId] ??= <H2hStanding>[]).add(standing);
      }
      for (final member in sheet.members) {
        final seen = seatOf[member.userId];
        if (seen == null ||
            (member.current && !seen.current) ||
            (member.current == seen.current &&
                member.fromRound > seen.fromRound)) {
          seatOf[member.userId] = member;
        }
      }
    }
    return {
      for (final entry in parts.entries)
        entry.key: H2hLeaguePolicy.mergeStandings(
          parts: entry.value,
          seat: seatOf[entry.key]!,
        ),
    };
  }

  /// The table of [leagueId] over [rounds]: the players who hold its seats
  /// now, each with his whole month, best first.
  List<H2hPlacing> placingsOf(
    H2hLeagueId leagueId,
    List<H2hRoundRef> rounds, {
    Map<UserId, H2hStanding>? merged,
  }) {
    final sheet = sheets[leagueId];
    if (sheet == null) {
      return const <H2hPlacing>[];
    }
    final all = merged ?? standings(rounds);
    return H2hLeaguePolicy.order([
      for (final member in h2hCurrentMembers(sheet))
        if (all[member.userId] != null) all[member.userId]!,
    ]);
  }
}
