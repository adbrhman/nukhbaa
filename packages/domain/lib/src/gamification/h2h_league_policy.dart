import 'package:domain/src/identity/user_id.dart';

/// The divisions of the monthly head-to-head league (decided 2026-10-09).
///
/// Stored in the database as the plain number `h2h_leagues.division`
/// (migration 0100), named here for the same reason `WeeklyLeagueTier` is:
/// how many divisions there are is policy, and policy must not need a
/// migration to change. The order runs downwards: 1 is the top division.
///
/// The Arabic labels live in the mobile l10n, never here.
enum H2hDivision {
  /// The top division. Nothing is promoted out of it.
  first(1),

  /// Second division.
  second(2),

  /// Third division.
  third(3),

  /// The open division: everyone else, in as many groups as it takes.
  /// Nothing is relegated out of it.
  fourth(4);

  const H2hDivision(this.level);

  /// The value stored in `gamification.h2h_leagues.division`.
  final int level;

  /// The division stored as [level], or null if the number names none.
  ///
  /// Null rather than a throw: a row written by a future generation of the
  /// ladder is data this generation does not understand, not a crash.
  static H2hDivision? ofLevel(int level) {
    for (final division in values) {
      if (division.level == level) {
        return division;
      }
    }
    return null;
  }

  /// Whether promotion out of this division is possible.
  bool get canPromote => this != first;

  /// Whether relegation out of this division is possible.
  bool get canRelegate => this != fourth;
}

/// What a month did to a member.
enum H2hLeagueOutcome {
  /// Plays a higher division next month.
  promoted('promoted'),

  /// Stays in the same division next month.
  held('held'),

  /// Plays a lower division next month.
  relegated('relegated'),

  /// Predicted on too few days to be drawn next month.
  out('out');

  const H2hLeagueOutcome(this.wireName);

  /// The value carried in the `h2h_league_finished` event payload.
  final String wireName;

  /// The outcome named [raw], or null when it names none.
  static H2hLeagueOutcome? ofWire(String? raw) {
    for (final outcome in values) {
      if (outcome.wireName == raw) {
        return outcome;
      }
    }
    return null;
  }
}

/// The result of one round for one member.
enum H2hMatchResult {
  /// Three league points.
  win('win'),

  /// One league point.
  draw('draw'),

  /// No league point.
  loss('loss');

  const H2hMatchResult(this.wireName);

  /// The value sent to clients.
  final String wireName;

  /// League points this result is worth.
  int get leaguePoints => switch (this) {
    H2hMatchResult.win => 3,
    H2hMatchResult.draw => 1,
    H2hMatchResult.loss => 0,
  };
}

/// Which kind of day a round may be made of.
enum H2hRoundKind {
  /// Six fixtures or more: approved by an admin or by the system.
  regular,

  /// Exactly five fixtures: only an admin may approve it, to complete the
  /// round-robin in a month short of regular days.
  fill,
}

/// One seat of a group, as the table needs to see it.
///
/// A seat is held for a run of rounds (NK183, migration 0189): the draw's
/// member from round 1, a player who came in by a seat swap from the swap's
/// round, and a player who left up to the round before it. Without a swap
/// the member holds the seat for the whole month.
final class H2hMember {
  /// Creates a member.
  const H2hMember({
    required this.userId,
    required this.slot,
    required this.joinedAt,
    this.fromRound = 1,
    this.untilRound,
  });

  /// The platform user who holds the seat.
  final UserId userId;

  /// The member's fixed place in the group's round-robin, `0 <= slot <
  /// capacity`. The whole schedule is a function of the slot.
  final int slot;

  /// When the seat was taken. The last tie-break of the table.
  final DateTime joinedAt;

  /// The first round the member plays in this seat.
  final int fromRound;

  /// The last round the member plays in this seat, or null when he holds
  /// it to the end of the month.
  final int? untilRound;

  /// Whether the member holds the seat in round [round].
  bool activeIn(int round) =>
      round >= fromRound && (untilRound == null || round <= untilRound!);

  /// Whether the member still holds the seat: no swap took it from him.
  bool get current => untilRound == null;
}

/// One round of the month: its number and its Riyadh day.
final class H2hRoundRef {
  /// Creates a round reference.
  const H2hRoundRef({required this.number, required this.day});

  /// 1-based number of the round in its month.
  final int number;

  /// The Riyadh day whose fixtures make the round, as a UTC midnight.
  final DateTime day;
}

/// What one member did in one round: the round's fixtures only.
final class H2hRoundScore {
  /// Creates a round score.
  const H2hRoundScore({
    required this.userId,
    required this.round,
    required this.points,
    required this.exactCount,
    required this.predictedCount,
  });

  /// Whose round this is.
  final UserId userId;

  /// The round's number.
  final int round;

  /// Points earned on the round's fixtures, the double included. Summed by
  /// the caller from the scores; never computed here.
  final int points;

