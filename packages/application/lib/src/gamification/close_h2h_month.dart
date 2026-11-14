import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/h2h_month_book.dart';
import 'package:application/src/gamification/ports/gamification_event_sink.dart';
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_outcome_reader.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: judges the head-to-head months that have ended (migration
/// 0100).
///
/// For every group of an ended month it reads the sheet, builds the table
/// over the month's played rounds (`H2hLeaguePolicy.table` and `order`),
/// judges the month (`H2hLeaguePolicy.monthEnd`, with the players who
/// predicted on five days as the eligible set) and writes one
/// `h2h_league_finished` event per member. The events ARE the result; the
/// next draw reads them.
///
/// **When.** The oldest unclosed month first. A month is due [grace] after
/// it ended (Riyadh midnight), and once every locked round is settled -- or,
/// if a result never arrives, [settleWait] after it ended: an unscored
/// fixture then counts for nobody.
///
/// **A pilot month** is closed without events: its results decide nothing.
///
/// **The admin's settings (0101)**, when [controls] is given: the days of
/// predictions that keep a player in the league are the settings'
/// `min_active_days` (five by default); unreadable settings leave the
/// month open for the next run.
///
/// **A month of the elite draw** (NK275, owner 2026-11-14) is not
/// judged by the divisions' ladder: `H2hEliteCarry` sends the last
/// three of each elite group down, fills the elite from groups 5 and 6
/// by commitment (absences, predictions, exact scorelines, right
/// outcomes from [outcomes], points), moves five down and five up
/// between the extra groups, and each event carries `next_order`, the
/// place in the next month's drawing order.
///
/// **Idempotent.** Each event is keyed on the user and the month; the month
/// is marked closed only after every event was recorded, so a failure half
/// way leaves it open and the next run repeats it harmlessly.
///
/// Never throws; returns a typed [Result] with the number of months closed.
final class CloseH2hMonth {
  /// Creates the use-case over its collaborators.
  const CloseH2hMonth({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required GamificationEventSink events,
    required IdGenerator idGenerator,
    H2hControlStore? controls,
    H2hOutcomeReader? outcomes,
    this.grace = const Duration(hours: 3),
    this.settleWait = const Duration(days: 3),
    this.maxMonthsPerRun = 3,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _events = events,
       _ids = idGenerator,
       _controls = controls,
       _outcomes = outcomes;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final GamificationEventSink _events;
  final IdGenerator _ids;
  final H2hControlStore? _controls;

  /// The right outcomes of a month (NK275); null counts none.
  final H2hOutcomeReader? _outcomes;

  /// How long a month must have been over before it is judged.
  final Duration grace;

  /// How long to wait for the last results before judging without them.
  final Duration settleWait;

  /// The most months a single run closes.
  final int maxMonthsPerRun;

  /// Riyadh is UTC+3 all year, with no daylight saving.
  static const Duration _riyadhOffset = Duration(hours: 3);

  /// Closes what is due as of [now]; returns how many months it closed.
  Future<Result<int>> call({required DateTime now}) async {
    final instant = now.toUtc();
    var closed = 0;
    while (closed < maxMonthsPerRun) {
      final nextResult = await _leagues.nextUnclosedMonth();
      if (nextResult is Err<DateTime?>) {
        return Result.err(nextResult.error);
      }
      final month = (nextResult as Ok<DateTime?>).value;
      if (month == null) {
        break;
      }
      final endsAt = H2hLeaguePolicy.monthEndOf(month).subtract(_riyadhOffset);
      if (instant.isBefore(endsAt.add(grace))) {
        break;
      }
      final monthResult = await _closeMonth(
        month: month,
        endsAt: endsAt,
        mayWait: instant.isBefore(endsAt.add(settleWait)),
      );
      if (monthResult is Err<bool>) {
        return Result.err(monthResult.error);
      }
      if (!(monthResult as Ok<bool>).value) {
        // Still waiting for results; later months wait behind it.
        break;
      }
      closed++;
    }
    return Result.ok(closed);
  }

  /// Judges [month]; Ok(false) when it must wait for results.
  Future<Result<bool>> _closeMonth({
    required DateTime month,
    required DateTime endsAt,
    required bool mayWait,
  }) async {
    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    final info = (infoResult as Ok<H2hMonthInfo?>).value;

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final rounds = (roundsResult as Ok<List<H2hRound>>).value;

    final groupsResult = await _leagues.groupsOf(month);
    if (groupsResult is Err<List<H2hGroupRef>>) {
      return Result.err(groupsResult.error);
    }
    final groups = (groupsResult as Ok<List<H2hGroupRef>>).value;

    final results = <H2hGroupResult>[];
    final eliteGroups = <H2hEliteGroup>[];
    final leagueOf = <UserId, H2hLeagueId>{};
    var members = 0;
    final sheets = <H2hLeagueId, H2hGroupSheet>{};
    final playedOf = <H2hLeagueId, List<H2hRoundRef>>{};
    for (final group in groups) {
      final sheetResult = await _sheets.sheetOf(
        leagueId: group.leagueId,
        rounds: rounds,
      );
      if (sheetResult is Err<H2hGroupSheet>) {
        return Result.err(sheetResult.error);
      }
      final sheet = (sheetResult as Ok<H2hGroupSheet>).value;
      final played = <H2hRoundRef>[];
      for (final round in rounds) {
        if (!round.locked || sheet.voidRounds.contains(round.number)) {
          continue;
        }
        if (!sheet.settledRounds.contains(round.number) && mayWait) {
          return const Result.ok(false);
        }
        played.add(round.ref);
      }
      sheets[group.leagueId] = sheet;
      playedOf[group.leagueId] = played;
    }
    // NK183: with a seat swap in the month, a group is judged on the
    // players who hold its seats at the end, each with his whole month.
    final book = sheets.values.any(h2hSheetHasSwaps)
        ? H2hMonthBook.of(groups: groups, sheets: sheets)
        : null;
    for (final group in groups) {
      final sheet = sheets[group.leagueId]!;
      final played = playedOf[group.leagueId]!;
      final placings = book != null
          ? book.placingsOf(group.leagueId, played)
          : H2hLeaguePolicy.order(
              H2hLeaguePolicy.table(
                capacity: group.capacity,
                members: sheet.members,
                rounds: played,
                scores: sheet.scores,
                turns: sheet.turns,
              ),
            );
      results.add(H2hGroupResult(division: group.division, placings: placings));
      eliteGroups.add(
        H2hEliteGroup(
          division: group.division,
          groupIndex: group.groupIndex,
          placings: placings,
        ),
      );
      final current = book != null ? h2hCurrentMembers(sheet) : sheet.members;
      for (final member in current) {
        leagueOf[member.userId] = group.leagueId;
      }
      members += current.length;
    }

    if (info == null || info.isPilot) {
      final marked = await _leagues.markClosed(
        monthStart: month,
        memberCount: members,
      );
      if (marked is Err<void>) {
        return Result.err(marked.error);
      }
      return const Result.ok(true);
    }

    var minActiveDays = H2hLeaguePolicy.minActiveDays;
    final controls = _controls;
    if (controls != null) {
      final settings = await controls.settings();
      if (settings is Err<H2hSettings>) {
        return Result.err(settings.error);
      }
      minActiveDays = (settings as Ok<H2hSettings>).value.minActiveDays;
    }

    final activeResult = await _sheets.activeDaysOf(month);
    if (activeResult is Err<Map<UserId, int>>) {
      return Result.err(activeResult.error);
    }
    final eligible = <UserId>{
      for (final entry in (activeResult as Ok<Map<UserId, int>>).value.entries)
        if (entry.value >= minActiveDays) entry.key,
    };

    // NK275: a month of the elite draw carries by the owner's rules of
    // 2026-11-14 (H2hEliteCarry); an older month by the ladder.
    final List<
      ({
        H2hPlacing placing,
        H2hDivision division,
        H2hDivision? nextDivision,
        H2hLeagueOutcome outcome,
        int? nextOrder,
      })
    >
    finishes;
    if (H2hLeaguePolicy.usesEliteDraw(month)) {
      final measured = await _commitmentOf(month, groups, sheets, playedOf);
      if (measured is Err<Map<UserId, H2hCommitment>>) {
        return Result.err(measured.error);
      }
      finishes = [
        for (final f in H2hEliteCarry.next(
          groups: eliteGroups,
          eligible: eligible,
          commitment: (measured as Ok<Map<UserId, H2hCommitment>>).value,
        ))
          (
            placing: f.placing,
            division: f.division,
            nextDivision: f.nextDivision,
            outcome: f.outcome,
            nextOrder: f.nextOrder,
          ),
      ];
    } else {
      finishes = [
        for (final f in H2hLeaguePolicy.monthEnd(
          groups: results,
          eligible: eligible,
          monthStart: month,
        ))
          (
            placing: f.placing,
            division: f.division,
            nextDivision: f.nextDivision,
            outcome: f.outcome,
            nextOrder: null,
          ),
      ];
    }
    // NK172_005
    for (final finish in finishes) {
      final standing = finish.placing.standing;
      final leagueId = leagueOf[standing.userId];
      if (leagueId == null) {
        continue;
      }
      final built = GamificationEvent.h2hLeagueFinished(
        id: _ids.newUuid(),
        userId: standing.userId,
        leagueId: leagueId,
        monthStart: month,
        division: finish.division,
        rank: finish.placing.rank,
        leaguePoints: standing.leaguePoints,
        points: standing.pointsFor,
        nextDivision: finish.nextDivision,
        outcome: finish.outcome,
        occurredAt: endsAt,
        nextOrder: finish.nextOrder,
      );
      if (built is Err<GamificationEvent>) {
        return Result.err(built.error);
      }
      final recorded = await _events.record(
        (built as Ok<GamificationEvent>).value,
      );
      if (recorded is Err<void>) {
        return Result.err(recorded.error);
      }
    }

    // After every event, never before: a closed month is never judged again.
    final marked = await _leagues.markClosed(
      monthStart: month,
      memberCount: members,
    );
    if (marked is Err<void>) {
      return Result.err(marked.error);
    }
    return const Result.ok(true);
  }

  /// What each player did in his own rounds of [month] (NK275): the
  /// played rounds of every seat he held, those he predicted nothing in,
  /// his predictions, exact scorelines and points on them, and the right
  /// outcomes read by [_outcomes] (none when it is not wired).
  Future<Result<Map<UserId, H2hCommitment>>> _commitmentOf(
    DateTime month,
    List<H2hGroupRef> groups,
    Map<H2hLeagueId, H2hGroupSheet> sheets,
    Map<H2hLeagueId, List<H2hRoundRef>> playedOf,
  ) async {
    var outcomes = const <UserId, int>{};
    final reader = _outcomes;
    if (reader != null) {
      final read = await reader.outcomesOf(month);
      if (read is Err<Map<UserId, int>>) {
        return Result.err(read.error);
      }
      outcomes = (read as Ok<Map<UserId, int>>).value;
    }
    final absent = <UserId, int>{};
    final predicted = <UserId, int>{};
    final exact = <UserId, int>{};
    final points = <UserId, int>{};
    for (final group in groups) {
      final sheet = sheets[group.leagueId];
      final played = playedOf[group.leagueId];
      if (sheet == null || played == null) {
        continue;
      }
      final scoreOf = <(UserId, int), H2hRoundScore>{
        for (final s in sheet.scores) (s.userId, s.round): s,
      };
      for (final member in sheet.members) {
        final u = member.userId;
        for (final round in played) {
          if (!member.activeIn(round.number)) {
            continue;
          }
          final score = scoreOf[(u, round.number)];
          absent[u] =
              (absent[u] ?? 0) + (score == null || !score.present ? 1 : 0);
          if (score != null) {
            predicted[u] = (predicted[u] ?? 0) + score.predictedCount;
            exact[u] = (exact[u] ?? 0) + score.exactCount;
            points[u] = (points[u] ?? 0) + score.points;
          }
        }
      }
    }
    return Result.ok(<UserId, H2hCommitment>{
      for (final u in absent.keys)
        u: H2hCommitment(
          absentRounds: absent[u] ?? 0,
          predicted: predicted[u] ?? 0,
          exact: exact[u] ?? 0,
          outcomes: outcomes[u] ?? 0,
          points: points[u] ?? 0,
        ),
    });
  }
}
