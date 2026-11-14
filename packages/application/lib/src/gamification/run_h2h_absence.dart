/// Use-case: relegation for absence in the head-to-head league (NK183,
/// migration 0189), run by the league's scheduler.
library;

import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/h2h_month_book.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_seat_move_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:application/src/gamification/ports/h2h_vacancy_store.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one run did.
final class H2hAbsenceRun {
  /// Creates a run summary.
  const H2hAbsenceRun({
    this.warned = 0,
    this.moved = 0,
    this.unfilled = 0,
    this.vacated = 0,
    this.filled = 0,
  });

  /// Elite players warned after a second consecutive absence.
  final int warned;

  /// Swaps stored before the next round.
  final int moved;

  /// Elite players due to leave with no substitute qualifying: they stay
  /// until the next round's turn.
  final int unfilled;

  /// NK278: seats of the last group that plays left for the waiting list.
  final int vacated;

  /// NK278: vacant seats taken by a player of the waiting list.
  final int filled;
}

/// The month's facts the absence rules read, shared by the job and the
/// admin's view and hand relegation.
final class H2hAbsenceState {
  /// Creates a state.
  H2hAbsenceState({
    required this.monthStart,
    required this.rounds,
    required this.counted,
    required this.book,
    required this.moves,
    required this.elite,
    required this.extra,
    required this.nextRound,
    this.vacancies = const <H2hSeatVacancy>[],
    this.playing = const <H2hAbsenceGroup>[],
    this.waiting = const <H2hHeldSeat>[],
  });

  /// The month.
  final DateTime monthStart;

  /// Its approved rounds, in order.
  final List<H2hRound> rounds;

  /// The counted rounds of the run: the month before (when it was played
  /// under the elite draw) and this one, oldest first.
  final List<H2hCountedRound> counted;

  /// Every group of the month with its sheet.
  final H2hMonthBook book;

  /// The month's swaps so far.
  final List<H2hSeatMove> moves;

  /// The elite seats (division 1) and who holds them now.
  final List<H2hHeldSeat> elite;

  /// The extra seats (division 2) and who holds them now.
  final List<H2hHeldSeat> extra;

  /// The first approved round of the month that has not started, or null.
  final H2hRound? nextRound;

  /// NK278: the month's seats left for absence, with their fills (read
  /// from December 2026 only).
  final List<H2hSeatVacancy> vacancies;

  /// NK278: the groups that play, each with its seats held now.
  final List<H2hAbsenceGroup> playing;

  /// NK278: the seats of the waiting group that has not started, held now:
  /// the waiting list a vacant seat is filled from.
  final List<H2hHeldSeat> waiting;

  /// Every player's month over its locked rounds.
  late final Map<UserId, H2hStanding> _played = book.standings([
    for (final round in rounds)
      if (round.locked) round.ref,
  ]);

  /// The opponents each relegated player met, read once.
  late final Map<UserId, Set<UserId>> _metBy = <UserId, Set<UserId>>{};

  /// Players relegated this month: they never come back in it. NK278: and
  /// those who left a seat for the waiting list.
  Set<UserId> get relegated => {
    for (final m in moves) m.outUser,
    for (final v in vacancies) v.outUser,
  };

  /// Players promoted this month. NK278: and those who took a vacant seat.
  Set<UserId> get promoted => {
    for (final m in moves) m.inUser,
    for (final v in vacancies) ?v.filledBy,
  };

  /// The group of [leagueId], or null.
  H2hGroupRef? groupOf(H2hLeagueId leagueId) {
    for (final group in book.groups) {
      if (group.leagueId == leagueId) {
        return group;
      }
    }
    return null;
  }

