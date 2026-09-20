import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/ports/gamification_event_sink.dart';
import 'package:application/src/gamification/ports/weekly_league_closure_store.dart';
import 'package:application/src/gamification/ports/weekly_league_standings_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: judges the weekly-league weeks that have ended (P2-5).
///
/// For every group of an ended week it reads the standing
/// (`WeeklyLeagueStandingsReader`), judges it (`WeeklyLeaguePolicy.judge`)
/// and writes one `weekly_league_finished` event per member. The events ARE
/// the result: there is no results table. Once written they freeze the week
/// against a later result correction, and next week's tier is read from the
/// newest of them (`WeeklyLeagueRepository.lastFinishOf`).
///
/// **Which weeks.** The oldest unclosed week first, one after another, up to
/// [maxWeeksPerRun]. A week is due once [grace] has passed since it ended
/// (Monday 00:00 Riyadh); the grace keeps a result corrected just after
/// midnight from being frozen out. The week in progress is never due, and
/// because weeks are taken oldest first, the first week that is not due ends
/// the run.
///
/// **`occurred_at` is the end of the week, not the moment of the run.**
/// `lastFinishOf` takes the newest event by `occurred_at`. A late run, or a
/// catch-up over several missed weeks, must not let an older week look newer
/// than a later one, so every event of a week carries that week's own end.
///
/// **Idempotent and replayable.** Each event is keyed on the user and the
/// week, so replaying a week writes nothing new. The week is marked closed
/// only AFTER every event of every group was recorded: a failure half-way
/// leaves the week open, and the next run repeats it harmlessly. Marking
/// first would make a lost event permanent, because a closed week is never
/// judged again.
///
/// **A sink failure is not ignored here.** The event sink is tier-3 for the
/// acts that emit into it (a saved prediction must not fail because its
/// event row did). This is the one emitter for which the event IS the work,
/// so its error is returned and the week stays open.
///
/// **No points.** Promotion, relegation and first place pay nothing into the
/// ledger; the reward is the tier and the placing.
///
/// Never throws; returns a typed [Result] with the number of weeks closed.
final class CloseWeeklyLeague {
  /// Creates the use-case over its collaborators.
  const CloseWeeklyLeague({
    required WeeklyLeagueClosureStore closures,
    required WeeklyLeagueStandingsReader standings,
    required GamificationEventSink events,
    required IdGenerator idGenerator,
    this.grace = const Duration(hours: 3),
    this.maxWeeksPerRun = 8,
  }) : _closures = closures,
       _standings = standings,
       _events = events,
       _ids = idGenerator;

  final WeeklyLeagueClosureStore _closures;
  final WeeklyLeagueStandingsReader _standings;
  final GamificationEventSink _events;
  final IdGenerator _ids;

  /// How long a week must have been over before it is judged.
  final Duration grace;

  /// The most weeks a single run closes.
  final int maxWeeksPerRun;

  /// Riyadh is UTC+3 all year, with no daylight saving.
  static const Duration _riyadhOffset = Duration(hours: 3);

  /// Closes what is due as of [now]; returns how many weeks it closed.
  Future<Result<int>> call({required DateTime now}) async {
    final instant = now.toUtc();
    var closed = 0;

    while (closed < maxWeeksPerRun) {
      final nextResult = await _closures.nextUnclosedWeek();
      if (nextResult is Err<DateTime?>) {
        return Result.err(nextResult.error);
      }
      final week = (nextResult as Ok<DateTime?>).value;
      if (week == null) {
        break;
      }

      final endsAt = _weekEndsAt(week);
      if (instant.isBefore(endsAt.add(grace))) {
        // Oldest first: a week that is not over yet means nothing after it
        // is either.
        break;
      }

      final weekResult = await _closeWeek(week: week, endsAt: endsAt);
      if (weekResult is Err<void>) {
        return Result.err(weekResult.error);
      }
      closed++;
    }

    return Result.ok(closed);
  }

  /// Judges every group of [week], then marks the week closed.
  Future<Result<void>> _closeWeek({
    required DateTime week,
    required DateTime endsAt,
  }) async {
    final groupsResult = await _closures.groupsOf(week);
    if (groupsResult is Err<List<WeeklyLeagueGroupRef>>) {
      return Result.err(groupsResult.error);
    }
    final groups = (groupsResult as Ok<List<WeeklyLeagueGroupRef>>).value;

    var members = 0;
    for (final group in groups) {
      final entriesResult = await _standings.entriesOf(
        leagueId: group.leagueId,
        weekStart: week,
      );
      if (entriesResult is Err<List<WeeklyLeagueEntry>>) {
        return Result.err(entriesResult.error);
      }
      final entries = (entriesResult as Ok<List<WeeklyLeagueEntry>>).value;

      final placings = WeeklyLeaguePolicy.judge(
        tier: group.tier,
        entries: entries,
      );
      for (final placing in placings) {
        final built = GamificationEvent.weeklyLeagueFinished(
          id: _ids.newUuid(),
          userId: placing.entry.userId,
          leagueId: group.leagueId,
          weekStart: week,
          tier: group.tier,
          rank: placing.rank,
          points: placing.entry.points,
          outcome: placing.outcome,
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
        members++;
      }
    }

    // After every event, never before: see the class documentation.
    return _closures.markClosed(weekStart: week, memberCount: members);
  }

  /// The instant [weekStart]'s week ends: the Monday after it, 00:00 in
  /// Riyadh, as UTC.
  static DateTime _weekEndsAt(DateTime weekStart) =>
      WeeklyLeaguePolicy.weekEndOf(weekStart).subtract(_riyadhOffset);
}
