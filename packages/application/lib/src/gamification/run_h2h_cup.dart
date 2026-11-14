/// The scheduler's Elite Cup keeping (NK185, migration 0190).
library;

import 'dart:math';

import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/h2h_month_book.dart';
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one run of [RunH2hCup] did.
final class H2hCupRun {
  /// Creates a report.
  const H2hCupRun({
    this.entered = 0,
    this.scheduled = 0,
    this.locked = 0,
    this.decided = 0,
    this.crowned = 0,
  });

  /// Qualifiers stored.
  final int entered;

  /// Stages given a day (new or carried).
  final int scheduled;

  /// Stages whose fixtures were frozen.
  final int locked;

  /// Pairs decided.
  final int decided;

  /// Titles decided.
  final int crowned;

  H2hCupRun _plus({
    int entered = 0,
    int scheduled = 0,
    int locked = 0,
    int decided = 0,
    int crowned = 0,
  }) => H2hCupRun(
    entered: this.entered + entered,
    scheduled: this.scheduled + scheduled,
    locked: this.locked + locked,
    decided: this.decided + decided,
    crowned: this.crowned + crowned,
  );
}

/// Use-case: the Elite Cup's keeping, run by the scheduler after the
/// rounds (NK185).
///
/// For each month of the elite draw (not the pilot) from two months back to
/// now, older first:
///
/// * **Entries.** Once the month has its 19 rounds and every one is judged
///   (settled or void), the first three places of each elite group are
///   stored as the qualifiers of paths 1, 2 and 3 (the month book's tables,
///   so a seat swap is read as the league reads it).
/// * **Four cup days, one at a time, in [H2hCupPolicy.days]** (NK276):
///   path 1's semi-finals, its final, then paths 2 and 3 side by side --
///   their semi-finals on one day, their finals on the next. A stage is
///   given the first qualifying day (six fixtures or more, today or
///   tomorrow, not started, within the lead, not excluded, after every
///   round and every stage of the cup days before it) once every stage of
///   the cup day before it is decided, so the two paths of a day are given
///   the same day. Its fixtures are frozen at its first kickoff; once every
///   one is settled its pairs are decided by [H2hCupPolicy.decide]. A stage
///   left with no fixture to play is carried to the next qualifying day
///   with the same pairs.
/// * **Titles.** A final decides its path; a path whose semi-finals leave
///   one finalist crowns him without a final; none, the title is vacant.
///
/// The monthly championship and the month's close never wait for any of
/// this, and the league's tables are never written. With automatic approval
/// off nothing is scheduled; frozen stages are still judged.
///
/// Never throws; a failure is returned and the next run repeats the work
/// harmlessly (entries, results and titles already stored stay; a stage's
/// day is refused when taken).
final class RunH2hCup {
  /// Creates the use-case over its collaborators.
  RunH2hCup({
    required H2hCupStore cups,
    required H2hRoundStore rounds,
    required H2hLeagueStore leagues,
    required H2hSheetReader sheets,
    required IdGenerator idGenerator,
    H2hControlStore? controls,
    Random? random,
    bool enabled = true,
  }) : _cups = cups,
       _rounds = rounds,
       _leagues = leagues,
       _sheets = sheets,
       _ids = idGenerator,
       _controls = controls,
       _random = random ?? Random.secure(),
       _enabled = enabled;

  final H2hCupStore _cups;
  final H2hRoundStore _rounds;
  final H2hLeagueStore _leagues;
  final H2hSheetReader _sheets;
  final IdGenerator _ids;
  final H2hControlStore? _controls;
  final Random _random;

  /// False when the host turned the cup off (`NUKHBA_H2H_CUP=off`): the
  /// run does nothing at all.
  final bool _enabled;