  /// Whether [relegated] taking [seat] from round [fromRound] on would meet
  /// an opponent he already met this month (the owner's rule: no match is
  /// played twice). The seat's opponents are its current neighbours by the
  /// group's schedule.
  bool wouldRepeat(UserId relegated, H2hHeldSeat seat, int fromRound) {
    final met = _metBy.putIfAbsent(relegated, () {
      final opponents = <UserId>{};
      final mine = _played[relegated];
      if (mine != null) {
        for (final match in mine.matches) {
          final opponent = match.opponentId;
          if (opponent != null) {
            opponents.add(opponent);
          }
        }
      }
      return opponents;
    });
    if (met.isEmpty) {
      return false;
    }
    final group = groupOf(seat.leagueId);
    final sheet = book.sheets[seat.leagueId];
    if (group == null || sheet == null) {
      return false;
    }
    final bySlot = <int, UserId>{
      for (final member in h2hCurrentMembers(sheet)) member.slot: member.userId,
    };
    for (var n = fromRound; n <= H2hAbsencePolicy.lastEffectiveRound; n++) {
      final opponent =
          bySlot[H2hLeaguePolicy.opponentSlot(
            slot: seat.slot,
            round: H2hLeaguePolicy.turnOf(round: n, turns: sheet.turns),
            capacity: group.capacity,
          )];
      if (opponent != null &&
          opponent != seat.userId &&
          met.contains(opponent)) {
        return true;
      }
    }
    return false;
  }
}