  /// Exact scorelines called right in the round.
  final int exactCount;

  /// Predictions the member holds for the round's fixtures. Zero means the
  /// member did not play the round.
  final int predictedCount;

  /// Whether the member played the round at all.
  bool get present => predictedCount > 0;
}

/// One round of one member.
final class H2hMatch {
  /// Creates a match.
  const H2hMatch({
    required this.round,
    required this.day,
    required this.opponentId,
    required this.points,
    required this.opponentPoints,
    required this.present,
    required this.opponentPresent,
    required this.result,
  });

  /// The round's number.
  final int round;

  /// The round's Riyadh day, as a UTC midnight.
  final DateTime day;

  /// The opponent, or null when the opposite seat was empty and the member
  /// played the group average.
  final UserId? opponentId;

  /// The member's points in the round.
  final int points;

  /// The opponent's points, or the group average when [opponentId] is null.
  final double opponentPoints;

  /// Whether the member played the round.
  final bool present;

  /// Whether the opponent played the round. Always true for the average.
  final bool opponentPresent;

  /// What the round gave the member.
  final H2hMatchResult result;
}

/// One member's month so far.
final class H2hStanding {
  /// Creates a standing.
  const H2hStanding({
    required this.userId,
    required this.slot,
    required this.joinedAt,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.pointsFor,
    required this.exactCount,
    required this.presentRounds,
    required this.matches,
  });

  /// The member.
  final UserId userId;

  /// The member's seat.
  final int slot;

  /// When the seat was taken.
  final DateTime joinedAt;

  /// Rounds won.
  final int won;

  /// Rounds drawn.
  final int drawn;

  /// Rounds lost.
  final int lost;

  /// Prediction points over the rounds. First tie-break.
  final int pointsFor;

  /// Exact scorelines over the rounds. Third tie-break, after the
  /// head-to-head between the tied members.
  final int exactCount;

  /// Rounds in which the member held at least one prediction.
  final int presentRounds;

  /// Every round of the member, oldest first.
  final List<H2hMatch> matches;

  /// Rounds played.
  int get played => won + drawn + lost;

  /// Three for a win, one for a draw.
  int get leaguePoints => won * 3 + drawn;
}

/// A standing with its place in the group.
final class H2hPlacing {
  /// Creates a placing.
  const H2hPlacing({required this.standing, required this.rank});

  /// The member's month.
  final H2hStanding standing;

  /// 1-based, distinct: the order is total.
  final int rank;
}

/// One group of a judged month, as the closing job hands it in.
final class H2hGroupResult {
  /// Creates a group result.
  const H2hGroupResult({required this.division, required this.placings});

  /// The division the group played in.
  final H2hDivision division;

  /// The group's table, best first, as [H2hLeaguePolicy.order] made it.
  final List<H2hPlacing> placings;
}

/// Where one member of a judged month goes next.
final class H2hFinish {
  /// Creates a finish.
  const H2hFinish({
    required this.placing,
    required this.division,
    required this.nextDivision,
    required this.outcome,
  });

  /// The member's place in their own group.
  final H2hPlacing placing;

  /// The division played this month.
  final H2hDivision division;

  /// The division played next month, or null when the member predicted on
  /// too few days to be drawn.
  final H2hDivision? nextDivision;

  /// [nextDivision] compared with [division].
  final H2hLeagueOutcome outcome;
}

/// One player of a monthly draw, in the order the draw seats them.
final class H2hDrawEntry {
  /// Creates an entry.
  const H2hDrawEntry({required this.userId, required this.division});

  /// The player.
  final UserId userId;

  /// The division the player plays this month.
  final H2hDivision division;
}

/// One group the draw opens, with its seats.
final class H2hDrawGroup {
  /// Creates a drawn group.
  const H2hDrawGroup({
    required this.division,
    required this.groupIndex,
    required this.seats,
    this.capacity = H2hLeaguePolicy.groupCapacity,
  });

  /// The division.
  final H2hDivision division;

  /// 0-based position among the groups of the division.
  final int groupIndex;

  /// The players, each with the slot they hold.
  final List<H2hDrawSeat> seats;

  /// Seats of the group's round-robin: [H2hLeaguePolicy.groupCapacity],
  /// or 22 for the one group of the elite draw that takes a last single
  /// player as its 21st member (`H2hLeaguePolicy.eliteDraw`). Always even.
  final int capacity;
}

/// One seat handed out by the draw.
final class H2hDrawSeat {
  /// Creates a seat.
  const H2hDrawSeat({required this.userId, required this.slot});

  /// The player.
  final UserId userId;

  /// The slot in the group's round-robin.
  final int slot;
}

