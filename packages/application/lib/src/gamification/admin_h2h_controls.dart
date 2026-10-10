/// The admin's desk for the head-to-head league (migrations 0100/0101):
/// the settings, the days kept from automatic approval, late seats, the
/// month report, the admin log, and a manual run of the league's jobs.
///
/// Every rule stays where it was: the store and the database refuse what
/// 0100/0101 refuse, and the jobs run exactly as the scheduler runs them.
/// Every change an admin makes here is written to the admin log. Nothing
/// here reads anybody's prediction or touches a point.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/admin_h2h_groups.dart';
import 'package:application/src/gamification/close_h2h_month.dart';
import 'package:application/src/gamification/draw_h2h_month.dart';
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_month_report_reader.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/gamification/run_h2h_rounds.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One day of a month as the controls show it: a day with matches that has
/// not started yet, or a day kept from automatic approval.
final class H2hControlDay {
  /// Creates a day.
  const H2hControlDay({
    required this.fixtures,
    required this.excluded,
    required this.round,
  });

  /// The day, its fixture count and its first kickoff.
  final H2hDayFixtures fixtures;

  /// Whether the system must not approve it by itself.
  final bool excluded;

  /// The round the day already is, or null.
  final int? round;
}

/// The admin's controls of one month.
final class H2hControlsView {
  /// Creates the reading.
  const H2hControlsView({
    required this.monthStart,
    required this.settings,
    required this.days,
    required this.actions,
    required this.names,
  });

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// The settings as they stand.
  final H2hSettings settings;

  /// The month's days from today on, in date order.
  final List<H2hControlDay> days;

  /// The latest lines of the admin log, newest first.
  final List<H2hAdminAction> actions;

  /// The display names of the admins named in [actions] and [settings].
  final Map<UserId, String> names;
}

/// What one manual run of the league's jobs did.
final class H2hJobsRun {
  /// Creates a report.
  const H2hJobsRun({
    required this.approved,
    required this.locked,
    required this.closedMonths,
    required this.drawnSeats,
  });

  /// Rounds the system approved.
  final int approved;

  /// Rounds whose fixture list was frozen.
  final int locked;

  /// Months judged.
  final int closedMonths;

  /// Seats handed out by a draw.
  final int drawnSeats;
}

