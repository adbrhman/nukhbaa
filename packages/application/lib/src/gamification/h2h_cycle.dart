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
/// Only the month before [day]'s is looked at, and only when it is a month
/// of the December rules (January 2027 on): its row, then its rounds, then
/// whether it is judged, each read only when the one before leaves the
/// answer open. A league is never more than one month late: the next
/// month's draw waits for it to be judged. Never throws.
Future<Result<DateTime>> h2hCycleOf({
  required H2hLeagueStore leagues,
  required H2hRoundStore rounds,
  required DateTime day,
}) async {
  final own = H2hLeaguePolicy.monthStartOf(day);
  final previous = H2hLeaguePolicy.previousMonthOf(own);
  if (!H2hLeaguePolicy.usesDecemberRules(previous)) {
    return Result.ok(own);
  }
  final infoResult = await leagues.monthOf(previous);
  if (infoResult is Err<H2hMonthInfo?>) {
    return Result.err(infoResult.error);
  }
  final info = (infoResult as Ok<H2hMonthInfo?>).value;
  if (info == null || info.isPilot) {
    return Result.ok(own);
  }
  final listResult = await rounds.roundsOf(previous);
  if (listResult is Err<List<H2hRound>>) {
    return Result.err(listResult.error);
  }
  final count = (listResult as Ok<List<H2hRound>>).value.length;
  if (count >= H2hLeaguePolicy.maxRounds) {
    return Result.ok(own);
  }
  final closedResult = await leagues.isClosed(previous);
  if (closedResult is Err<bool>) {
    return Result.err(closedResult.error);
  }
  return Result.ok(
    H2hLeaguePolicy.cycleOf(
      day: day,
      previousDrawn: true,
      previousRounds: count,
      previousJudged: (closedResult as Ok<bool>).value,
    ),
  );
}