/// The rules of the monthly head-to-head league (decided 2026-10-09/10 with
/// the players' group, checked against September's real data).
///
/// Pure data and arithmetic: no clock, no database, no fixture. The caller
/// hands it rounds, seats and scores, and it answers.
///
/// **A round is an approved day.** Its fixtures are every fixture of that
/// Riyadh day, frozen at its first kickoff. A day of six fixtures or more is
/// a regular round (the system approves it by itself when no admin did); a
/// day of exactly five is a fill round, approved only by an admin to
/// complete the round-robin. At most 19 rounds a month.
///
/// **One opponent a round, by a fixed schedule in a secret order.** Each
/// member holds a slot of a 20-seat round-robin (the circle method): its 19
/// turns meet every other seat once. The rounds take the turns in the
/// group's own order (`turnOf`, migration 0184, decided 2026-10-25), drawn
/// at random and never sent to a client, so nobody can work out an opponent
/// ahead of time; a group without one takes them in order.
///
/// **The round.** Both played: more points wins, equal points draw. One
/// played: that one wins, whatever the score. Neither played: both lose. An
/// empty seat plays the group average: more than the average wins, exactly
/// the average draws, and a member who did not play loses to it.
///
/// **The table** is league points (3, 1, 0), then prediction points, then
/// the head-to-head between the members still tied, then exact scorelines,
/// then the earlier seat, then the user id: a total order.
///
/// **The month's end.** Up to three cross each boundary (never more than
/// half of either division); the open division's group winners go up first.
/// Only a player who predicted on [minActiveDays] days of the month is drawn
/// next month; the divisions above the open one are refilled to twenty from
/// below. No points are paid into the ledger: the reward is the division.
final class H2hLeaguePolicy {
  const H2hLeaguePolicy._();

  /// Seats of one group. Even: every round pairs every seat.
  static const int groupCapacity = 20;

  /// Members of each division above the open one.
  static const int divisionSize = 20;

  /// The most members moved across one boundary.
  static const int maxMovement = 3;

  /// The most rounds of one month: one full round-robin, no return legs.
  static const int maxRounds = 19;

  /// Fixtures a day needs to be a regular round.
  static const int regularRoundFixtures = 6;

  /// Fixtures of a fill round.
  static const int fillRoundFixtures = 5;

  /// Days with a prediction a player needs in a month to be drawn the next.
  static const int minActiveDays = 5;

  /// Matches a player may have left without a prediction in the month and
  /// still count as committed. The first draw seats the committed first, by
  /// points, then the rest, so a group is not a mix of a player who
  /// predicted everything and one who dropped in for five days (script 171).
  ///
  /// No longer read by the draw: from NK182 (2026-10-31) the order is the
  /// matches missed themselves, fewest first, then points.
  static const int committedMissedMatches = 5;

  /// How long before a regular day's first kickoff the system approves it
  /// when no admin did.
  static const Duration autoApproveLead = Duration(hours: 24);

  /// The first month the league is played for everyone, as a UTC midnight on
  /// its first day. Its draw is seeded from the month before.
  static final DateTime firstMonth = DateTime.utc(2026, 11);

  // NK172 month gate
  /// Whether [monthOrDay] belongs to December 2026 or a later month.
  ///
  /// A rule is selected from the month being judged, never from today's date.
  static bool usesDecemberRules(DateTime monthOrDay) =>
      monthOrDay.year > 2026 ||
      (monthOrDay.year == 2026 && monthOrDay.month >= 12);
  // NK172_000

  // NK182 elite draw (decided 2026-10-31)
  /// The groups of the elite draw: the first [eliteSeats] players of the
  /// order, dealt evenly into this many groups of [eliteDivision].
  static const int eliteGroups = 4;

  /// Players of the elite groups: 20 a group.
  static const int eliteSeats = eliteGroups * groupCapacity;

  /// The division the four elite groups are stored under
  /// (`h2h_leagues.division`). Shown as المجموعة 1 .. 4.
  static const H2hDivision eliteDivision = H2hDivision.first;

  /// The division the extra groups are stored under, `group_index` 0, 1,
  /// ... in the order of the draw. Shown as المجموعة 5, 6, ...
  static const H2hDivision extraDivision = H2hDivision.second;

  /// Places of each elite group that go to the Elite Cup after the 19
  /// rounds: the first, second and third places play three separate cups.
  static const int cupQualifiers = 3;

  /// Whether [monthOrDay] is drawn by [eliteDraw]: November 2026 and every
  /// month after it. Selected from the month itself, never today's date.
  static bool usesEliteDraw(DateTime monthOrDay) =>
      monthOrDay.year > 2026 ||
      (monthOrDay.year == 2026 && monthOrDay.month >= 11);

  /// The 1-based group number players see: المجموعة 1 .. 4 for the elite
  /// groups, 5 and up for the extra groups, in the draw's order.
  static int groupNumberOf({
    required H2hDivision division,
    required int groupIndex,
  }) =>
      division == eliteDivision ? groupIndex + 1 : eliteGroups + groupIndex + 1;