  /// Keeps every open cup as of [now].
  Future<Result<H2hCupRun>> call({required DateTime now}) async {
    if (!_enabled) {
      return const Result.ok(H2hCupRun());
    }
    final instant = now.toUtc();
    final today = riyadhDayOf(instant);
    final current = H2hLeaguePolicy.monthStartOf(today);
    final months = <DateTime>[
      DateTime.utc(current.year, current.month - 2),
      DateTime.utc(current.year, current.month - 1),
      current,
    ];

    final window = await _window(today);
    if (window is Err<_Window>) {
      return Result.err(window.error);
    }
    final days = (window as Ok<_Window>).value;

    var run = const H2hCupRun();
    for (final month in months) {
      if (!H2hLeaguePolicy.usesEliteDraw(month)) {
        continue;
      }
      final info = await _leagues.monthOf(month);
      if (info is Err<H2hMonthInfo?>) {
        return Result.err(info.error);
      }
      final held = (info as Ok<H2hMonthInfo?>).value;
      if (held == null || held.isPilot) {
        continue;
      }
      final kept = await _keep(month, instant, today, days);
      if (kept is Err<H2hCupRun>) {
        return Result.err(kept.error);
      }
      final did = (kept as Ok<H2hCupRun>).value;
      run = run._plus(
        entered: did.entered,
        scheduled: did.scheduled,
        locked: did.locked,
        decided: did.decided,
        crowned: did.crowned,
      );
    }
    return Result.ok(run);
  }

  Future<Result<H2hCupRun>> _keep(
    DateTime month,
    DateTime now,
    DateTime today,
    _Window days,
  ) async {
    var run = const H2hCupRun();
    var stateResult = await _cups.stateOf(month);
    if (stateResult is Err<H2hCupState>) {
      return Result.err(stateResult.error);
    }
    var state = (stateResult as Ok<H2hCupState>).value;
    if (state.titles.length >= H2hCupPolicy.places.length) {
      return Result.ok(run);
    }

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final rounds = (roundsResult as Ok<List<H2hRound>>).value;

    if (state.entries.isEmpty) {
      final entries = await _qualifiers(month, rounds);
      if (entries is Err<List<H2hCupEntry>>) {
        return Result.err(entries.error);
      }
      final found = (entries as Ok<List<H2hCupEntry>>).value;
      if (found.isEmpty) {
        return Result.ok(run);
      }
      final stored = await _cups.enter(month, found);
      if (stored is Err<void>) {
        return Result.err(stored.error);
      }
      run = run._plus(entered: found.length);
      stateResult = await _cups.stateOf(month);
      if (stateResult is Err<H2hCupState>) {
        return Result.err(stateResult.error);
      }
      state = (stateResult as Ok<H2hCupState>).value;
    }

    // NK276: the cup's four days (H2hCupPolicy.days), one after the other.
    // The paths of one day play side by side on its fixtures; a day starts
    // only once every stage of the day before it is decided, on a day after
    // the month's last round and every stage before it.
    var lastDay = rounds.isEmpty ? null : rounds.last.day;
    final titled = <int>{for (final t in state.titles) t.place};
    final finalists = <int, List<UserId>>{};
    for (final cupDay in H2hCupPolicy.days) {
      // Every day this cup day already used, a carried attempt and a path
      // crowned on an earlier run included: the next cup day comes after.
      var played = lastDay;
      for (final s in state.stages) {
        if (cupDay.contains(s.step)) {
          played = _later(played, s.day);
        }
      }
      var waiting = false;
      for (final step in cupDay) {
        final place = step.place;
        if (titled.contains(place)) {
          continue;
        }
        final entries = state.entriesOf(place);
        if (step.round == H2hCupRound.semi) {
          if (entries.length <= 1) {
            final alone = await _crownAlone(month, place, [
              for (final e in entries) e.userId,
            ]);
            if (alone is Err<void>) {
              return Result.err(alone.error);
            }
            titled.add(place);
            run = run._plus(crowned: 1);
            continue;
          }
          if (entries.length == 2) {
            // Two qualifiers go straight to the final.
            finalists[place] = [entries[0].userId, entries[1].userId];
            continue;
          }
          final semi = await _advance(
            month: month,
            step: step,
            stage: state.stageOf(step),
            entries: entries,
            pairs: () => H2hCupPolicy.drawSemis(entries, _random),
            now: now,
            today: today,
            lastDay: lastDay,
            days: days,
          );
          if (semi is Err<_Advance>) {
            return Result.err(semi.error);
          }
          final advance = (semi as Ok<_Advance>).value;
          run = run._plus(
            scheduled: advance.scheduled,
            locked: advance.locked,
            decided: advance.decided,
          );
          final decidedSemi = advance.decidedStage;
          if (decidedSemi == null) {
            waiting = true;
            continue;
          }
          played = _later(played, decidedSemi.day);
          final through = [
            for (final r in decidedSemi.results)
              if (r.winner != null) r.winner!,
          ];
          final bye = H2hCupPolicy.byeOf(entries, decidedSemi.pairs);
          if (bye != null) {
            through.add(bye);
          }
          if (through.length <= 1) {
            final alone = await _crownAlone(month, place, through);
            if (alone is Err<void>) {
              return Result.err(alone.error);
            }
            titled.add(place);
            run = run._plus(crowned: 1);
            continue;
          }
          finalists[place] = through;
          continue;
        }

        // The final, between the two the semi-finals' day sent through.
        final pairOf = finalists[place];
        if (pairOf == null) {
          continue;
        }
        final finale = await _advance(
          month: month,
          step: step,
          stage: state.stageOf(step),
          entries: entries,
          pairs: () => [H2hCupPair(slot: 1, home: pairOf[0], away: pairOf[1])],
          now: now,
          today: today,
          lastDay: lastDay,
          days: days,
        );
        if (finale is Err<_Advance>) {
          return Result.err(finale.error);
        }
        final advance = (finale as Ok<_Advance>).value;
        run = run._plus(
          scheduled: advance.scheduled,
          locked: advance.locked,
          decided: advance.decided,
        );
        final decidedFinal = advance.decidedStage;
        if (decidedFinal == null) {
          waiting = true;
          continue;
        }
        played = _later(played, decidedFinal.day);
        final pair = decidedFinal.pairs.first;
        final winner = decidedFinal.results.first.winner;
        final crowned = await _cups.crown(
          monthStart: month,
          place: place,
          champion: winner,
          runnerUp: winner == null
              ? null
              : (winner == pair.home ? pair.away : pair.home),
          how: winner == null ? 'vacant' : 'final',
        );
        if (crowned is Err<void>) {
          return Result.err(crowned.error);
        }
        titled.add(place);
        run = run._plus(crowned: 1);
      }
      if (waiting) {
        // Waiting on this cup day: nothing after it may start.
        return Result.ok(run);
      }
      lastDay = played;
    }
    return Result.ok(run);
  }

