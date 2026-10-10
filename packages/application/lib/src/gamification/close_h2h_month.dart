import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/ports/gamification_event_sink.dart';
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
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
    this.grace = const Duration(hours: 3),
    this.settleWait = const Duration(days: 3),
    this.maxMonthsPerRun = 3,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _events = events,
       _ids = idGenerator,
       _controls = controls;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final GamificationEventSink _events;
  final IdGenerator _ids;
  final H2hControlStore? _controls;

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
    final leagueOf = <UserId, H2hLeagueId>{};
    var members = 0;
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
      final standings = H2hLeaguePolicy.table(
        capacity: group.capacity,
        members: sheet.members,
        rounds: played,
        scores: sheet.scores,
      );
      results.add(
        H2hGroupResult(
          division: group.division,
          placings: H2hLeaguePolicy.order(standings),
        ),
      );
      for (final member in sheet.members) {
        leagueOf[member.userId] = group.leagueId;
      }
      members += sheet.members.length;
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

    final finishes = H2hLeaguePolicy.monthEnd(
      groups: results,
      eligible: eligible,
    );
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
}