  /// The top places of a group shown as the Elite Cup's places: three in an
  /// elite group, none in an extra group.
  static int cupZoneOf(H2hDivision division, int size) {
    if (division != eliteDivision) {
      return 0;
    }
    return size < cupQualifiers ? size : cupQualifiers;
  }

  /// The groups of a month drawn from [ordered], the drawing order (fewest
  /// matches missed first, then points, then exact scorelines).
  ///
  /// **The four elite groups.** The first [eliteSeats] are dealt like a
  /// snake: 1 2 3 4, then 4 3 2 1, then 1 2 3 4 ..., so every group gets
  /// one player of each band of four and the groups are as even in strength
  /// as the order allows. A player's slot is the band they came from.
  /// Fewer than eight players open as many groups as there are pairs.
  ///
  /// **The extra groups.** The rest, in the same order, twenty at a time:
  /// the 81st to the 100th is the first extra group (المجموعة 5), the 101st
  /// to the 120th the next, and the last group takes what is left. A single
  /// player left at the end is not left out: he joins the last full group as
  /// its 21st member, in a group of 22 seats (one seat stays empty and plays
  /// the group average). Alone, with no extra group to join, he plays in a
  /// group of his own.
  static List<H2hDrawGroup> eliteDraw(List<UserId> ordered) {
    final eliteCount = ordered.length < eliteSeats
        ? ordered.length
        : eliteSeats;
    // Fewer than eight players (never the case in a real month) open fewer
    // groups, so that no elite group is a player alone.
    final pairs = eliteCount ~/ 2;
    final count = pairs >= eliteGroups ? eliteGroups : (pairs < 1 ? 1 : pairs);
    final elite = <List<H2hDrawSeat>>[
      for (var g = 0; g < count; g++) <H2hDrawSeat>[],
    ];
    for (var k = 0; k < eliteCount; k++) {
      final band = k ~/ count;
      final position = k % count;
      final group = band.isEven ? position : count - 1 - position;
      elite[group].add(H2hDrawSeat(userId: ordered[k], slot: band));
    }

    final groups = <H2hDrawGroup>[
      for (var g = 0; g < count; g++)
        if (elite[g].isNotEmpty)
          H2hDrawGroup(
            division: eliteDivision,
            groupIndex: g,
            seats: List<H2hDrawSeat>.unmodifiable(elite[g]),
          ),
    ];

    final rest = ordered.sublist(eliteCount);
    final chunks = <List<UserId>>[];
    for (var start = 0; start < rest.length; start += groupCapacity) {
      final end = start + groupCapacity < rest.length
          ? start + groupCapacity
          : rest.length;
      chunks.add(rest.sublist(start, end));
    }
    if (chunks.length > 1 && chunks.last.length == 1) {
      final single = chunks.removeLast();
      chunks[chunks.length - 1] = <UserId>[...chunks.last, ...single];
    }
    for (var i = 0; i < chunks.length; i++) {
      final players = chunks[i];
      final capacity = players.length <= groupCapacity
          ? groupCapacity
          : players.length + players.length % 2;
      groups.add(
        H2hDrawGroup(
          division: extraDivision,
          groupIndex: i,
          capacity: capacity,
          seats: List<H2hDrawSeat>.unmodifiable([
            for (var k = 0; k < players.length; k++)
              H2hDrawSeat(userId: players[k], slot: k),
          ]),
        ),
      );
    }
    return List<H2hDrawGroup>.unmodifiable(groups);
  }
  // NK182_000

  /// The first day of the Riyadh month containing [riyadhDay], as a UTC
  /// midnight -- the value of `month_start` in the 0100 tables.
  static DateTime monthStartOf(DateTime riyadhDay) =>
      DateTime.utc(riyadhDay.year, riyadhDay.month);

  /// The first day of the month after the one containing [riyadhDay]: the
  /// exclusive end of that month.
  static DateTime monthEndOf(DateTime riyadhDay) =>
      DateTime.utc(riyadhDay.year, riyadhDay.month + 1);

  /// The first day of the month before the one containing [riyadhDay].
  static DateTime previousMonthOf(DateTime riyadhDay) =>
      DateTime.utc(riyadhDay.year, riyadhDay.month - 1);

  /// The kind of round a day of [fixtureCount] fixtures may be, or null when
  /// it may be none.
  static H2hRoundKind? roundKindOf(int fixtureCount) {
    if (fixtureCount >= regularRoundFixtures) {
      return H2hRoundKind.regular;
    }
    if (fixtureCount == fillRoundFixtures) {
      return H2hRoundKind.fill;
    }
    return null;
  }