  /// Crowns [place] without a final: the one player [left], or nobody.
  Future<Result<void>> _crownAlone(
    DateTime month,
    int place,
    List<UserId> left,
  ) => _cups.crown(
    monthStart: month,
    place: place,
    champion: left.isEmpty ? null : left.first,
    runnerUp: null,
    how: left.isEmpty ? 'vacant' : 'walkover',
  );

  static DateTime? _later(DateTime? a, DateTime b) =>
      a == null || b.isAfter(a) ? b : a;

  /// Moves [step] on by one: schedule it, freeze it, judge it or carry it.
  /// The stage it returns as decided carries its results.
  Future<Result<_Advance>> _advance({
    required DateTime month,
    required H2hCupStep step,
    required H2hCupStage? stage,
    required List<H2hCupEntry> entries,
    required List<H2hCupPair> Function() pairs,
    required DateTime now,
    required DateTime today,
    required DateTime? lastDay,
    required _Window days,
  }) async {
    if (stage == null) {
      return _schedule(
        month: month,
        step: step,
        attempt: 1,
        pairs: pairs(),
        now: now,
        lastDay: lastDay,
        days: days,
      );
    }
    if (stage.decided) {
      return Result.ok(_Advance(decidedStage: stage));
    }
    var locked = 0;
    if (!stage.locked) {
      final fixtures = await _rounds.dayFixtures(stage.day);
      if (fixtures is Err<H2hDayFixtures>) {
        return Result.err(fixtures.error);
      }
      final first = (fixtures as Ok<H2hDayFixtures>).value.firstKickoff;
      final started = first != null && !now.isBefore(first);
      if (!started && !stage.day.isBefore(today)) {
        return const Result.ok(_Advance());
      }
      final frozen = await _cups.lock(stageId: stage.id, day: stage.day);
      if (frozen is Err<int>) {
        return Result.err(frozen.error);
      }
      locked = 1;
    }
    final figuresResult = await _cups.figuresOf(stage.id);
    if (figuresResult is Err<H2hCupStageFigures>) {
      return Result.err(figuresResult.error);
    }
    final figures = (figuresResult as Ok<H2hCupStageFigures>).value;
    if (figures.empty) {
      // Nothing left to play on the stage's day: the same pairs on the next
      // qualifying day.
      final carried = await _schedule(
        month: month,
        step: step,
        attempt: stage.attempt + 1,
        pairs: stage.pairs,
        now: now,
        lastDay: _later(lastDay, stage.day),
        days: days,
      );
      if (carried is Err<_Advance>) {
        return carried;
      }
      final did = (carried as Ok<_Advance>).value;
      return Result.ok(_Advance(scheduled: did.scheduled, locked: locked));
    }
    if (!figures.judged) {
      return Result.ok(_Advance(locked: locked));
    }
    final byUser = {for (final e in entries) e.userId: e};
    final results = <H2hCupResult>[];
    for (final pair in stage.pairs) {
      final home = figures.sideOf(pair.home);
      final away = figures.sideOf(pair.away);
      final homeEntry = byUser[pair.home] ?? _bare(pair.home, step.place);
      final awayEntry = byUser[pair.away] ?? _bare(pair.away, step.place);
      final decision = H2hCupPolicy.decide(
        home: home,
        away: away,
        homeEntry: homeEntry,
        awayEntry: awayEntry,
      );
      results.add(
        H2hCupResult(
          slot: pair.slot,
          winner: decision.winner,
          outcome: decision.outcome.wire,
          home: home,
          away: away,
        ),
      );
    }
    final stored = await _cups.decide(stageId: stage.id, results: results);
    if (stored is Err<void>) {
      return Result.err(stored.error);
    }
    return Result.ok(
      _Advance(
        locked: locked,
        decided: results.length,
        decidedStage: H2hCupStage(
          id: stage.id,
          monthStart: stage.monthStart,
          step: stage.step,
          attempt: stage.attempt,
          day: stage.day,
          fixtureCount: stage.fixtureCount,
          lockedAt: stage.lockedAt ?? now,
          pairs: stage.pairs,
          results: results,
        ),
      ),
    );
  }

