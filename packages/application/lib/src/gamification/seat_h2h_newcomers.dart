/// The scheduler's seating of new players (NK277, migration 0213).
library;

import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/h2h_cycle.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_newcomer_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one run of [SeatH2hNewcomers] did.
final class H2hNewcomersRun {
  /// Creates a report.
  const H2hNewcomersRun({this.seated = 0, this.opened = 0, this.started = 0});

  /// New players seated.
  final int seated;

  /// Waiting groups opened.
  final int opened;

  /// Waiting groups started (their twentieth player joined).
  final int started;
}

/// Use-case: seats the new players of the head-to-head month open now
/// (decided by the owner on 2026-11-14; December 2026 on).
///
/// * **Who.** A player with no seat in the month who made a prediction on
///   a real match since the month was drawn, his account neither suspended
///   nor hidden ([H2hNewcomerStore.newcomersOf]): he joins at his first
///   real prediction, not at registration. First prediction first.
/// * **Where.** The month's waiting group that has not started, at its
///   next seat; with none, a new extra group of twenty is opened as the
///   waiting group. A waiting group is not a competing group: it plays no
///   round, and no result or absence counts, until it starts.
/// * **Start.** The twentieth player starts the group in the same
///   transaction, from the first round of the month that has not started
///   ([H2hLeaguePolicy.countsForMovement] then says whether it takes part
///   in the month's promotion and relegation). The groups already playing
///   are never touched.
/// * **Back from absence (NK278, migration 0214).** A player who left his
///   seat in the last group for absence is on the waiting list with no
///   seat; his first real prediction after that seats him in the waiting
///   group like a new player, on its lowest free seat, a seat a filler left
///   included.
/// * **When not.** November 2026 and every earlier month (their rules stay
///   as they were), a month not drawn, a pilot, a month judged, and once
///   the month's last round has started: nobody joins a month that has no
///   round left; he joins the next month's waiting group at his next
///   prediction after its draw.
///
/// Never throws. A seat the database refuses (taken meanwhile by another
/// run, a round that started meanwhile) is skipped and tried again on the
/// next run; a freeze by the owner stops the run with
/// `h2h.newcomers_frozen`.
final class SeatH2hNewcomers {
  /// Creates the use-case over its collaborators.
  SeatH2hNewcomers({
    required H2hNewcomerStore newcomers,
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required IdGenerator idGenerator,
    bool enabled = true,
  }) : _newcomers = newcomers,
       _leagues = leagues,
       _rounds = rounds,
       _ids = idGenerator,
       _enabled = enabled;

  final H2hNewcomerStore _newcomers;
  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final IdGenerator _ids;

  /// False when the host turned it off (`NUKHBA_H2H_NEWCOMERS=off`): the
  /// run does nothing at all.
  final bool _enabled;

  /// Seats the month's new players as of [now].
  Future<Result<H2hNewcomersRun>> call({required DateTime now}) async {
    if (!_enabled) {
      return const Result.ok(H2hNewcomersRun());
    }
    // NK279: a league still playing past its month's end seats its new
    // players as before its end.
    final cycleResult = await h2hCycleOf(
      leagues: _leagues,
      rounds: _rounds,
      day: riyadhDayOf(now.toUtc()),
    );
    if (cycleResult is Err<DateTime>) {
      return Result.err(cycleResult.error);
    }
    final month = (cycleResult as Ok<DateTime>).value;
    if (!H2hLeaguePolicy.usesDecemberRules(month)) {
      return const Result.ok(H2hNewcomersRun());
    }
    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    final info = (infoResult as Ok<H2hMonthInfo?>).value;
    if (info == null || info.isPilot) {
      return const Result.ok(H2hNewcomersRun());
    }
    final closedResult = await _leagues.isClosed(month);
    if (closedResult is Err<bool>) {
      return Result.err(closedResult.error);
    }
    if ((closedResult as Ok<bool>).value) {
      return const Result.ok(H2hNewcomersRun());
    }

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    var lastStarted = 0;
    for (final round in (roundsResult as Ok<List<H2hRound>>).value) {
      if (round.locked && round.number > lastStarted) {
        lastStarted = round.number;
      }
    }
    if (lastStarted >= H2hLeaguePolicy.maxRounds) {
      return const Result.ok(H2hNewcomersRun());
    }

    final listResult = await _newcomers.newcomersOf(month);
    if (listResult is Err<List<UserId>>) {
      return Result.err(listResult.error);
    }
    final players = (listResult as Ok<List<UserId>>).value;

    var seated = 0;
    var opened = 0;
    var started = 0;
    for (final player in players) {
      final waitingResult = await _newcomers.waitingGroupOf(month);
      if (waitingResult is Err<H2hWaitingGroup?>) {
        return Result.err(waitingResult.error);
      }
      var waiting = (waitingResult as Ok<H2hWaitingGroup?>).value;
      if (waiting == null) {
        final indexResult = await _newcomers.nextExtraIndexOf(month);
        if (indexResult is Err<int>) {
          return Result.err(indexResult.error);
        }
        final idResult = H2hLeagueId.tryParse(_ids.newUuid());
        if (idResult is Err<H2hLeagueId>) {
          return Result.err(idResult.error);
        }
        final leagueId = (idResult as Ok<H2hLeagueId>).value;
        final groupIndex = (indexResult as Ok<int>).value;
        final openResult = await _newcomers.openWaitingGroup(
          monthStart: month,
          leagueId: leagueId,
          groupIndex: groupIndex,
        );
        if (openResult is Err<void>) {
          return Result.err(openResult.error);
        }
        opened++;
        waiting = H2hWaitingGroup(
          leagueId: leagueId,
          groupIndex: groupIndex,
          seated: 0,
        );
      }
      if (waiting.seated >= H2hLeaguePolicy.groupCapacity) {
        // A full group that has not started: the round it should start
        // from had started when it filled. It starts on a later run.
        return Result.ok(
          H2hNewcomersRun(seated: seated, opened: opened, started: started),
        );
      }
      final fills = waiting.seated + 1 == H2hLeaguePolicy.groupCapacity;
      final seatResult = await _newcomers.seat(
        monthStart: month,
        leagueId: waiting.leagueId,
        userId: player,
        slot: waiting.nextSlot,
        startFrom: fills ? lastStarted + 1 : null,
      );
      if (seatResult is Err<void>) {
        if (seatResult.error.code == 'h2h.newcomer_refused') {
          continue;
        }
        return Result.err(seatResult.error);
      }
      seated++;
      if (fills) {
        started++;
      }
    }
    return Result.ok(
      H2hNewcomersRun(seated: seated, opened: opened, started: started),
    );
  }
}