  /// Whether a day of [fixtureCount] fixtures may become the next round of a
  /// month that already holds [approvedRounds] rounds. A fill day needs an
  /// admin ([byAdmin]); the system approves regular days only.
  static bool canApprove({
    required int fixtureCount,
    required int approvedRounds,
    required bool byAdmin,
  }) {
    if (approvedRounds >= maxRounds) {
      return false;
    }
    return switch (roundKindOf(fixtureCount)) {
      H2hRoundKind.regular => true,
      H2hRoundKind.fill => byAdmin,
      null => false,
    };
  }

  /// Whether a player who predicted on [activeDays] days of a month is drawn
  /// the next month.
  static bool isEligible(int activeDays) => activeDays >= minActiveDays;

  /// The turn of the round-robin that round [round] plays, by the group's
  /// secret order [turns] (a permutation of 1 .. capacity - 1, migration
  /// 0184), counted again from its start past its end. An empty [turns] is
  /// the order of the slots themselves: round n plays turn n.
  static int turnOf({required int round, required List<int> turns}) {
    if (turns.isEmpty) {
      return round;
    }
    return turns[(round - 1) % turns.length];
  }

  /// The slot [slot] meets in [round] of a group of [capacity] seats.
  ///
  /// The circle method: slot 0 stays put and the others rotate one place a
  /// round, so `capacity - 1` rounds meet every pair exactly once. [capacity]
  /// must be even and [round] at least 1.
  static int opponentSlot({
    required int slot,
    required int round,
    required int capacity,
  }) {
    final rotating = capacity - 1;
    final turn = (round - 1) % rotating;
    final position = slot == 0 ? 0 : ((slot - 1 - turn) % rotating) + 1;
    final facing = capacity - 1 - position;
    return facing == 0 ? 0 : ((facing - 1 + turn) % rotating) + 1;
  }

  /// The division of the player at 0-based [position] of a drawing order:
  /// twenty to a division, the rest to the open one.
  static H2hDivision seedDivision(int position) {
    final index = position ~/ divisionSize;
    const divisions = H2hDivision.values;
    return index < divisions.length ? divisions[index] : divisions.last;
  }

  /// [ordered] cut into divisions, twenty at a time.
  static List<H2hDrawEntry> cut(List<UserId> ordered) =>
      List<H2hDrawEntry>.unmodifiable([
        for (var i = 0; i < ordered.length; i++)
          H2hDrawEntry(userId: ordered[i], division: seedDivision(i)),
      ]);

  /// How many of a division of [size] are promoted out of it.
  static int promotionCount(H2hDivision division, int size) =>
      division.canPromote ? _movement(size) : 0;

  /// How many of a division of [size] are relegated out of it.
  static int relegationCount(H2hDivision division, int size) =>
      division.canRelegate ? _movement(size) : 0;

  static int _movement(int size) {
    final half = size ~/ 2;
    return half < maxMovement ? half : maxMovement;
  }

  /// Every member's month over [rounds], oldest first.
  ///
  /// [scores] holds what members did in those rounds; a member missing from
  /// a round did not play it. [turns] is the group's secret order of the
  /// round-robin's turns (`turnOf`); empty, the rounds take them in order.
  ///
  /// A round is played by the members who hold a seat in it
  /// (`H2hMember.activeIn`, NK183): after a seat swap the seat's new holder
  /// meets that seat's opponents, and the group average of a round is over
  /// the members who held a seat in it. Without a swap every member plays
  /// every round, as before.
  static List<H2hStanding> table({
    required int capacity,
    required List<H2hMember> members,
    required List<H2hRoundRef> rounds,
    required List<H2hRoundScore> scores,
    List<int> turns = const <int>[],
  }) {
    final byKey = <String, H2hRoundScore>{
      for (final score in scores) _key(score.userId, score.round): score,
    };
    final tallies = <UserId, _Tally>{
      for (final member in members) member.userId: _Tally(),
    };

    for (final round in rounds) {
      // NK183: the members who hold a seat in this round (a seat swap of
      // 0189 changes the holder from its round on).
      final active = <H2hMember>[
        for (final member in members)
          if (member.activeIn(round.number)) member,
      ];
      if (active.isEmpty) {
        continue;
      }
      final bySlot = <int, H2hMember>{
        for (final member in active) member.slot: member,
      };
      final day = DateTime.utc(round.day.year, round.day.month, round.day.day);
      var total = 0;
      for (final member in active) {
        final score = byKey[_key(member.userId, round.number)];
        if (score != null && score.present) {
          total += score.points;
        }
      }
      // NK172_095
      final count = active.length;

      for (final member in active) {
        final mine = byKey[_key(member.userId, round.number)];
        final points = mine?.points ?? 0;
        final present = mine?.present ?? false;
        final candidate =
            bySlot[opponentSlot(
              slot: member.slot,
              round: turnOf(round: round.number, turns: turns),
              capacity: capacity,
            )];
        final opponent = candidate != null && candidate.userId != member.userId
            ? candidate
            : null;

        final H2hMatch match;
        if (opponent != null) {
          final theirs = byKey[_key(opponent.userId, round.number)];
          final theirPoints = theirs?.points ?? 0;
          final theyPlayed = theirs?.present ?? false;
          final average = total / count;
          final compareWithAverage =
              usesDecemberRules(day) && present && !theyPlayed;
          match = H2hMatch(
            round: round.number,
            day: day,
            opponentId: opponent.userId,
            points: points,
            opponentPoints: compareWithAverage
                ? average
                : theirPoints.toDouble(),
            present: present,
            opponentPresent: theyPlayed,
            result: compareWithAverage
                ? _compare(points * count, total)
                : _versus(
                    points: points,
                    present: present,
                    opponentPoints: theirPoints,
                    opponentPresent: theyPlayed,
                  ),
          );
          // NK172_001
        } else {
          match = H2hMatch(
            round: round.number,
            day: day,
            opponentId: null,
            points: points,
            opponentPoints: total / count,
            present: present,
            opponentPresent: true,
            result: !present
                ? H2hMatchResult.loss
                : _compare(points * count, total),
          );
        }
        tallies[member.userId]!.add(match, mine?.exactCount ?? 0);
      }
    }

    // One standing per player: a player who held two seats of the group
    // (never in practice) is read at his last one.
    final lastSeat = <UserId, H2hMember>{};
    for (final member in members) {
      final seen = lastSeat[member.userId];
      if (seen == null || member.fromRound >= seen.fromRound) {
        lastSeat[member.userId] = member;
      }
    }
    final written = <UserId>{};
    return List<H2hStanding>.unmodifiable([
      for (final member in members)
        if (written.add(member.userId))
          tallies[member.userId]!.toStanding(lastSeat[member.userId]!),
    ]);
  }