  static H2hCupEntry _bare(UserId user, int place) => H2hCupEntry(
    userId: user,
    place: place,
    groupNumber: 4,
    leaguePoints: 0,
    pointsFor: 0,
    exactCount: 0,
  );

  /// Gives [step] the first qualifying day after [lastDay], if one is open
  /// now.
  Future<Result<_Advance>> _schedule({
    required DateTime month,
    required H2hCupStep step,
    required int attempt,
    required List<H2hCupPair> pairs,
    required DateTime now,
    required DateTime? lastDay,
    required _Window days,
  }) async {
    if (!days.approving) {
      return const Result.ok(_Advance());
    }
    for (final day in days.days) {
      if (lastDay != null && !day.isAfter(lastDay)) {
        continue;
      }
      if (days.excluded.contains(day)) {
        continue;
      }
      final fixtures = await _rounds.dayFixtures(day);
      if (fixtures is Err<H2hDayFixtures>) {
        return Result.err(fixtures.error);
      }
      final info = (fixtures as Ok<H2hDayFixtures>).value;
      final first = info.firstKickoff;
      if (first == null || !now.isBefore(first)) {
        continue;
      }
      if (first.difference(now) > days.lead) {
        continue;
      }
      if (H2hLeaguePolicy.roundKindOf(info.fixtureCount) !=
          H2hRoundKind.regular) {
        continue;
      }
      final stored = await _cups.schedule(
        id: H2hCupStageId(_ids.newUuid()),
        monthStart: month,
        step: step,
        attempt: attempt,
        day: day,
        fixtureCount: info.fixtureCount,
        pairs: pairs,
      );
      if (stored is Err<void>) {
        if (stored.error.kind == ErrorKind.transient) {
          return Result.err(stored.error);
        }
        // The day was taken (another month's cup): try the next one.
        continue;
      }
      return const Result.ok(_Advance(scheduled: 1));
    }
    return const Result.ok(_Advance());
  }