/// Runs relegation for absence: warns after a second consecutive absence,
/// and swaps the seats of the players who reached three, an hour before the
/// next round's first kickoff (`H2hAbsencePolicy`).
///
/// **When.** A swap is stored inside [H2hAbsencePolicy.relegationLead] of
/// the next round's first kickoff, so an admin has every hour until then to
/// excuse a round in which the app failed. A round at or past 19 moves
/// nobody. A month not drawn by the elite draw, or a pilot month, is left
/// alone.
///
/// **Safe to run often.** A warning is stored once per round and player
/// before its push; a swap is refused by the database when it was made
/// already, and the refusal is not an error of the run. A failure is
/// returned, and the next tick tries again.
///
/// Never throws; returns a typed [Result].
final class RunH2hAbsence {
  /// Creates the use-case over its collaborators.
  const RunH2hAbsence({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required H2hSeatMoveStore moves,
    required PushSender sender,
    required IdGenerator idGenerator,
    bool relegate = true,
    H2hVacancyStore? vacancies,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _moves = moves,
       _sender = sender,
       _ids = idGenerator,
       _relegate = relegate,
       _vacancies = vacancies;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final H2hSeatMoveStore _moves;
  final PushSender _sender;
  final IdGenerator _ids;
  final bool _relegate;

  /// NK278: the vacancies of the last group. With it, a month of December
  /// 2026 or later is run by the December rules (absence in every group);
  /// without it, as before.
  final H2hVacancyStore? _vacancies;

  /// The warning push.
  static const String warningTitle = 'تنبيه غياب ⚠️';

  /// Its text.
  static const String warningBody =
      'غبت عن جولتين متتاليتين في دوري المواجهات. إن لم تتوقع في الجولة '
      'القادمة تهبط من مجموعتك إلى المجموعات الإضافية.';

  // NK278_10
  /// The December warning (absence in every group, owner 2026-11-14).
  static const String warningBodyDecember =
      'غبت عن جولتين متتاليتين في دوري المواجهات. إن لم تتوقع في الجولة '
      'القادمة تهبط إلى المجموعة التي تلي مجموعتك، وإن كانت مجموعتك '
      'الأخيرة تترك مقعدك وتنتقل إلى قائمة الانتظار.';

  /// The push to a player of the last group who left his seat.
  static const String vacatedTitle = 'انتقلت إلى قائمة الانتظار';

  /// Its text, from round [round].
  static String vacatedBody(int round) =>
      'غبت عن 3 جولات متتالية فتركت مقعدك من الجولة $round. تعود إلى '
      'مجموعة حين تتوقع من جديد، ولا تُحسب في مجموعة الانتظار قبل ذلك.';

  /// The push to a player of the waiting list who took a vacant seat, in
  /// group [group] from round [round].
  static String filledBody(int group, int round) =>
      'لالتزامك انتقلت من قائمة الانتظار إلى المجموعة $group من الجولة '
      '$round، وتأخذ نقاط المقعد الذي جلست فيه.';

  /// The push to a relegated player.
  static const String relegatedTitle = 'هبطت من مجموعتك';

  /// Its text, for group [group] from round [round]. [keepsRecord]: the
  /// seat's record stays with the seat (NK216), so he takes the points of
  /// the seat he moves to; else his points go with him.
  static String relegatedBody(
    int group,
    int round, {
    bool keepsRecord = false,
  }) =>
      'غبت عن 3 جولات متتالية فانتقلت إلى المجموعة $group من الجولة '
      '$round. ${keepsRecord ? _seatPoints : 'نقاطك معك.'}';

  // NK216_20
  static const String _seatPoints = 'تأخذ نقاط المقعد الذي انتقلت إليه.';

  /// The push to a promoted player.
  static String promotedTitle(int group) => 'صعدت إلى المجموعة $group 🎉';

  /// Its text, from round [round]. [keepsRecord]: the seat's record stays
  /// with the seat (NK216), so he takes the points of the seat he fills.
  static String promotedBody(int round, {bool keepsRecord = false}) =>
      'لالتزامك صعدت بدلاً من لاعب غاب 3 جولات متتالية. تلعب في مجموعتك '
      'الجديدة من الجولة $round، '
      '${keepsRecord ? 'وتأخذ نقاط المقعد الذي جلست فيه.' : 'ونقاطك معك.'}';

  /// One run at [now].
  Future<Result<H2hAbsenceRun>> call({required DateTime now}) async {
    final stateResult = await loadH2hAbsenceState(
      leagues: _leagues,
      rounds: _rounds,
      sheets: _sheets,
      moves: _moves,
      now: now,
      vacancies: _vacancies,
    );
    if (stateResult is Err<H2hAbsenceState?>) {
      return Result.err(stateResult.error);
    }
    final state = (stateResult as Ok<H2hAbsenceState?>).value;
    if (state == null) {
      return const Result.ok(H2hAbsenceRun());
    }
    // NK278: from December 2026 absence counts in every group.
    final vacancies = _vacancies;
    final december =
        vacancies != null &&
        H2hLeaguePolicy.usesDecemberRules(state.monthStart);

    // The warning: an elite player whose run of absences just reached two
    // (NK278: from December any player of a group that plays).
    var warned = 0;
    if (state.counted.isNotEmpty) {
      final latest = state.counted.last;
      final warnedSeats = december
          ? [for (final group in state.playing) ...group.seats]
          : state.elite;
      for (final seat in warnedSeats) {
        final run = december
            ? H2hAbsencePolicy.absenceRunIn(
                seat,
                state.counted,
                state.monthStart,
              )
            : H2hAbsencePolicy.absenceRun(seat.userId, state.counted);
        if (run.length != H2hAbsencePolicy.warningStreak) {
          continue;
        }
        final recorded = await _moves.recordWarning(
          roundId: latest.roundId,
          userId: seat.userId,
        );
        if (recorded is Err<bool>) {
          return Result.err(recorded.error);
        }
        if (!(recorded as Ok<bool>).value) {
          continue;
        }
        warned++;
        await _push(
          seat.userId,
          warningTitle,
          december ? warningBodyDecember : warningBody,
        );
      }
    }

    if (!_relegate) {
      return Result.ok(H2hAbsenceRun(warned: warned));
    }
    final next = state.nextRound;
    if (next == null ||
        next.number < 2 ||
        next.number > H2hAbsencePolicy.lastEffectiveRound) {
      return Result.ok(H2hAbsenceRun(warned: warned));
    }
    final dayResult = await _rounds.dayFixtures(next.day);
    if (dayResult is Err<H2hDayFixtures>) {
      return Result.err(dayResult.error);
    }
    final firstKickoff = (dayResult as Ok<H2hDayFixtures>).value.firstKickoff;
    if (firstKickoff == null ||
        now.isBefore(firstKickoff.subtract(H2hAbsencePolicy.relegationLead)) ||
        !now.isBefore(firstKickoff)) {
      return Result.ok(H2hAbsenceRun(warned: warned));
    }

    if (december) {
      final done = await applyH2hDecemberMoves(
        state: state,
        fromRound: next.number,
        moves: _moves,
        vacancies: vacancies,
        sender: _sender,
        ids: _ids,
        now: now,
      );
      if (done is Err<H2hAbsenceRun>) {
        return Result.err(done.error);
      }
      final run = (done as Ok<H2hAbsenceRun>).value;
      return Result.ok(
        H2hAbsenceRun(
          warned: warned,
          moved: run.moved,
          unfilled: run.unfilled,
          vacated: run.vacated,
          filled: run.filled,
        ),
      );
    }

    final applied = await applyH2hAbsenceMoves(
      state: state,
      fromRound: next.number,
      moves: _moves,
      sender: _sender,
      ids: _ids,
      now: now,
    );
    if (applied is Err<({int moved, int unfilled})>) {
      return Result.err(applied.error);
    }
    final done = (applied as Ok<({int moved, int unfilled})>).value;
    return Result.ok(
      H2hAbsenceRun(warned: warned, moved: done.moved, unfilled: done.unfilled),
    );
  }

  Future<void> _push(UserId userId, String title, String body) async {
    final tokens = await _moves.pushTokensOf(userId);
    if (tokens is Ok<List<String>> && tokens.value.isNotEmpty) {
      await _sender.send(
        tokens: tokens.value,
        title: title,
        body: body,
        link: PushLink.h2h,
      );
    }
  }
}

/// Reads the month open at [now] as the absence rules see it, or null when
/// the rules do not apply to it (not an elite month, not drawn, a pilot).
Future<Result<H2hAbsenceState?>> loadH2hAbsenceState({
  required H2hLeagueStore leagues,
  required H2hRoundStore rounds,
  required H2hSheetReader sheets,
  required H2hSeatMoveStore moves,
  required DateTime now,
  H2hVacancyStore? vacancies,
}) async {
  final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(now));
  if (!H2hLeaguePolicy.usesEliteDraw(month)) {
    return const Result.ok(null);
  }
  final infoResult = await leagues.monthOf(month);
  if (infoResult is Err<H2hMonthInfo?>) {
    return Result.err(infoResult.error);
  }
  final info = (infoResult as Ok<H2hMonthInfo?>).value;
  if (info == null || info.isPilot) {
    return const Result.ok(null);
  }

  final roundsResult = await rounds.roundsOf(month);
  if (roundsResult is Err<List<H2hRound>>) {
    return Result.err(roundsResult.error);
  }
  final monthRounds = (roundsResult as Ok<List<H2hRound>>).value;

  // The run goes on across months: the month before counts when it was
  // played under the elite draw.
  final previous = H2hLeaguePolicy.previousMonthOf(month);
  var earlier = const <H2hRound>[];
  if (H2hLeaguePolicy.usesEliteDraw(previous)) {
    final previousInfo = await leagues.monthOf(previous);
    if (previousInfo is Err<H2hMonthInfo?>) {
      return Result.err(previousInfo.error);
    }
    final prior = (previousInfo as Ok<H2hMonthInfo?>).value;
    if (prior != null && !prior.isPilot) {
      final previousRounds = await rounds.roundsOf(previous);
      if (previousRounds is Err<List<H2hRound>>) {
        return Result.err(previousRounds.error);
      }
      earlier = (previousRounds as Ok<List<H2hRound>>).value;
    }
  }
  final all = <H2hRound>[...earlier, ...monthRounds];

  final attendanceResult = await moves.attendance(all);
  if (attendanceResult is Err<List<H2hRoundAttendance>>) {
    return Result.err(attendanceResult.error);
  }
  final excusalsResult = await moves.excusals(all);
  if (excusalsResult is Err<Map<H2hRoundId, H2hRoundExcusal>>) {
    return Result.err(excusalsResult.error);
  }
  final excused =
      (excusalsResult as Ok<Map<H2hRoundId, H2hRoundExcusal>>).value;
  final attendanceOf = <H2hRoundId, H2hRoundAttendance>{
    for (final a in (attendanceResult as Ok<List<H2hRoundAttendance>>).value)
      a.roundId: a,
  };
  final counted = <H2hCountedRound>[];
  for (final round in all) {
    final attendance = attendanceOf[round.id];
    final last = attendance?.lastKickoff;
    if (!round.locked ||
        attendance == null ||
        attendance.fixtures == 0 ||
        last == null ||
        now.isBefore(last) ||
        excused.containsKey(round.id)) {
      continue;
    }
    counted.add(
      H2hCountedRound(
        roundId: round.id,
        monthStart: round.monthStart,
        number: round.number,
        day: round.day,
        present: attendance.present,
      ),
    );
  }

  final bookResult = await H2hMonthBook.load(
    leagues: leagues,
    reader: sheets,
    monthStart: month,
    rounds: monthRounds,
  );
  if (bookResult is Err<H2hMonthBook>) {
    return Result.err(bookResult.error);
  }
  final book = (bookResult as Ok<H2hMonthBook>).value;

  final movesResult = await moves.movesOf(month);
  if (movesResult is Err<List<H2hSeatMove>>) {
    return Result.err(movesResult.error);
  }

  // NK278: the vacancies of the last group, from December 2026.
  var vacancyList = const <H2hSeatVacancy>[];
  if (vacancies != null && H2hLeaguePolicy.usesDecemberRules(month)) {
    final read = await vacancies.vacanciesOf(month);
    if (read is Err<List<H2hSeatVacancy>>) {
      return Result.err(read.error);
    }
    vacancyList = (read as Ok<List<H2hSeatVacancy>>).value;
  }

  final elite = <H2hHeldSeat>[];
  final extra = <H2hHeldSeat>[];
  final playing = <H2hAbsenceGroup>[];
  final waiting = <H2hHeldSeat>[];
  for (final group in book.groups) {
    final sheet = book.sheets[group.leagueId];
    if (sheet == null) {
      continue;
    }
    final into = group.division == H2hLeaguePolicy.eliteDivision
        ? elite
        : (group.division == H2hLeaguePolicy.extraDivision ? extra : null);
    if (into == null) {
      continue;
    }
    final held = <H2hHeldSeat>[];
    for (final member in h2hCurrentMembers(sheet)) {
      final seat = H2hHeldSeat(
        userId: member.userId,
        leagueId: group.leagueId,
        groupIndex: group.groupIndex,
        slot: member.slot,
        fromRound: member.fromRound,
      );
      // NK277: a player of a waiting group that has not started plays no
      // round: he is never a substitute. NK278: he is the waiting list.
      if (member.waiting) {
        waiting.add(seat);
        continue;
      }
      into.add(seat);
      held.add(seat);
    }
    if (held.isNotEmpty) {
      playing.add(
        H2hAbsenceGroup(
          leagueId: group.leagueId,
          number: H2hLeaguePolicy.groupNumberOf(
            division: group.division,
            groupIndex: group.groupIndex,
          ),
          seats: List<H2hHeldSeat>.unmodifiable(held),
        ),
      );
    }
  }

  H2hRound? next;
  for (final round in monthRounds) {
    if (!round.locked) {
      next = round;
      break;
    }
  }

  return Result.ok(
    H2hAbsenceState(
      monthStart: month,
      rounds: monthRounds,
      counted: List<H2hCountedRound>.unmodifiable(counted),
      book: book,
      moves: (movesResult as Ok<List<H2hSeatMove>>).value,
      elite: List<H2hHeldSeat>.unmodifiable(elite),
      extra: List<H2hHeldSeat>.unmodifiable(extra),
      nextRound: next,
      vacancies: vacancyList,
      playing: List<H2hAbsenceGroup>.unmodifiable(playing),
      waiting: List<H2hHeldSeat>.unmodifiable(waiting),
    ),
  );
}

/// The facts of every extra holder over the window ending on the last
/// counted round (or the day before [fallbackDay] when none is counted).
Future<Result<List<H2hCandidateFacts>>> loadH2hCandidateFacts({
  required H2hAbsenceState state,
  required H2hSeatMoveStore moves,
  required DateTime fallbackDay,
}) {
  final lastDay = state.counted.isNotEmpty
      ? state.counted.last.day
      : DateTime.utc(
          fallbackDay.year,
          fallbackDay.month,
          fallbackDay.day,
        ).subtract(const Duration(days: 1));
  return moves.candidateFacts(
    lastDay: lastDay,
    users: [for (final seat in state.extra) seat.userId],
  );
}

/// Plans and stores the absence swaps due before round [fromRound], and
/// tells the players. Returns how many were stored and how many found no
/// substitute.
Future<Result<({int moved, int unfilled})>> applyH2hAbsenceMoves({
  required H2hAbsenceState state,
  required int fromRound,
  required H2hSeatMoveStore moves,
  required PushSender sender,
  required IdGenerator ids,
  required DateTime now,
}) async {
  final factsResult = await loadH2hCandidateFacts(
    state: state,
    moves: moves,
    fallbackDay: state.nextRound?.day ?? state.monthStart,
  );
  if (factsResult is Err<List<H2hCandidateFacts>>) {
    return Result.err(factsResult.error);
  }
  final plan = H2hAbsencePolicy.planAbsenceMoves(
    elite: state.elite,
    extra: state.extra,
    counted: state.counted,
    facts: (factsResult as Ok<List<H2hCandidateFacts>>).value,
    alreadyOut: state.relegated,
    alreadyIn: state.promoted,
    wouldRepeat: (out, seat) => state.wouldRepeat(out, seat, fromRound),
  );

  var moved = 0;
  for (final planned in plan.moves) {
    final move = H2hSeatMove(
      id: ids.newUuid(),
      monthStart: state.monthStart,
      fromRound: fromRound,
      kind: H2hSeatMoveKind.absence,
      outUser: planned.out,
      inUser: planned.substitute,
      eliteLeagueId: planned.eliteSeat.leagueId,
      eliteSlot: planned.eliteSeat.slot,
      extraLeagueId: planned.extraSeat.leagueId,
      extraSlot: planned.extraSeat.slot,
      absentRounds: [
        for (final r in planned.absentRounds)
          (month: r.monthStart, round: r.number),
      ],
      facts: planned.facts,
      reason: null,
      decidedBy: null,
      createdAt: now,
    );
    final stored = await moves.recordMove(move: move, logId: ids.newUuid());
    if (stored is Err<void>) {
      if (stored.error.code == 'h2h.move_refused') {
        // Made already (a second tick, a second server): nothing to tell.
        continue;
      }
      return Result.err(stored.error);
    }
    moved++;
    await tellH2hSeatMove(
      state: state,
      move: move,
      moves: moves,
      sender: sender,
    );
  }
  return Result.ok((moved: moved, unfilled: plan.unfilled.length));
}

/// Tells the two players of [move] what happened, by push.
Future<void> tellH2hSeatMove({
  required H2hAbsenceState state,
  required H2hSeatMove move,
  required H2hSeatMoveStore moves,
  required PushSender sender,
}) async {
  final elite = state.groupOf(move.eliteLeagueId);
  final extra = state.groupOf(move.extraLeagueId);
  if (elite == null || extra == null) {
    return;
  }
  final eliteNumber = H2hLeaguePolicy.groupNumberOf(
    division: elite.division,
    groupIndex: elite.groupIndex,
  );
  final extraNumber = H2hLeaguePolicy.groupNumberOf(
    division: extra.division,
    groupIndex: extra.groupIndex,
  );
  // NK216_21: from round 7 of November 2026 the record stays with the seat.
  final keepsRecord = H2hLeaguePolicy.seatKeepsRecord(
    day: state.monthStart,
    fromRound: move.fromRound,
  );
  final outTokens = await moves.pushTokensOf(move.outUser);
  if (outTokens is Ok<List<String>> && outTokens.value.isNotEmpty) {
    await sender.send(
      tokens: outTokens.value,
      title: RunH2hAbsence.relegatedTitle,
      body: move.kind == H2hSeatMoveKind.absence
          ? RunH2hAbsence.relegatedBody(
              extraNumber,
              move.fromRound,
              keepsRecord: keepsRecord,
            )
          : 'نُقلت إلى المجموعة $extraNumber من الجولة ${move.fromRound} '
                'بقرار من إدارة الدوري.',
      link: PushLink.h2h,
    );
  }
  final inTokens = await moves.pushTokensOf(move.inUser);
  if (inTokens is Ok<List<String>> && inTokens.value.isNotEmpty) {
    await sender.send(
      tokens: inTokens.value,
      title: RunH2hAbsence.promotedTitle(eliteNumber),
      body: move.kind == H2hSeatMoveKind.absence
          ? RunH2hAbsence.promotedBody(move.fromRound, keepsRecord: keepsRecord)
          : 'لالتزامك صعدت إلى المجموعة $eliteNumber من الجولة '
                '${move.fromRound}، '
                '${keepsRecord ? 'وتأخذ نقاط المقعد الذي جلست فيه.' : 'ونقاطك معك.'}',
      link: PushLink.h2h,
    );
  }
}

// NK278 absence in every group (owner, 2026-11-14; migration 0214)
/// Plans and stores what the December rules do before round [fromRound]
/// (`H2hAbsencePolicy.planDecemberMoves`) and tells the players: the seats
/// left vacant before filled from the waiting list, the swaps between a
/// group and the one below it, and the seats of the last group left for
/// the waiting list, each with its fill in the same transaction when a
/// player of the waiting list qualifies.
///
/// A write the database refuses (made already by another tick or server, a
/// player who moved meanwhile) is skipped: nothing changed, nothing is
/// told, and the next run plans again from what is stored. Running twice
/// therefore never moves anybody twice.
Future<Result<H2hAbsenceRun>> applyH2hDecemberMoves({
  required H2hAbsenceState state,
  required int fromRound,
  required H2hSeatMoveStore moves,
  required H2hVacancyStore vacancies,
  required PushSender sender,
  required IdGenerator ids,
  required DateTime now,
}) async {
  final lastDay = state.counted.isNotEmpty
      ? state.counted.last.day
      : (state.nextRound?.day ?? state.monthStart).subtract(
          const Duration(days: 1),
        );
  final factsResult = await moves.candidateFacts(
    lastDay: DateTime.utc(lastDay.year, lastDay.month, lastDay.day),
    users: [
      for (final seat in state.extra) seat.userId,
      for (final seat in state.waiting) seat.userId,
    ],
  );
  if (factsResult is Err<List<H2hCandidateFacts>>) {
    return Result.err(factsResult.error);
  }
  final plan = H2hAbsencePolicy.planDecemberMoves(
    groups: state.playing,
    waiting: state.waiting,
    open: [
      for (final v in state.vacancies)
        if (!v.filled)
          H2hOpenVacancy(
            id: v.id,
            leagueId: v.leagueId,
            slot: v.slot,
            outUser: v.outUser,
          ),
    ],
    counted: state.counted,
    facts: (factsResult as Ok<List<H2hCandidateFacts>>).value,
    monthStart: state.monthStart,
    alreadyOut: state.relegated,
    alreadyIn: state.promoted,
    wouldRepeat: (out, seat) => state.wouldRepeat(out, seat, fromRound),
  );

  H2hVacancyFill fillOf(String vacancyId, H2hPlannedFill planned) =>
      H2hVacancyFill(
        vacancyId: vacancyId,
        monthStart: state.monthStart,
        inUser: planned.user,
        fromRound: fromRound,
        fromLeagueId: planned.waitingSeat.leagueId,
        fromSlot: planned.waitingSeat.slot,
        facts: planned.facts,
      );

  var filled = 0;
  for (final (vacancy, planned) in plan.fills) {
    final stored = await vacancies.fill(fillOf(vacancy.id, planned));
    if (stored is Err<void>) {
      if (stored.error.code == 'h2h.move_refused') {
        continue;
      }
      return Result.err(stored.error);
    }
    filled++;
    await _tellFill(
      state,
      vacancy.leagueId,
      planned.user,
      fromRound,
      moves,
      sender,
    );
  }

  var moved = 0;
  for (final planned in plan.moves) {
    final move = H2hSeatMove(
      id: ids.newUuid(),
      monthStart: state.monthStart,
      fromRound: fromRound,
      kind: H2hSeatMoveKind.absence,
      outUser: planned.out,
      inUser: planned.substitute,
      eliteLeagueId: planned.eliteSeat.leagueId,
      eliteSlot: planned.eliteSeat.slot,
      extraLeagueId: planned.extraSeat.leagueId,
      extraSlot: planned.extraSeat.slot,
      absentRounds: [
        for (final r in planned.absentRounds)
          (month: r.monthStart, round: r.number),
      ],
      facts: planned.facts,
      reason: null,
      decidedBy: null,
      createdAt: now,
    );
    final stored = await moves.recordMove(move: move, logId: ids.newUuid());
    if (stored is Err<void>) {
      if (stored.error.code == 'h2h.move_refused') {
        continue;
      }
      return Result.err(stored.error);
    }
    moved++;
    await tellH2hSeatMove(
      state: state,
      move: move,
      moves: moves,
      sender: sender,
    );
  }

  var vacated = 0;
  for (final planned in plan.vacancies) {
    final id = ids.newUuid();
    final vacancy = H2hSeatVacancy(
      id: id,
      monthStart: state.monthStart,
      leagueId: planned.seat.leagueId,
      slot: planned.seat.slot,
      outUser: planned.out,
      fromRound: fromRound,
      absentRounds: [
        for (final r in planned.absentRounds)
          (month: r.monthStart, round: r.number),
      ],
    );
    final fill = planned.fill;
    final stored = await vacancies.vacate(
      vacancy: vacancy,
      fill: fill == null ? null : fillOf(id, fill),
    );
    if (stored is Err<void>) {
      if (stored.error.code == 'h2h.move_refused') {
        continue;
      }
      return Result.err(stored.error);
    }
    vacated++;
    final tokens = await moves.pushTokensOf(planned.out);
    if (tokens is Ok<List<String>> && tokens.value.isNotEmpty) {
      await sender.send(
        tokens: tokens.value,
        title: RunH2hAbsence.vacatedTitle,
        body: RunH2hAbsence.vacatedBody(fromRound),
        link: PushLink.h2h,
      );
    }
    if (fill != null) {
      filled++;
      await _tellFill(
        state,
        planned.seat.leagueId,
        fill.user,
        fromRound,
        moves,
        sender,
      );
    }
  }

  return Result.ok(
    H2hAbsenceRun(
      moved: moved,
      unfilled: plan.unfilled.length,
      vacated: vacated,
      filled: filled,
    ),
  );
}

/// Tells [user] he took a vacant seat of [leagueId] from round [round].
Future<void> _tellFill(
  H2hAbsenceState state,
  H2hLeagueId leagueId,
  UserId user,
  int round,
  H2hSeatMoveStore moves,
  PushSender sender,
) async {
  final group = state.groupOf(leagueId);
  if (group == null) {
    return;
  }
  final number = H2hLeaguePolicy.groupNumberOf(
    division: group.division,
    groupIndex: group.groupIndex,
  );
  final tokens = await moves.pushTokensOf(user);
  if (tokens is Ok<List<String>> && tokens.value.isNotEmpty) {
    await sender.send(
      tokens: tokens.value,
      title: RunH2hAbsence.promotedTitle(number),
      body: RunH2hAbsence.filledBody(number, round),
      link: PushLink.h2h,
    );
  }
}