/// The admin's controls over the head-to-head league. Admin only; every
/// method never throws and returns a typed [Result].
final class AdminH2hControls {
  /// Creates the controls over their collaborators.
  const AdminH2hControls({
    required H2hControlStore controls,
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hMonthReportReader reports,
    required WeeklyLeagueProfileReader profiles,
    required RunH2hRounds runRounds,
    required CloseH2hMonth closeMonth,
    required DrawH2hMonth drawMonth,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _controls = controls,
       _leagues = leagues,
       _rounds = rounds,
       _reports = reports,
       _profiles = profiles,
       _runRounds = runRounds,
       _closeMonth = closeMonth,
       _drawMonth = drawMonth,
       _ids = idGenerator,
       _clock = clock;

  final H2hControlStore _controls;
  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hMonthReportReader _reports;
  final WeeklyLeagueProfileReader _profiles;
  final RunH2hRounds _runRounds;
  final CloseH2hMonth _closeMonth;
  final DrawH2hMonth _drawMonth;
  final IdGenerator _ids;
  final Clock _clock;

  /// How many lines of the admin log [view] reads.
  static const int actionsShown = 30;

  /// The settings, the days of the month containing [day] (today's month
  /// when null) from today on, and the latest lines of the admin log.
  Future<Result<H2hControlsView>> view({
    required AuthenticatedUser principal,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final now = _clock.nowUtc();
    final today = riyadhDayOf(now);
    final month = H2hLeaguePolicy.monthStartOf(day ?? today);
    final last = H2hLeaguePolicy.monthEndOf(
      month,
    ).subtract(const Duration(days: 1));
    final from = month.isAfter(today) ? month : today;

    final settingsResult = await _controls.settings();
    if (settingsResult is Err<H2hSettings>) {
      return Result.err(settingsResult.error);
    }
    final settings = (settingsResult as Ok<H2hSettings>).value;

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final roundOf = <DateTime, int>{
      for (final round in (roundsResult as Ok<List<H2hRound>>).value)
        round.day: round.number,
    };

    final days = <DateTime, H2hControlDay>{};
    if (!from.isAfter(last)) {
      final excludedResult = await _controls.excludedDays(
        from: from,
        through: last,
      );
      if (excludedResult is Err<Set<DateTime>>) {
        return Result.err(excludedResult.error);
      }
      final excluded = (excludedResult as Ok<Set<DateTime>>).value;

      final daysResult = await _rounds.daysBetween(from: from, through: last);
      if (daysResult is Err<List<H2hDayFixtures>>) {
        return Result.err(daysResult.error);
      }
      for (final fixtures in (daysResult as Ok<List<H2hDayFixtures>>).value) {
        final firstKickoff = fixtures.firstKickoff;
        final started = firstKickoff == null || !now.isBefore(firstKickoff);
        if (started && !excluded.contains(fixtures.day)) {
          continue;
        }
        days[fixtures.day] = H2hControlDay(
          fixtures: fixtures,
          excluded: excluded.contains(fixtures.day),
          round: roundOf[fixtures.day],
        );
      }
      for (final excludedDay in excluded) {
        if (days.containsKey(excludedDay)) {
          continue;
        }
        final fixturesResult = await _rounds.dayFixtures(excludedDay);
        if (fixturesResult is Err<H2hDayFixtures>) {
          return Result.err(fixturesResult.error);
        }
        days[excludedDay] = H2hControlDay(
          fixtures: (fixturesResult as Ok<H2hDayFixtures>).value,
          excluded: true,
          round: roundOf[excludedDay],
        );
      }
    }
    final ordered = days.values.toList()
      ..sort((a, b) => a.fixtures.day.compareTo(b.fixtures.day));

    final actionsResult = await _controls.recentActions(actionsShown);
    if (actionsResult is Err<List<H2hAdminAction>>) {
      return Result.err(actionsResult.error);
    }
    final actions = (actionsResult as Ok<List<H2hAdminAction>>).value;

    final named = <UserId>{
      for (final action in actions)
        if (action.actor != null) action.actor!,
      if (settings.updatedBy != null) settings.updatedBy!,
    };
    final names = <UserId, String>{};
    if (named.isNotEmpty) {
      final profilesResult = await _profiles.profilesOf(named.toList());
      if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
        return Result.err(profilesResult.error);
      }
      final profiles =
          (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
      for (final entry in profiles.entries) {
        names[entry.key] = entry.value.displayName;
      }
    }

    return Result.ok(
      H2hControlsView(
        monthStart: month,
        settings: settings,
        days: List<H2hControlDay>.unmodifiable(ordered),
        actions: actions,
        names: names,
      ),
    );
  }

  /// Replaces the settings. The lead is 1 to 24 hours and the active days
  /// 1 to 28 (`h2h.settings_out_of_range` otherwise). Answers the settings
  /// as stored.
  Future<Result<H2hSettings>> saveSettings({
    required AuthenticatedUser principal,
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (leadHours < H2hSettings.minLeadHours ||
        leadHours > H2hSettings.maxLeadHours ||
        minActiveDays < H2hSettings.minActiveDaysFloor ||
        minActiveDays > H2hSettings.minActiveDaysCeiling) {
      return const Result.err(
        AppError.validation(
          'h2h.settings_out_of_range',
          'The lead must be 1 to 24 hours and the active days 1 to 28',
        ),
      );
    }
    final saved = await _controls.saveSettings(
      autoApprove: autoApprove,
      leadHours: leadHours,
      minActiveDays: minActiveDays,
      by: principal.userId,
    );
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }
    // The log is a record, not a condition: the settings stand.
    await _controls.record(
      id: _ids.newUuid(),
      action: H2hAdminActionKind.settingsSaved,
      by: principal.userId,
      detail: {
        'auto_approve': autoApprove,
        'lead_hours': leadHours,
        'min_active_days': minActiveDays,
      },
    );
    return _controls.settings();
  }

  /// Keeps the Riyadh [day] from automatic approval ([excluded] true) or
  /// lifts that. A day before today is `h2h.day_past`. Answers whether
  /// anything changed; only a change is written to the log.
  Future<Result<bool>> setDayExcluded({
    required AuthenticatedUser principal,
    required DateTime day,
    required bool excluded,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final theDay = DateTime.utc(day.year, day.month, day.day);
    if (theDay.isBefore(riyadhDayOf(_clock.nowUtc()))) {
      return const Result.err(
        AppError.validation(
          'h2h.day_past',
          'A day that has passed cannot be changed',
        ),
      );
    }
    final changed = excluded
        ? await _controls.exclude(day: theDay, by: principal.userId)
        : await _controls.include(theDay);
    if (changed is Err<bool>) {
      return changed;
    }
    if ((changed as Ok<bool>).value) {
      await _controls.record(
        id: _ids.newUuid(),
        action: excluded
            ? H2hAdminActionKind.dayExcluded
            : H2hAdminActionKind.dayIncluded,
        by: principal.userId,
        detail: {'day': _isoDay(theDay)},
      );
    }
    return changed;
  }

  /// Seats [userId] late in the empty [slot] of group [leagueId] of the
  /// month containing [day] (today's month when null). The month must be
  /// drawn (`h2h.month_not_drawn`) and not judged (`h2h.month_closed`), the
  /// group must be one of its own (`h2h.group_unknown`), the slot inside
  /// the group (`h2h.seat_outside_group`) and the player not seated yet
  /// (`h2h.player_seated`); the database refuses a taken slot
  /// (`h2h.seat_taken`) and an unknown player (`h2h.player_unknown`).
  Future<Result<void>> addSeat({
    required AuthenticatedUser principal,
    required H2hLeagueId leagueId,
    required UserId userId,
    required int slot,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final month = H2hLeaguePolicy.monthStartOf(
      day ?? riyadhDayOf(_clock.nowUtc()),
    );

    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    if ((infoResult as Ok<H2hMonthInfo?>).value == null) {
      return const Result.err(
        AppError.invariant('h2h.month_not_drawn', 'The month was not drawn'),
      );
    }
    final closedResult = await _leagues.isClosed(month);
    if (closedResult is Err<bool>) {
      return Result.err(closedResult.error);
    }
    if ((closedResult as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant('h2h.month_closed', 'The month was already judged'),
      );
    }

    final refsResult = await _leagues.groupsOf(month);
    if (refsResult is Err<List<H2hGroupRef>>) {
      return Result.err(refsResult.error);
    }
    H2hGroupRef? ref;
    for (final candidate in (refsResult as Ok<List<H2hGroupRef>>).value) {
      if (candidate.leagueId == leagueId) {
        ref = candidate;
        break;
      }
    }
    if (ref == null) {
      return const Result.err(
        AppError.invariant('h2h.group_unknown', 'The month has no such group'),
      );
    }
    if (slot < 0 || slot >= ref.capacity) {
      return const Result.err(
        AppError.invariant(
          'h2h.seat_outside_group',
          'The seat is outside the group',
        ),
      );
    }

    final seatResult = await _leagues.seatFor(
      userId: userId,
      monthStart: month,
    );
    if (seatResult is Err<H2hSeat?>) {
      return Result.err(seatResult.error);
    }
    if ((seatResult as Ok<H2hSeat?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'h2h.player_seated',
          'The player already has a seat this month',
        ),
      );
    }

    final added = await _controls.addSeat(
      leagueId: leagueId,
      monthStart: month,
      userId: userId,
      slot: slot,
    );
    if (added is Err<void>) {
      return added;
    }
    await _controls.record(
      id: _ids.newUuid(),
      action: H2hAdminActionKind.seatAdded,
      by: principal.userId,
      detail: {
        'month': _isoDay(month),
        'league_id': leagueId.value,
        'user_id': userId.value,
        'slot': slot,
      },
    );
    return const Result.ok(null);
  }

  /// How the month containing [day] (today's month when null) went: its
  /// draw, its groups and its closing.
  Future<Result<H2hMonthReport>> report({
    required AuthenticatedUser principal,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _reports.reportOf(
      H2hLeaguePolicy.monthStartOf(day ?? riyadhDayOf(_clock.nowUtc())),
    );
  }

  /// Runs the league's jobs now, as the scheduler runs them every five
  /// minutes: rounds (approve and lock), then the month closing, then the
  /// draw. Each is idempotent. All three run; the first failure is
  /// answered, and only a full run is written to the log.
  Future<Result<H2hJobsRun>> runJobs({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final now = _clock.nowUtc();
    final rounds = await _runRounds(now: now);
    final closed = await _closeMonth(now: now);
    final drawn = await _drawMonth(now: now);
    if (rounds is Err<H2hRoundsRun>) {
      return Result.err(rounds.error);
    }
    if (closed is Err<int>) {
      return Result.err(closed.error);
    }
    if (drawn is Err<int>) {
      return Result.err(drawn.error);
    }
    final roundsRun = (rounds as Ok<H2hRoundsRun>).value;
    final run = H2hJobsRun(
      approved: roundsRun.approved,
      locked: roundsRun.locked,
      closedMonths: (closed as Ok<int>).value,
      drawnSeats: (drawn as Ok<int>).value,
    );
    await _controls.record(
      id: _ids.newUuid(),
      action: H2hAdminActionKind.jobsRun,
      by: principal.userId,
      detail: {
        'approved': run.approved,
        'locked': run.locked,
        'closed_months': run.closedMonths,
        'drawn_seats': run.drawnSeats,
      },
    );
    return Result.ok(run);
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// Every admin use-case of the head-to-head league beyond the rounds, in
/// one place for the composition root: the month's groups, a round of one
/// group, one player's month, and the controls.
final class H2hAdminDesk {
  /// Creates the desk.
  const H2hAdminDesk({
    required this.groups,
    required this.groupRound,
    required this.player,
    required this.controls,
  });

  /// Every group of a month with its table (`GET /admin/h2h/groups`).
  final AdminGetH2hGroups groups;

  /// Every match of a round in one group
  /// (`GET /admin/h2h/groups/{id}/rounds/{n}`).
  final AdminGetH2hGroupRound groupRound;

  /// One player's month as they see it (`GET /admin/h2h/players/{id}`).
  final AdminGetH2hPlayer player;

  /// The settings, days, seats, report, log and jobs.
  final AdminH2hControls controls;
}
