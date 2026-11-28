// NK309_01
/// Which Elite Cup a signed-in player reads, and where he stands in it.
///
/// Shared by every reading of the cup (`GetMyH2hCup` and the cup board), so
/// that all of them show the same month. The cup of the current Riyadh month
/// is read first, then the month before it: the cup of a month opens after
/// its 19 rounds, and may still be on in the next month. A cup whose three
/// titles were decided more than [H2hCupMonthPicker.lingerDays] days ago is
/// not shown any more. A player who is in a cup reads his own before he
/// watches another.
library;

import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The cup chosen for one player.
final class H2hCupMonthPick {
  /// Creates the choice.
  const H2hCupMonthPick({
    required this.month,
    required this.state,
    required this.place,
    required this.groupNumber,
    required this.watching,
  });

  /// The month whose cup it is (a UTC first of the month).
  final DateTime month;

  /// The cup as stored: every path, stage, pair and title of the month.
  final H2hCupState state;

  /// The player's path: 1, 2 or 3; the first places' path for a watcher.
  final int place;

  /// The player's elite group, or 0 for a watcher.
  final int groupNumber;

  /// Whether the player is outside the cup and only watches it.
  final bool watching;
}

/// Chooses the cup a player reads. Reads only; decides and writes nothing.
abstract final class H2hCupMonthPicker {
  /// Days a finished cup stays on a player's screen.
  static const int lingerDays = 3;

  /// The path a player outside the cup may watch: the first places, the
  /// group leaders.
  static const int spectatorPlace = 1;

  /// The cup [user] reads on Riyadh day [today], or null when there is none.
  ///
  /// The cup he is in wins over one he could only watch; of two to watch,
  /// the current month's wins. A transient failure of [cups] is returned
  /// as it came.
  static Future<Result<H2hCupMonthPick?>> pick({
    required H2hCupStore cups,
    required DateTime today,
    required UserId user,
  }) async {
    final current = H2hLeaguePolicy.monthStartOf(today);
    final months = <DateTime>[
      current,
      DateTime.utc(current.year, current.month - 1),
    ];
    // The first open cup of the first places, kept for a player who is in
    // none of them: he may watch it, he does not play it.
    H2hCupMonthPick? watch;
    for (final month in months) {
      if (!H2hLeaguePolicy.usesEliteDraw(month)) {
        continue;
      }
      final read = await cups.stateOf(month);
      if (read is Err<H2hCupState>) {
        return Result.err(read.error);
      }
      final state = (read as Ok<H2hCupState>).value;
      // NK359_01c
      if (isOver(state, today, month: month)) {
        continue;
      }
      final mine = entryOf(state, user);
      if (mine == null) {
        if (watch == null && state.entriesOf(spectatorPlace).isNotEmpty) {
          watch = H2hCupMonthPick(
            month: month,
            state: state,
            place: spectatorPlace,
            groupNumber: 0,
            watching: true,
          );
        }
        continue;
      }
      return Result.ok(
        H2hCupMonthPick(
          month: month,
          state: state,
          place: mine.place,
          groupNumber: mine.groupNumber,
          watching: false,
        ),
      );
    }
    return Result.ok(watch);
  }

  /// The entry of [user] in [state], or null when he did not qualify.
  static H2hCupEntry? entryOf(H2hCupState state, UserId user) {
    for (final entry in state.entries) {
      if (entry.userId == user) {
        return entry;
      }
    }
    return null;
  }

  /// Whether the cup of [month] is finished and has been for more than
  /// [lingerDays]. It is finished with the titles of its own kind
  /// ([H2hCupPolicy.titleCountOf]): three paths, or the bracket's one.
  static bool isOver(
    H2hCupState state,
    DateTime today, {
    required DateTime month,
  }) {
    // NK359_01d
    if (state.titles.length < H2hCupPolicy.titleCountOf(month)) {
      return false;
    }
    DateTime? last;
    for (final stage in state.stages) {
      if (last == null || stage.day.isAfter(last)) {
        last = stage.day;
      }
    }
    return last == null || today.difference(last).inDays > lingerDays;
  }
}