  /// The qualifiers of [month], or none while its league is not finished.
  Future<Result<List<H2hCupEntry>>> _qualifiers(
    DateTime month,
    List<H2hRound> rounds,
  ) async {
    if (rounds.length < H2hLeaguePolicy.maxRounds ||
        rounds.any((r) => !r.locked)) {
      return const Result.ok(<H2hCupEntry>[]);
    }
    final bookResult = await H2hMonthBook.load(
      leagues: _leagues,
      reader: _sheets,
      monthStart: month,
      rounds: rounds,
    );
    if (bookResult is Err<H2hMonthBook>) {
      return Result.err(bookResult.error);
    }
    final book = (bookResult as Ok<H2hMonthBook>).value;
    final elite = [
      for (final g in book.groups)
        if (g.division == H2hLeaguePolicy.eliteDivision) g,
    ]..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    if (elite.isEmpty) {
      return const Result.ok(<H2hCupEntry>[]);
    }
    // The rounds are judged the same in every group: their fixtures are the
    // month's, not the group's.
    final sheet = book.sheets[elite.first.leagueId];
    if (sheet == null) {
      return const Result.ok(<H2hCupEntry>[]);
    }
    final judged = sheet.settledRounds.union(sheet.voidRounds);
    final finished = H2hCupPolicy.leagueFinished(
      roundCount: rounds.length,
      judgedRounds: [
        for (final r in rounds)
          if (judged.contains(r.number)) r,
      ].length,
    );
    if (!finished) {
      return const Result.ok(<H2hCupEntry>[]);
    }
    final refs = [for (final r in rounds) r.ref];
    final merged = book.standings(refs);
    final entries = <H2hCupEntry>[];
    for (final group in elite.take(H2hLeaguePolicy.eliteGroups)) {
      final placings = book.placingsOf(group.leagueId, refs, merged: merged);
      for (
        var i = 0;
        i < placings.length && i < H2hCupPolicy.places.length;
        i++
      ) {
        final standing = placings[i].standing;
        entries.add(
          H2hCupEntry(
            userId: standing.userId,
            place: i + 1,
            groupNumber: group.groupIndex + 1,
            leaguePoints: standing.leaguePoints,
            pointsFor: standing.pointsFor,
            exactCount: standing.exactCount,
          ),
        );
      }
    }
    return Result.ok(entries);
  }

  /// The days a stage may be given now, and the admin's controls.
  Future<Result<_Window>> _window(DateTime today) async {
    final tomorrow = today.add(const Duration(days: 1));
    var approving = true;
    var lead = H2hLeaguePolicy.autoApproveLead;
    var excluded = const <DateTime>{};
    final controls = _controls;
    if (controls != null) {
      final settings = await controls.settings();
      if (settings is Err<H2hSettings>) {
        return Result.err(settings.error);
      }
      final knobs = (settings as Ok<H2hSettings>).value;
      approving = knobs.autoApprove;
      final hours = Duration(hours: knobs.leadHours);
      if (hours < lead) {
        lead = hours;
      }
      final days = await controls.excludedDays(from: today, through: tomorrow);
      if (days is Err<Set<DateTime>>) {
        return Result.err(days.error);
      }
      excluded = (days as Ok<Set<DateTime>>).value;
    }
    return Result.ok(
      _Window(
        days: [today, tomorrow],
        approving: approving,
        lead: lead,
        excluded: excluded,
      ),
    );
  }
}

final class _Window {
  const _Window({
    required this.days,
    required this.approving,
    required this.lead,
    required this.excluded,
  });

  final List<DateTime> days;
  final bool approving;
  final Duration lead;
  final Set<DateTime> excluded;
}

final class _Advance {
  const _Advance({
    this.scheduled = 0,
    this.locked = 0,
    this.decided = 0,
    this.decidedStage,
  });

  final int scheduled;
  final int locked;
  final int decided;
  final H2hCupStage? decidedStage;
}