  /// One player's month put together from the parts he played in several
  /// groups (NK183: a seat swap moves a player to another group, and he
  /// keeps his own month). [parts] are his standings in each group over the
  /// rounds he held a seat there; [seat] is the seat he holds now.
  static H2hStanding mergeStandings({
    required List<H2hStanding> parts,
    required H2hMember seat,
  }) {
    var won = 0;
    var drawn = 0;
    var lost = 0;
    var pointsFor = 0;
    var exact = 0;
    var present = 0;
    final matches = <H2hMatch>[];
    for (final part in parts) {
      won += part.won;
      drawn += part.drawn;
      lost += part.lost;
      pointsFor += part.pointsFor;
      exact += part.exactCount;
      present += part.presentRounds;
      matches.addAll(part.matches);
    }
    matches.sort((a, b) => a.round.compareTo(b.round));
    return H2hStanding(
      userId: seat.userId,
      slot: seat.slot,
      joinedAt: seat.joinedAt,
      won: won,
      drawn: drawn,
      lost: lost,
      pointsFor: pointsFor,
      exactCount: exact,
      presentRounds: present,
      matches: List<H2hMatch>.unmodifiable(matches),
    );
  }

  /// [standings] best first, each with its distinct rank.
  ///
  /// Members level on league points and prediction points are separated by
  /// the league points they took from each other, then by exact scorelines,
  /// the earlier seat and the user id.
  static List<H2hPlacing> order(List<H2hStanding> standings) {
    final sorted = List<H2hStanding>.of(standings)..sort(_compareLevel);
    final ordered = <H2hStanding>[];
    var i = 0;
    while (i < sorted.length) {
      var j = i + 1;
      while (j < sorted.length && _compareLevel(sorted[i], sorted[j]) == 0) {
        j++;
      }
      final block = sorted.sublist(i, j);
      if (block.length > 1) {
        final tied = <UserId>{for (final s in block) s.userId};
        final headToHead = <UserId, int>{
          for (final s in block) s.userId: _pointsAgainst(s, tied),
        };
        block.sort((a, b) {
          final byHeadToHead = headToHead[b.userId]!.compareTo(
            headToHead[a.userId]!,
          );
          if (byHeadToHead != 0) {
            return byHeadToHead;
          }
          final byExact = b.exactCount.compareTo(a.exactCount);
          if (byExact != 0) {
            return byExact;
          }
          final bySeat = a.joinedAt.compareTo(b.joinedAt);
          if (bySeat != 0) {
            return bySeat;
          }
          return a.userId.value.compareTo(b.userId.value);
        });
      }
      ordered.addAll(block);
      i = j;
    }
    return List<H2hPlacing>.unmodifiable([
      for (var k = 0; k < ordered.length; k++)
        H2hPlacing(standing: ordered[k], rank: k + 1),
    ]);
  }

