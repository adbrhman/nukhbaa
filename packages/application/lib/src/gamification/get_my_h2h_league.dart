/// Use-case: read the caller's own head-to-head group (migration 0100).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where the caller stands with the league this month.
enum H2hLeagueState {
  /// The league opens to everyone on `H2hLeaguePolicy.firstMonth`, and the
  /// caller is not in a pilot.
  notStarted,

  /// The month has not been drawn yet (its first night).
  drawPending,

  /// The month was drawn without the caller: they predicted on fewer than
  /// five days last month, or joined since.
  notInDraw,

  /// The caller holds a seat.
  open,
}

/// Where a round stands for the caller.
enum H2hRoundStatus {
  /// Approved, not started: the fixture list is not frozen yet.
  upcoming,

  /// Started, not every result is in.
  live,

  /// Every result is in.
  settled,

  /// No fixture of the round is left: it counts for nobody.
  voided,
}

/// Whether the opponents of a round in [status] are still secret at [now]
/// (decided 2026-10-25, option D): until the last fixture that counts
/// ([lastKickoff], the sheet's) has kicked off, by the rule that closes
/// predictions (`FixtureLock`: at or after the kickoff). After it no pick of
/// the round can change. A round not started is secret; a settled or void
/// one is not; a live one without a kickoff stays secret.
bool h2hOpponentSecret({
  required H2hRoundStatus status,
  required DateTime? lastKickoff,
  required DateTime now,
}) {
  switch (status) {
    case H2hRoundStatus.upcoming:
      return true;
    case H2hRoundStatus.settled:
    case H2hRoundStatus.voided:
      return false;
    case H2hRoundStatus.live:
      return lastKickoff == null || now.toUtc().isBefore(lastKickoff.toUtc());
  }
}

/// One round as the caller sees it.
final class MyH2hRound {
  /// Creates a round view.
  const MyH2hRound({
    required this.round,
    required this.status,
    required this.opponentId,
    required this.match,
    this.opponentHidden = false,
    this.revealsAt,
    this.ownPoints,
  });

  /// The round.
  final H2hRound round;

  /// Where it stands.
  final H2hRoundStatus status;

  /// The caller's opponent in it, or null when the opposite seat is empty
  /// and the caller plays the group average, or while the opponent is
  /// secret ([opponentHidden]).
  final UserId? opponentId;

  /// The caller's match so far: null while upcoming or voided, and while
  /// the opponent is secret.
  final H2hMatch? match;

  /// True while the opponent is secret (`h2hOpponentSecret`): [opponentId]
  /// and [match] are then null, whoever the opponent is -- never read as
  /// the group average.
  final bool opponentHidden;

  /// When the secret opponent is named: the last kickoff of a live round.
  /// Null when not secret, and for a round not started.
  final DateTime? revealsAt;

  /// The caller's own stored points in a live round whose opponent is
  /// still secret; null otherwise ([match] carries them).
  final int? ownPoints;
}

/// The caller's head-to-head month.
final class MyH2hLeague {
  /// Creates a reading.
  const MyH2hLeague({
    required this.state,
    required this.monthStart,
    required this.readerId,
    this.seat,
    this.placings = const <H2hPlacing>[],
    this.profiles = const <UserId, WeeklyLeagueMemberProfile>{},
    this.myRank = 0,
    this.rounds = const <MyH2hRound>[],
    this.promotionZone = 0,
    this.relegationZone = 0,
  });

  /// Where the caller stands with the league.
  final H2hLeagueState state;

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// The user this reading was made for.
  final UserId readerId;

  /// The caller's seat, when [state] is open.
  final H2hSeat? seat;

  /// The group's table over its settled rounds, best first.
  final List<H2hPlacing> placings;

  /// The name and picture version of each member, keyed by user.
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;

  /// The caller's 1-based rank in [placings], 0 when not open.
  final int myRank;

  /// Every approved round of the month, oldest first.
  final List<MyH2hRound> rounds;

  /// How many places from the top go up if the month ended now. In the open
  /// division with several groups, the places that are certain.
  final int promotionZone;

  /// How many places from the bottom go down if the month ended now.
  final int relegationZone;
}

