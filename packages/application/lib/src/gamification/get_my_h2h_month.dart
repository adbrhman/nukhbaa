/// Use-case: the caller's head-to-head month as the screen shows it
/// (migration 0100) -- the group reading plus each round's phase, its first
/// kickoff and the days left in the month.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:application/src/gamification/h2h_round_phase.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The caller's month with what the screen needs around it.
final class MyH2hMonth {
  /// Creates a reading.
  const MyH2hMonth({
    required this.league,
    required this.phases,
    required this.results,
    required this.firstKickoffs,
    required this.daysLeft,
  });

  /// The group reading, exactly as [GetMyH2hLeague] made it. Its live
  /// matches carry the policy's result, which weighs whether the opponent
  /// predicted at all: what a client is told is [results], never that.
  final MyH2hLeague league;

  /// Each round's phase, keyed by round number.
  final Map<int, H2hRoundPhase> phases;

  /// The result each round shows (`h2hShownResultOf`), keyed by round
  /// number; a round that shows none is absent.
  final Map<int, H2hMatchResult> results;

  /// When each round's day kicks off first (UTC), keyed by round number;
  /// a round whose day holds no visible fixture is absent.
  final Map<int, DateTime> firstKickoffs;

  /// Whole Riyadh days of the month after today, never negative.
  final int daysLeft;
}

/// Reads the caller's month for the screen.
///
/// **It adds; it does not rank or score.** The table, the matches and the
/// zones are [GetMyH2hLeague]'s. The phases come from the server's round
/// state (`h2hRoundPhasesOf`), and the first kickoffs from the fixtures of
/// each round's day as the round store reads them.
///
/// Never throws; returns a typed [Result].
final class GetMyH2hMonth {
  /// Creates the use-case over its collaborators.
  const GetMyH2hMonth({
    required GetMyH2hLeague league,
    required H2hRoundStore rounds,
    required Clock clock,
  }) : _league = league,
       _rounds = rounds,
       _clock = clock;

  final GetMyH2hLeague _league;
  final H2hRoundStore _rounds;
  final Clock _clock;

  /// Reads [principal]'s month.
  Future<Result<MyH2hMonth>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final leagueResult = await _league(principal: principal);
    if (leagueResult is Err<MyH2hLeague>) {
      return Result.err(leagueResult.error);
    }
    final league = (leagueResult as Ok<MyH2hLeague>).value;

    final firstKickoffs = <int, DateTime>{};
    if (league.rounds.isNotEmpty) {
      var from = league.rounds.first.round.day;
      var through = from;
      for (final view in league.rounds) {
        final day = view.round.day;
        if (day.isBefore(from)) {
          from = day;
        }
        if (day.isAfter(through)) {
          through = day;
        }
      }
      final daysResult = await _rounds.daysBetween(
        from: from,
        through: through,
      );
      if (daysResult is Err<List<H2hDayFixtures>>) {
        return Result.err(daysResult.error);
      }
      final byDay = <DateTime, DateTime>{};
      for (final day in (daysResult as Ok<List<H2hDayFixtures>>).value) {
        final first = day.firstKickoff;
        if (first != null) {
          byDay[day.day] = first.toUtc();
        }
      }
      for (final view in league.rounds) {
        final kickoff = byDay[view.round.day];
        if (kickoff != null) {
          firstKickoffs[view.round.number] = kickoff;
        }
      }
    }

    return Result.ok(
      MyH2hMonth(
        league: league,
        phases: h2hRoundPhasesOf(league.rounds),
        results: {
          for (final view in league.rounds)
            if (h2hShownResultOf(view) case final shown?)
              view.round.number: shown,
        },
        firstKickoffs: firstKickoffs,
        daysLeft: daysLeftIn(
          monthStart: league.monthStart,
          today: riyadhDayOf(_clock.nowUtc()),
        ),
      ),
    );
  }

  /// Whole days of the month opened by [monthStart] after [today] (both UTC
  /// midnights of Riyadh days); 0 on its last day and after it.
  static int daysLeftIn({
    required DateTime monthStart,
    required DateTime today,
  }) {
    final end = H2hLeaguePolicy.monthEndOf(monthStart);
    final left = end.difference(today).inDays - 1;
    return left < 0 ? 0 : left;
  }
}