  /// Where every member of a judged month goes next.
  ///
  /// [groups] is every group of the month; [eligible] the members who
  /// predicted on [minActiveDays] days of it. Members of one division are
  /// merged across its groups by their place in their own group (every
  /// group winner before any runner-up), then by the table. Up to three
  /// cross each boundary; the members who are not eligible are then taken
  /// out, and the rest are cut at twenty a division, so a seat freed above
  /// is taken by the best of the division below.
  static List<H2hFinish> monthEnd({
    required List<H2hGroupResult> groups,
    required Set<UserId> eligible,
    required DateTime monthStart,
  }) {
    // NK172_002
    const divisions = H2hDivision.values;
    final merged = <H2hDivision, List<_Ranked>>{
      for (final division in divisions) division: <_Ranked>[],
    };
    for (final group in groups) {
      for (final placing in group.placings) {
        merged[group.division]!.add(_Ranked(placing, group.division));
      }
    }
    final decemberRules = usesDecemberRules(monthStart);
    final lists = <List<_Ranked>>[
      for (final division in divisions)
        merged[division]!
          ..sort((a, b) => _compareRanked(a, b, decemberRules: decemberRules)),
    ];
    // NK172_003

    // crossing[i]: how many move between division i and division i + 1.
    final crossing = <int>[
      for (var i = 0; i < divisions.length - 1; i++)
        _min(
          relegationCount(divisions[i], lists[i].length),
          promotionCount(divisions[i + 1], lists[i + 1].length),
        ),
    ];

    final ladder = <_Ranked>[];
    for (var i = 0; i < divisions.length; i++) {
      final list = lists[i];
      final up = i > 0 ? crossing[i - 1] : 0;
      final down = i < crossing.length ? crossing[i] : 0;
      ladder.addAll(list.sublist(up, list.length - down));
      if (i < crossing.length) {
        ladder.addAll(lists[i + 1].sublist(0, crossing[i]));
      }
      if (i > 0) {
        final above = lists[i - 1];
        ladder.addAll(above.sublist(above.length - crossing[i - 1]));
      }
    }

    final finishes = <H2hFinish>[];
    var position = 0;
    for (final ranked in ladder) {
      final userId = ranked.placing.standing.userId;
      if (eligible.contains(userId)) {
        finishes.add(_finish(ranked, seedDivision(position)));
        position++;
      } else {
        finishes.add(_finish(ranked, null));
      }
    }
    return List<H2hFinish>.unmodifiable(finishes);
  }

  /// Splits [entries] into groups: as few as hold each division at
  /// [groupCapacity], dealt in turn so the groups are even and the entries
  /// at the top of the order are spread across them. Slots follow the order
  /// within each group.
  static List<H2hDrawGroup> draw(List<H2hDrawEntry> entries) {
    final groups = <H2hDrawGroup>[];
    for (final division in H2hDivision.values) {
      final players = <UserId>[
        for (final entry in entries)
          if (entry.division == division) entry.userId,
      ];
      if (players.isEmpty) {
        continue;
      }
      final count = (players.length + groupCapacity - 1) ~/ groupCapacity;
      final seats = <List<H2hDrawSeat>>[
        for (var g = 0; g < count; g++) <H2hDrawSeat>[],
      ];
      for (var k = 0; k < players.length; k++) {
        seats[k % count].add(H2hDrawSeat(userId: players[k], slot: k ~/ count));
      }
      for (var g = 0; g < count; g++) {
        groups.add(
          H2hDrawGroup(
            division: division,
            groupIndex: g,
            seats: List<H2hDrawSeat>.unmodifiable(seats[g]),
          ),
        );
      }
    }
    return List<H2hDrawGroup>.unmodifiable(groups);
  }

  /// The groups an admin adds to a month already drawn (decided
  /// 2026-10-11): [order] dealt [groupCapacity] at a time, in its order,
  /// into the next groups of the ladder -- each division above the open one
  /// that holds no group yet, top down, then new groups of the open division
  /// after its last. [existing] names every group the month holds already.
  ///
  /// At most [groups] groups. A group needs two players, so a single player
  /// left at the end waits. Slots follow the order within each group, and
  /// the schedule is the slot's, so a group added late meets the same
  /// opponents in every round of the month as one drawn on its first night.
  ///
  /// In a month of the elite draw ([elite], `usesEliteDraw`) every added
  /// group is an extra group: [extraDivision], after its last group.
  static List<H2hDrawGroup> extend({
    required List<({H2hDivision division, int groupIndex})> existing,
    required List<UserId> order,
    required int groups,
    bool elite = false,
  }) {
    final nextIndex = <H2hDivision, int>{};
    for (final group in existing) {
      final after = group.groupIndex + 1;
      if (after > (nextIndex[group.division] ?? 0)) {
        nextIndex[group.division] = after;
      }
    }
    final open = H2hDivision.values.last;
    final added = <H2hDrawGroup>[];
    var start = 0;
    while (added.length < groups && order.length - start >= 2) {
      var division = elite ? extraDivision : open;
      if (!elite) {
        for (final candidate in H2hDivision.values) {
          if (candidate != open && !nextIndex.containsKey(candidate)) {
            division = candidate;
            break;
          }
        }
      }
      final end = start + groupCapacity < order.length
          ? start + groupCapacity
          : order.length;
      final index = nextIndex[division] ?? 0;
      added.add(
        H2hDrawGroup(
          division: division,
          groupIndex: index,
          seats: List<H2hDrawSeat>.unmodifiable([
            for (var k = start; k < end; k++)
              H2hDrawSeat(userId: order[k], slot: k - start),
          ]),
        ),
      );
      nextIndex[division] = index + 1;
      start = end;
    }
    return List<H2hDrawGroup>.unmodifiable(added);
  }

