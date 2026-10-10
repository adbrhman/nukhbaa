/// Use-case: every match of one round in the caller's head-to-head group
/// (migration 0100) -- who meets whom, each side's points, and who the
/// round shows ahead.
library;

import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:application/src/gamification/h2h_round_phase.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Who a round shows ahead in one match.
enum H2hPairWinner {
  /// The first member.
  home('home'),

  /// The second member, or the group average.
  away('away'),

  /// Level.
  draw('draw'),

  /// Neither: a settled round both members lost (neither predicted).
  none('none');

  const H2hPairWinner(this.wireName);

  /// The value sent to clients.
  final String wireName;
}

/// One match of the round.
final class H2hGroupPair {
  /// Creates a pair.
  const H2hGroupPair({
    required this.home,
    required this.away,
    required this.homePoints,
    required this.awayPoints,
    required this.winner,
  });

  /// The first member: the caller, when the caller plays this match.
  final UserId home;

  /// The second member, or null when [home] plays the group average.
  final UserId? away;

  /// The first member's stored points in the round; null before it starts
  /// and when it is void.
  final int? homePoints;

  /// The second member's stored points, or the group average.
  final double? awayPoints;

  /// Who the round shows ahead; null before it starts and when void.
  final H2hPairWinner? winner;
}

/// Every match of one round of the caller's group.
final class MyH2hGroupRound {
  /// Creates a reading.
  const MyH2hGroupRound({
    required this.round,
    required this.phase,
    required this.readerId,
    required this.pairs,
    required this.profiles,
  });

  /// The round.
  final H2hRound round;

  /// Its phase in the month.
  final H2hRoundPhase phase;

  /// The user this reading was made for.
  final UserId readerId;

  /// The matches, the caller's first, then by seat.
  final List<H2hGroupPair> pairs;

  /// The name and picture version of each member.
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;
}

/// Reads every match of round [round] of the caller's group.
///
/// **It reads; it does not score.** Points are the stored scores the table
/// is built from (`H2hSheetReader`), and the pairs are
/// `H2hLeaguePolicy.opponentSlot`'s.
///
/// **Nobody's predictions, and nobody's absence, before it is over.** No
/// pick is read here at all. A live round shows who is ahead by points
/// alone: the policy's live result also weighs whether a member predicted,
/// which would tell about picks on fixtures not kicked off. A settled
/// round shows the policy's result, the one the table counts.
///
/// Only the caller's own group is read. Never throws; a caller with no seat
/// gets `h2h.not_seated`, a round the month does not have
/// `h2h.round_unknown`.
final class GetMyH2hGroupRound {
  /// Creates the use-case over its collaborators.
  const GetMyH2hGroupRound({
    required GetMyH2hLeague league,
    required H2hSheetReader sheets,
  }) : _league = league,
       _sheets = sheets;

  final GetMyH2hLeague _league;
  final H2hSheetReader _sheets;

  /// Reads round [round] of [principal]'s group.
  Future<Result<MyH2hGroupRound>> call({
    required AuthenticatedUser principal,
    required int round,
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
    final seat = league.seat;
    if (league.state != H2hLeagueState.open || seat == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.not_seated',
          'The caller holds no seat this month',
        ),
      );
    }
    MyH2hRound? view;
    for (final candidate in league.rounds) {
      if (candidate.round.number == round) {
        view = candidate;
        break;
      }
    }
    if (view == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_unknown',
          'The month has no round with this number',
        ),
      );
    }

    final sheetResult = await _sheets.sheetOf(
      leagueId: seat.leagueId,
      rounds: [for (final r in league.rounds) r.round],
    );
    if (sheetResult is Err<H2hGroupSheet>) {
      return Result.err(sheetResult.error);
    }
    final sheet = (sheetResult as Ok<H2hGroupSheet>).value;

    final members = List<H2hMember>.of(sheet.members)
      ..sort((a, b) => a.slot.compareTo(b.slot));
    final bySlot = <int, H2hMember>{for (final m in members) m.slot: m};

    final started =
        view.status == H2hRoundStatus.live ||
        view.status == H2hRoundStatus.settled;
    final matchOf = <UserId, H2hMatch>{};
    if (started) {
      for (final standing in H2hLeaguePolicy.table(
        capacity: seat.capacity,
        members: members,
        rounds: [view.round.ref],
        scores: sheet.scores,
      )) {
        if (standing.matches.isNotEmpty) {
          matchOf[standing.userId] = standing.matches.single;
        }
      }
    }

    final reader = league.readerId;
    final paired = <UserId>{};
    final mine = <H2hGroupPair>[];
    final others = <H2hGroupPair>[];
    for (final member in members) {
      if (paired.contains(member.userId)) {
        continue;
      }
      final candidate =
          bySlot[H2hLeaguePolicy.opponentSlot(
            slot: member.slot,
            round: round,
            capacity: seat.capacity,
          )];
      final opponent =
          candidate != null &&
              candidate.userId != member.userId &&
              !paired.contains(candidate.userId)
          ? candidate
          : null;
      paired.add(member.userId);
      if (opponent != null) {
        paired.add(opponent.userId);
      }
      // The caller always on the first side of their own match.
      final flip = opponent != null && opponent.userId == reader;
      final home = flip ? reader : member.userId;
      final away = opponent == null
          ? null
          : (flip ? member.userId : opponent.userId);
      final pair = _pair(
        home: home,
        away: away,
        settled: view.status == H2hRoundStatus.settled,
        matchOf: matchOf,
      );
      if (home == reader || away == reader) {
        mine.add(pair);
      } else {
        others.add(pair);
      }
    }

    return Result.ok(
      MyH2hGroupRound(
        round: view.round,
        phase: h2hRoundPhasesOf(league.rounds)[view.round.number]!,
        readerId: reader,
        pairs: List<H2hGroupPair>.unmodifiable([...mine, ...others]),
        profiles: league.profiles,
      ),
    );
  }

  static H2hGroupPair _pair({
    required UserId home,
    required UserId? away,
    required bool settled,
    required Map<UserId, H2hMatch> matchOf,
  }) {
    final homeMatch = matchOf[home];
    if (homeMatch == null) {
      return H2hGroupPair(
        home: home,
        away: away,
        homePoints: null,
        awayPoints: null,
        winner: null,
      );
    }
    final awayMatch = away == null ? null : matchOf[away];
    final homePoints = homeMatch.points;
    final awayPoints = awayMatch?.points.toDouble() ?? homeMatch.opponentPoints;

    final H2hPairWinner winner;
    if (!settled) {
      winner = _byPoints(homePoints.toDouble(), awayPoints);
    } else if (awayMatch == null) {
      winner = switch (homeMatch.result) {
        H2hMatchResult.win => H2hPairWinner.home,
        H2hMatchResult.loss => H2hPairWinner.away,
        H2hMatchResult.draw => H2hPairWinner.draw,
      };
    } else if (homeMatch.result == H2hMatchResult.win) {
      winner = H2hPairWinner.home;
    } else if (awayMatch.result == H2hMatchResult.win) {
      winner = H2hPairWinner.away;
    } else if (homeMatch.result == H2hMatchResult.draw) {
      winner = H2hPairWinner.draw;
    } else {
      winner = H2hPairWinner.none;
    }
    return H2hGroupPair(
      home: home,
      away: away,
      homePoints: homePoints,
      awayPoints: awayPoints,
      winner: winner,
    );
  }

  static H2hPairWinner _byPoints(double home, double away) {
    if (home > away) {
      return H2hPairWinner.home;
    }
    if (home < away) {
      return H2hPairWinner.away;
    }
    return H2hPairWinner.draw;
  }
}
