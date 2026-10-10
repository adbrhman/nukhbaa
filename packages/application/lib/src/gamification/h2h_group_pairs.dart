/// Who meets whom in one round of a head-to-head group, and how the round
/// stands for each pair (migration 0100). Pure: no port, no clock.
library;

import 'package:application/src/gamification/get_my_h2h_group_round.dart';
import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:domain/domain.dart';

/// Every pair of round [number] in a group of [members] seated in a
/// round-robin of [capacity], with each side's stored points from [scores].
///
/// [status] is the round's state from the server (`H2hRoundStatus`): a
/// round not started or void carries no points. A live round shows who is
/// ahead by points alone; a settled one, the policy's result -- the same
/// rules as [GetMyH2hGroupRound]. When [first] is a member, that member's
/// match comes first and on its first side; the rest follow by seat.
List<H2hGroupPair> h2hGroupPairs({
  required List<H2hMember> members,
  required int capacity,
  required H2hRoundRef round,
  required H2hRoundStatus status,
  required List<H2hRoundScore> scores,
  UserId? first,
}) {
  final ordered = List<H2hMember>.of(members)
    ..sort((a, b) => a.slot.compareTo(b.slot));
  final bySlot = <int, H2hMember>{for (final m in ordered) m.slot: m};

  final started =
      status == H2hRoundStatus.live || status == H2hRoundStatus.settled;
  final matchOf = <UserId, H2hMatch>{};
  if (started) {
    for (final standing in H2hLeaguePolicy.table(
      capacity: capacity,
      members: ordered,
      rounds: [round],
      scores: scores,
    )) {
      if (standing.matches.isNotEmpty) {
        matchOf[standing.userId] = standing.matches.single;
      }
    }
  }

  final paired = <UserId>{};
  final lead = <H2hGroupPair>[];
  final rest = <H2hGroupPair>[];
  for (final member in ordered) {
    if (paired.contains(member.userId)) {
      continue;
    }
    final candidate =
        bySlot[H2hLeaguePolicy.opponentSlot(
          slot: member.slot,
          round: round.number,
          capacity: capacity,
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
    final UserId home;
    final UserId? away;
    if (opponent != null && first != null && opponent.userId == first) {
      home = opponent.userId;
      away = member.userId;
    } else {
      home = member.userId;
      away = opponent?.userId;
    }
    final pair = _pair(
      home: home,
      away: away,
      settled: status == H2hRoundStatus.settled,
      matchOf: matchOf,
    );
    if (first != null && (home == first || away == first)) {
      lead.add(pair);
    } else {
      rest.add(pair);
    }
  }
  return List<H2hGroupPair>.unmodifiable([...lead, ...rest]);
}

H2hGroupPair _pair({
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
    final mine = homePoints.toDouble();
    winner = mine > awayPoints
        ? H2hPairWinner.home
        : (mine < awayPoints ? H2hPairWinner.away : H2hPairWinner.draw);
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
