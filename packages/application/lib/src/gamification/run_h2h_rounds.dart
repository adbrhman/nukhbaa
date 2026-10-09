import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/approve_h2h_round.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one run of [RunH2hRounds] did.
final class H2hRoundsRun {
  /// Creates a report.
  const H2hRoundsRun({required this.approved, required this.locked});

  /// Rounds the system approved.
  final int approved;

  /// Rounds whose fixture list was frozen.
  final int locked;
}

/// Use-case: the scheduler's round keeping (migration 0100).
///
/// **Approve.** A day of six fixtures or more that no admin approved becomes
/// the next round by itself once its first kickoff is within
/// `H2hLeaguePolicy.autoApproveLead` (24 hours), so a forgotten day is not a
/// lost round. Only today and tomorrow are looked at: fixtures are known two
/// days ahead. A fill day (five fixtures) is never approved here. Before the
/// league opens, only a drawn (pilot) month gets rounds.
///
/// **Lock.** A round whose day's first match kicked off has its fixture list
/// frozen. A round whose day passed with no fixture left is frozen empty,
/// which voids it.
///
/// Never throws; a failure is returned and the next run repeats the work
/// harmlessly (approval refuses a day already taken; locking is idempotent).
final class RunH2hRounds {
  /// Creates the use-case over its collaborators.
  const RunH2hRounds({
    required H2hRoundStore rounds,
    required H2hLeagueStore leagues,
    required IdGenerator idGenerator,
  }) : _rounds = rounds,
       _leagues = leagues,
       _ids = idGenerator;

  final H2hRoundStore _rounds;
  final H2hLeagueStore _leagues;
  final IdGenerator _ids;

  /// Approves and locks what is due as of [now].
  Future<Result<H2hRoundsRun>> call({required DateTime now}) async {
    final instant = now.toUtc();
    final today = riyadhDayOf(instant);
    var approved = 0;
    var locked = 0;

    for (final day in [today, today.add(const Duration(days: 1))]) {
      final open = await _monthIsOpen(H2hLeaguePolicy.monthStartOf(day));
      if (open is Err<bool>) {
        return Result.err(open.error);
      }
      if (!(open as Ok<bool>).value) {
        continue;
      }
      final due = await _dueForApproval(day, instant);
      if (due is Err<bool>) {
        return Result.err(due.error);
      }
      if (!(due as Ok<bool>).value) {
        continue;
      }
      final result = await ApproveH2hRound.approveDay(
        rounds: _rounds,
        ids: _ids,
        now: instant,
        day: day,
        approvedBy: null,
      );
      if (result is Ok<H2hRound>) {
        approved++;
      } else if (result is Err<H2hRound> &&
          result.error.kind == ErrorKind.transient) {
        return Result.err(result.error);
      }
    }

    final months = <DateTime>{
      H2hLeaguePolicy.monthStartOf(today.subtract(const Duration(days: 1))),
      H2hLeaguePolicy.monthStartOf(today),
    };
    for (final month in months) {
      final listResult = await _rounds.roundsOf(month);
      if (listResult is Err<List<H2hRound>>) {
        return Result.err(listResult.error);
      }
      for (final round in (listResult as Ok<List<H2hRound>>).value) {
        if (round.locked) {
          continue;
        }
        final fixturesResult = await _rounds.dayFixtures(round.day);
        if (fixturesResult is Err<H2hDayFixtures>) {
          return Result.err(fixturesResult.error);
        }
        final firstKickoff =
            (fixturesResult as Ok<H2hDayFixtures>).value.firstKickoff;
        final started = firstKickoff != null && !instant.isBefore(firstKickoff);
        final passed = round.day.isBefore(today);
        if (!started && !passed) {
          continue;
        }
        final lockResult = await _rounds.lock(
          roundId: round.id,
          day: round.day,
        );
        if (lockResult is Err<int>) {
          return Result.err(lockResult.error);
        }
        locked++;
      }
    }

    return Result.ok(H2hRoundsRun(approved: approved, locked: locked));
  }

  /// A public month always takes rounds; before the league opens, only a
  /// month that was drawn (the pilot) does.
  Future<Result<bool>> _monthIsOpen(DateTime month) async {
    if (!month.isBefore(H2hLeaguePolicy.firstMonth)) {
      return const Result.ok(true);
    }
    final info = await _leagues.monthOf(month);
    return switch (info) {
      Err<H2hMonthInfo?>(:final error) => Result.err(error),
      Ok<H2hMonthInfo?>(:final value) => Result.ok(value != null),
    };
  }

  /// Whether [day] is a regular day, not approved yet, whose first kickoff
  /// is ahead of [now] but within the lead.
  Future<Result<bool>> _dueForApproval(DateTime day, DateTime now) async {
    final fixturesResult = await _rounds.dayFixtures(day);
    if (fixturesResult is Err<H2hDayFixtures>) {
      return Result.err(fixturesResult.error);
    }
    final fixtures = (fixturesResult as Ok<H2hDayFixtures>).value;
    final firstKickoff = fixtures.firstKickoff;
    if (firstKickoff == null || !now.isBefore(firstKickoff)) {
      return const Result.ok(false);
    }
    if (firstKickoff.difference(now) > H2hLeaguePolicy.autoApproveLead) {
      return const Result.ok(false);
    }
    if (H2hLeaguePolicy.roundKindOf(fixtures.fixtureCount) !=
        H2hRoundKind.regular) {
      return const Result.ok(false);
    }
    final listResult = await _rounds.roundsOf(
      H2hLeaguePolicy.monthStartOf(day),
    );
    if (listResult is Err<List<H2hRound>>) {
      return Result.err(listResult.error);
    }
    final list = (listResult as Ok<List<H2hRound>>).value;
    return Result.ok(list.isEmpty || day.isAfter(list.last.day));
  }
}
