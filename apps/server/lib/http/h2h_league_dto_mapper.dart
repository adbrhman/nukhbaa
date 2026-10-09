/// Projects the head-to-head league readings onto their versioned wire
/// shapes (API ADR, Section 4), in one place (migration 0100).
///
/// Integrity boundary (Axioms 2/5): every number here is server-produced.
/// The table, the matches, the zones and the round list are echoed exactly
/// as the policy and the stores produced them; the client never sends a
/// point, a rank or a result.
///
/// Days cross the wire as plain `YYYY-MM-DD` Riyadh dates; the one instant
/// (a candidate day's first kickoff) as ISO-8601 UTC.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/http/avatar_url.dart';

/// How many recent results a table line carries, oldest first.
const int h2hFormLength = 5;

/// The caller's month as `GET /me/h2h-league` sends it.
MyH2hLeagueDto myH2hLeagueToDto(MyH2hLeague league) {
  final seat = league.seat;
  return MyH2hLeagueDto(
    state: h2hStateWireName(league.state),
    monthStart: isoDayOf(league.monthStart),
    startsOn: isoDayOf(H2hLeaguePolicy.firstMonth),
    isPilot: seat?.isPilot ?? false,
    division: seat?.division.level,
    groupIndex: seat?.groupIndex,
    myRank: league.myRank,
    promotionZone: league.promotionZone,
    relegationZone: league.relegationZone,
    standings: [
      for (final placing in league.placings) _standingToDto(placing, league),
    ],
    rounds: [for (final view in league.rounds) _roundViewToDto(view, league)],
  );
}

/// The admin's month as `GET /admin/h2h/rounds` sends it.
H2hRoundsOverviewDto h2hRoundsOverviewToDto(H2hRoundsOverview overview) {
  final month = overview.month;
  return H2hRoundsOverviewDto(
    monthStart: isoDayOf(overview.monthStart),
    drawn: month != null,
    isPilot: month?.isPilot ?? false,
    rounds: [for (final round in overview.rounds) h2hRoundToDto(round)],
    candidates: [
      for (final candidate in overview.candidates)
        H2hCandidateDayDto(
          day: isoDayOf(candidate.fixtures.day),
          fixtureCount: candidate.fixtures.fixtureCount,
          firstKickoff:
              candidate.fixtures.firstKickoff?.toUtc().toIso8601String() ?? '',
          kind: candidate.kind.name,
        ),
    ],
  );
}

/// One approved round as an admin sees it.
H2hRoundDto h2hRoundToDto(H2hRound round) => H2hRoundDto(
  id: round.id.value,
  round: round.number,
  day: isoDayOf(round.day),
  fixtureCount: round.fixtureCount,
  automatic: round.approvedBy == null,
  locked: round.locked,
);

/// The wire name of a [H2hLeagueState].
String h2hStateWireName(H2hLeagueState state) => switch (state) {
  H2hLeagueState.notStarted => 'not_started',
  H2hLeagueState.drawPending => 'draw_pending',
  H2hLeagueState.notInDraw => 'not_in_draw',
  H2hLeagueState.open => 'open',
};

/// Parses a `YYYY-MM-DD` day sent by a client into its UTC midnight, or
/// null when [raw] is not exactly such a date (a day that does not exist,
/// as `2026-02-30`, included).
DateTime? parseIsoDay(String? raw) {
  if (raw == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final year = int.parse(raw.substring(0, 4));
  final month = int.parse(raw.substring(5, 7));
  final day = int.parse(raw.substring(8, 10));
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// Formats a UTC-midnight day as `YYYY-MM-DD`.
String isoDayOf(DateTime day) {
  final utc = day.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

H2hStandingDto _standingToDto(H2hPlacing placing, MyH2hLeague league) {
  final standing = placing.standing;
  final matches = [...standing.matches]
    ..sort((a, b) => a.round.compareTo(b.round));
  final recent = matches.length > h2hFormLength
      ? matches.sublist(matches.length - h2hFormLength)
      : matches;
  return H2hStandingDto(
    rank: placing.rank,
    userId: standing.userId.value,
    displayName: league.profiles[standing.userId]?.displayName ?? '',
    played: standing.played,
    won: standing.won,
    drawn: standing.drawn,
    lost: standing.lost,
    leaguePoints: standing.leaguePoints,
    pointsFor: standing.pointsFor,
    exactCount: standing.exactCount,
    form: [for (final match in recent) match.result.wireName],
    isMe: standing.userId == league.readerId,
    avatarUrl: _avatarUrlOf(standing.userId, league.profiles),
  );
}

H2hRoundViewDto _roundViewToDto(MyH2hRound view, MyH2hLeague league) {
  final opponent = view.opponentId;
  final played =
      view.status == H2hRoundStatus.live ||
      view.status == H2hRoundStatus.settled;
  final match = played ? view.match : null;
  return H2hRoundViewDto(
    round: view.round.number,
    day: isoDayOf(view.round.day),
    status: view.status.name,
    fixtureCount: view.round.fixtureCount,
    opponentUserId: opponent?.value,
    opponentName: opponent == null
        ? null
        : league.profiles[opponent]?.displayName ?? '',
    opponentAvatarUrl: opponent == null
        ? null
        : _avatarUrlOf(opponent, league.profiles),
    myPoints: match?.points,
    opponentPoints: match?.opponentPoints,
    result: match?.result.wireName,
  );
}

/// The relative URL of [userId]'s picture, or null when the profile reader
/// returned no picture version for them.
String? _avatarUrlOf(
  UserId userId,
  Map<UserId, WeeklyLeagueMemberProfile> profiles,
) {
  final updatedAt = profiles[userId]?.avatarUpdatedAt;
  if (updatedAt == null) {
    return null;
  }
  return avatarUrlOf(userId: userId, updatedAt: updatedAt);
}
