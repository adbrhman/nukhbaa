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
    startsOn: isoDayOf(H2hLeaguePolicy.firstMonth),
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
    // A live round shows points only: the policy's live result would
    // tell whether the opponent predicted fixtures not kicked off yet.
    result: h2hShownResultOf(view)?.wireName,
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

/// The caller's month as `GET /me/h2h-league` sends it: the group reading
/// of [myH2hLeagueToDto], each round with its phase (`open` for the next
/// one, from the server's round state), its first kickoff and the result it
/// shows, and the days left in the month.
MyH2hLeagueDto myH2hMonthToDto(MyH2hMonth month) {
  final base = myH2hLeagueToDto(month.league);
  return MyH2hLeagueDto(
    state: base.state,
    monthStart: base.monthStart,
    startsOn: base.startsOn,
    isPilot: base.isPilot,
    division: base.division,
    groupIndex: base.groupIndex,
    myRank: base.myRank,
    promotionZone: base.promotionZone,
    relegationZone: base.relegationZone,
    standings: base.standings,
    daysLeft: month.daysLeft,
    rounds: [
      for (final round in base.rounds)
        H2hRoundViewDto(
          round: round.round,
          day: round.day,
          status: month.phases[round.round]?.name ?? round.status,
          fixtureCount: round.fixtureCount,
          opponentUserId: round.opponentUserId,
          opponentName: round.opponentName,
          opponentAvatarUrl: round.opponentAvatarUrl,
          myPoints: round.myPoints,
          opponentPoints: round.opponentPoints,
          result: month.results[round.round]?.wireName,
          firstKickoff: month.firstKickoffs[round.round]
              ?.toUtc()
              .toIso8601String(),
        ),
    ],
  );
}

/// One round of the caller in detail as `GET /me/h2h-league/rounds/{n}`
/// sends it. The opponent's picks are only those `GetMyH2hRound` let
/// through (kicked-off fixtures); nothing here adds or computes one.
MyH2hRoundDto myH2hRoundToDto(MyH2hRoundDetail detail) {
  final opponent = detail.opponentId;
  final profile = detail.opponentProfile;
  final pictureAt = profile?.avatarUpdatedAt;
  final theirs = detail.theirs;
  return MyH2hRoundDto(
    round: detail.round.number,
    day: isoDayOf(detail.round.day),
    status: detail.phase.name,
    fixtureCount: detail.round.fixtureCount,
    firstKickoff: detail.firstKickoff?.toUtc().toIso8601String(),
    opponentUserId: opponent?.value,
    opponentName: opponent == null ? null : profile?.displayName ?? '',
    opponentAvatarUrl: opponent == null || pictureAt == null
        ? null
        : avatarUrlOf(userId: opponent, updatedAt: pictureAt),
    myPoints: detail.myPoints,
    opponentPoints: detail.opponentPoints,
    result: detail.result?.wireName,
    mine: _sideTotalsToDto(detail.mine),
    theirs: theirs == null ? null : _sideTotalsToDto(theirs),
    fixtures: [
      for (final fixture in detail.fixtures) _roundFixtureToDto(fixture),
    ],
  );
}

H2hSideTotalsDto _sideTotalsToDto(H2hSideTotals totals) => H2hSideTotalsDto(
  predicted: totals.predicted,
  exact: totals.exact,
  doubles: totals.doubles,
);

H2hRoundFixtureDto _roundFixtureToDto(H2hRoundFixtureView fixture) {
  final mine = fixture.mine;
  final theirs = fixture.theirs;
  return H2hRoundFixtureDto(
    fixtureId: fixture.fixtureId,
    homeTeam: fixture.homeTeam,
    awayTeam: fixture.awayTeam,
    homeTeamId: fixture.homeTeamId,
    awayTeamId: fixture.awayTeamId,
    kickoffAt: fixture.kickoffAt?.toUtc().toIso8601String(),
    state: fixture.state.wireName,
    homeGoals: fixture.homeGoals,
    awayGoals: fixture.awayGoals,
    mine: mine == null ? null : _pickToDto(mine),
    theirs: theirs == null ? null : _pickToDto(theirs),
    theirsHidden: fixture.theirsHidden,
  );
}

H2hPickDto _pickToDto(H2hFixturePick pick) => H2hPickDto(
  homeGoals: pick.homeGoals,
  awayGoals: pick.awayGoals,
  isDouble: pick.isDouble,
  points: pick.points,
  exact: pick.exact,
);

/// Every match of one round in the caller's group, as
/// `GET /me/h2h-league/rounds/{n}/matches` sends it: names, pictures and
/// stored points only -- nobody's prediction.
H2hGroupRoundDto h2hGroupRoundToDto(MyH2hGroupRound group) => H2hGroupRoundDto(
  round: group.round.number,
  day: isoDayOf(group.round.day),
  status: group.phase.name,
  matches: [for (final pair in group.pairs) _groupMatchToDto(pair, group)],
);

H2hGroupMatchDto _groupMatchToDto(H2hGroupPair pair, MyH2hGroupRound group) {
  final away = pair.away;
  return H2hGroupMatchDto(
    homeUserId: pair.home.value,
    homeName: group.profiles[pair.home]?.displayName ?? '',
    homeAvatarUrl: _avatarUrlOf(pair.home, group.profiles),
    homeIsMe: pair.home == group.readerId,
    homePoints: pair.homePoints,
    awayUserId: away?.value,
    awayName: away == null ? null : group.profiles[away]?.displayName ?? '',
    awayAvatarUrl: away == null ? null : _avatarUrlOf(away, group.profiles),
    awayIsMe: away != null && away == group.readerId,
    awayPoints: pair.awayPoints,
    winner: pair.winner?.wireName,
  );
}