  static H2hFinish _finish(_Ranked ranked, H2hDivision? next) {
    final H2hLeagueOutcome outcome;
    if (next == null) {
      outcome = H2hLeagueOutcome.out;
    } else if (next.level < ranked.division.level) {
      outcome = H2hLeagueOutcome.promoted;
    } else if (next.level > ranked.division.level) {
      outcome = H2hLeagueOutcome.relegated;
    } else {
      outcome = H2hLeagueOutcome.held;
    }
    return H2hFinish(
      placing: ranked.placing,
      division: ranked.division,
      nextDivision: next,
      outcome: outcome,
    );
  }

  static H2hMatchResult _versus({
    required int points,
    required bool present,
    required int opponentPoints,
    required bool opponentPresent,
  }) {
    if (!present) {
      return H2hMatchResult.loss;
    }
    if (!opponentPresent) {
      return H2hMatchResult.win;
    }
    return _compare(points, opponentPoints);
  }

  static H2hMatchResult _compare(int mine, int theirs) {
    if (mine > theirs) {
      return H2hMatchResult.win;
    }
    if (mine == theirs) {
      return H2hMatchResult.draw;
    }
    return H2hMatchResult.loss;
  }

  /// League points first, then prediction points; zero means level.
  static int _compareLevel(H2hStanding a, H2hStanding b) {
    final byLeague = b.leaguePoints.compareTo(a.leaguePoints);
    if (byLeague != 0) {
      return byLeague;
    }
    return b.pointsFor.compareTo(a.pointsFor);
  }

  /// League points [standing] took from the members in [tied].
  static int _pointsAgainst(H2hStanding standing, Set<UserId> tied) {
    var points = 0;
    for (final match in standing.matches) {
      final opponent = match.opponentId;
      if (opponent != null && tied.contains(opponent)) {
        points += match.result.leaguePoints;
      }
    }
    return points;
  }

  // NK172 cross-group comparison
  static int _compareRanked(
    _Ranked a,
    _Ranked b, {
    required bool decemberRules,
  }) {
    final byRank = a.placing.rank.compareTo(b.placing.rank);
    if (byRank != 0) {
      return byRank;
    }
    final sa = a.placing.standing;
    final sb = b.placing.standing;
    if (decemberRules) {
      final byPrediction = sb.pointsFor.compareTo(sa.pointsFor);
      if (byPrediction != 0) {
        return byPrediction;
      }
      final byExact = sb.exactCount.compareTo(sa.exactCount);
      if (byExact != 0) {
        return byExact;
      }
      final byLeague = sb.leaguePoints.compareTo(sa.leaguePoints);
      if (byLeague != 0) {
        return byLeague;
      }
    } else {
      final byLevel = _compareLevel(sa, sb);
      if (byLevel != 0) {
        return byLevel;
      }
      final byExact = sb.exactCount.compareTo(sa.exactCount);
      if (byExact != 0) {
        return byExact;
      }
    }
    return sa.userId.value.compareTo(sb.userId.value);
  }
  // NK172_004

  static int _min(int a, int b) => a < b ? a : b;

  static String _key(UserId userId, int round) => '${userId.value}|$round';
}

/// A placing remembered with the division it was played in.
final class _Ranked {
  _Ranked(this.placing, this.division);

  final H2hPlacing placing;
  final H2hDivision division;
}

/// A member's running totals while [H2hLeaguePolicy.table] walks the rounds.
final class _Tally {
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int pointsFor = 0;
  int exactCount = 0;
  int presentRounds = 0;
  final List<H2hMatch> matches = <H2hMatch>[];

  void add(H2hMatch match, int exact) {
    switch (match.result) {
      case H2hMatchResult.win:
        won++;
      case H2hMatchResult.draw:
        drawn++;
      case H2hMatchResult.loss:
        lost++;
    }
    pointsFor += match.points;
    exactCount += exact;
    if (match.present) {
      presentRounds++;
    }
    matches.add(match);
  }

  H2hStanding toStanding(H2hMember member) => H2hStanding(
    userId: member.userId,
    slot: member.slot,
    joinedAt: member.joinedAt,
    won: won,
    drawn: drawn,
    lost: lost,
    pointsFor: pointsFor,
    exactCount: exactCount,
    presentRounds: presentRounds,
    matches: List<H2hMatch>.unmodifiable(matches),
  );
}