/// Reads the caller's group for the Riyadh month that is open now.
///
/// **It ranks; it does not score.** The table is `H2hLeaguePolicy.table` and
/// `order` over the SETTLED rounds, the same rules the closing job judges
/// with. A live round shows as the caller's live match, not in the table,
/// so the table never moves on a half-played round.
///
/// **A pilot month is visible only to its members**: anybody else reads
/// [H2hLeagueState.notStarted] until the league opens.
///
/// **The opponent is secret until the round's last kickoff**
/// (`h2hOpponentSecret`, decided 2026-10-25): a round not started, or live
/// before its last fixture kicks off, carries no opponent and no match, only
/// the caller's own points. The opponents come from the group's secret order
/// of the turns (`H2hLeaguePolicy.turnOf`, migration 0184).
///
/// Never throws; returns a typed [Result].
final class GetMyH2hLeague {
  /// Creates the use-case over its collaborators.
  const GetMyH2hLeague({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _profiles = profiles,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads [principal]'s month.
  Future<Result<MyH2hLeague>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final reader = principal.userId;
    final now = _clock.nowUtc().toUtc();
    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(now));

    final seatResult = await _leagues.seatFor(
      userId: reader,
      monthStart: month,
    );
    if (seatResult is Err<H2hSeat?>) {
      return Result.err(seatResult.error);
    }
    final seat = (seatResult as Ok<H2hSeat?>).value;

    if (seat == null) {
      final infoResult = await _leagues.monthOf(month);
      if (infoResult is Err<H2hMonthInfo?>) {
        return Result.err(infoResult.error);
      }
      final info = (infoResult as Ok<H2hMonthInfo?>).value;
      final H2hLeagueState state;
      if (month.isBefore(H2hLeaguePolicy.firstMonth)) {
        state = H2hLeagueState.notStarted;
      } else if (info == null) {
        state = H2hLeagueState.drawPending;
      } else {
        state = H2hLeagueState.notInDraw;
      }
      return Result.ok(
        MyH2hLeague(state: state, monthStart: month, readerId: reader),
      );
    }

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final rounds = (roundsResult as Ok<List<H2hRound>>).value;

    final sheetResult = await _sheets.sheetOf(
      leagueId: seat.leagueId,
      rounds: rounds,
    );
    if (sheetResult is Err<H2hGroupSheet>) {
      return Result.err(sheetResult.error);
    }
    final sheet = (sheetResult as Ok<H2hGroupSheet>).value;

    final settled = <H2hRoundRef>[];
    final started = <H2hRoundRef>[];
    for (final round in rounds) {
      if (!round.locked || sheet.voidRounds.contains(round.number)) {
        continue;
      }
      started.add(round.ref);
      if (sheet.settledRounds.contains(round.number)) {
        settled.add(round.ref);
      }
    }

    final placings = H2hLeaguePolicy.order(
      H2hLeaguePolicy.table(
        capacity: seat.capacity,
        members: sheet.members,
        rounds: settled,
        scores: sheet.scores,
        turns: sheet.turns,
      ),
    );
    var myRank = 0;
    for (final placing in placings) {
      if (placing.standing.userId == reader) {
        myRank = placing.rank;
        break;
      }
    }

    // The caller's matches over every started round, live ones included.
    final myMatches = <int, H2hMatch>{};
    for (final standing in H2hLeaguePolicy.table(
      capacity: seat.capacity,
      members: sheet.members,
      rounds: started,
      scores: sheet.scores,
      turns: sheet.turns,
    )) {
      if (standing.userId == reader) {
        for (final match in standing.matches) {
          myMatches[match.round] = match;
        }
      }
    }

    final bySlot = <int, UserId>{
      for (final member in sheet.members) member.slot: member.userId,
    };
    final views = <MyH2hRound>[];
    for (final round in rounds) {
      final status = _statusOf(round, sheet);
      final lastKickoff = sheet.lastKickoffs[round.number];
      final match = myMatches[round.number];
      if (h2hOpponentSecret(
        status: status,
        lastKickoff: lastKickoff,
        now: now,
      )) {
        views.add(
          MyH2hRound(
            round: round,
            status: status,
            opponentId: null,
            match: null,
            opponentHidden: true,
            revealsAt: status == H2hRoundStatus.live ? lastKickoff : null,
            ownPoints: match?.points,
          ),
        );
        continue;
      }
      views.add(
        MyH2hRound(
          round: round,
          status: status,
          opponentId:
              bySlot[H2hLeaguePolicy.opponentSlot(
                slot: seat.slot,
                round: H2hLeaguePolicy.turnOf(
                  round: round.number,
                  turns: sheet.turns,
                ),
                capacity: seat.capacity,
              )],
          match: match,
        ),
      );
    }

    final profilesResult = await _profiles.profilesOf([
      for (final member in sheet.members) member.userId,
    ]);
    if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profilesResult.error);
    }

    final size = sheet.members.length;
    return Result.ok(
      MyH2hLeague(
        state: H2hLeagueState.open,
        monthStart: month,
        readerId: reader,
        seat: seat,
        placings: placings,
        profiles: (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>)
            .value,
        myRank: myRank,
        rounds: views,
        // NK182: a month of the elite draw shows the Elite Cup's three
        // places in an elite group and no relegation by place.
        promotionZone: H2hLeaguePolicy.usesEliteDraw(month)
            ? H2hLeaguePolicy.cupZoneOf(seat.division, size)
            : _promotionZone(seat, size),
        relegationZone: H2hLeaguePolicy.usesEliteDraw(month)
            ? 0
            : H2hLeaguePolicy.relegationCount(seat.division, size),
      ),
    );
  }

  static H2hRoundStatus _statusOf(H2hRound round, H2hGroupSheet sheet) {
    if (!round.locked) {
      return H2hRoundStatus.upcoming;
    }
    if (sheet.voidRounds.contains(round.number)) {
      return H2hRoundStatus.voided;
    }
    if (sheet.settledRounds.contains(round.number)) {
      return H2hRoundStatus.settled;
    }
    return H2hRoundStatus.live;
  }

  /// In a division of one group, the policy's count. In the open division
  /// with several groups the three places go to the group winners first, so
  /// only `3 ~/ groups` places of each group are certain.
  static int _promotionZone(H2hSeat seat, int size) {
    final single = H2hLeaguePolicy.promotionCount(seat.division, size);
    if (seat.divisionGroups <= 1) {
      return single;
    }
    final certain = H2hLeaguePolicy.maxMovement ~/ seat.divisionGroups;
    return certain < single ? certain : single;
  }
}
