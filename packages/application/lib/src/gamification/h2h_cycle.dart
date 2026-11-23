/// The league a day belongs to (NK279, decided by the owner on 2026-11-14).
library;

import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The month whose league the Riyadh [day] belongs to.
///
/// From December 2026 a league that has not played its 19 rounds by its
/// month's end goes on into the next month (`H2hLeaguePolicy.cycleOf`):
/// the days after the end are its own until its 19th round, and the jobs
/// and reads that look at "this month" look at it instead, so no round is
/// dropped at the month's end. The month's champion, by the calendar, is
/// not affected.
///
/// The months before [day]'s are looked at from the nearest one back, down
/// to December 2026 and no further (only a month of the December rules can
/// run past its end). A month that was never drawn is passed over: while a
/// league is late the months behind it are not drawn, and it may be more
/// than one month late, so a day of February can still be December's
/// (NK303). The first drawn month decides, reading its row, then its
/// rounds, then whether it is judged, each only when the one before leaves
/// the answer open: a pilot, a month with its 19 rounds and a judged month
/// leave the day to its own month. Never throws.
Future<Result<DateTime>> h2hCycleOf({
  required H2hLeagueStore leagues,
  required H2hRoundStore rounds,
  required DateTime day,
}) async {
  final own = H2hLeaguePolicy.monthStartOf(day);
  var month = H2hLeaguePolicy.previousMonthOf(own);
  while (H2hLeaguePolicy.usesDecemberRules(month)) {
    final infoResult = await leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    final info = (infoResult as Ok<H2hMonthInfo?>).value;
    if (info == null) {
      // NK303: never drawn; the month before it may still be the league.
      month = H2hLeaguePolicy.previousMonthOf(month);
      continue;
    }
    if (info.isPilot) {
      return Result.ok(own);
    }
    final listResult = await rounds.roundsOf(month);
    if (listResult is Err<List<H2hRound>>) {
      return Result.err(listResult.error);
    }
    final count = (listResult as Ok<List<H2hRound>>).value.length;
    if (!H2hLeaguePolicy.runsPastMonthEnd(monthStart: month, rounds: count)) {
      return Result.ok(own);
    }
    final closedResult = await leagues.isClosed(month);
    if (closedResult is Err<bool>) {
      return Result.err(closedResult.error);
    }
    return Result.ok((closedResult as Ok<bool>).value ? own : month);
  }
  return Result.ok(own);
}
