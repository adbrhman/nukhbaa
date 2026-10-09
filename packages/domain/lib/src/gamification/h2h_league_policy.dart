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
final class H2hMember {
  /// Creates a member.
  const H2hMember({
    required this.userId,
    required this.slot,
    required this.joinedAt,
  });

  /// The platform user who holds the seat.
  final UserId userId;

  /// The member's fixed place in the group's round-robin, `0 <= slot <
  /// capacity`. The whole schedule is a function of the slot.
  final int slot;

  /// When the seat was taken. The last tie-break of the table.
  final DateTime joinedAt;
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
  });

  /// The division.
  final H2hDivision division;

  /// 0-based position among the groups of the division.
  final int groupIndex;

  /// The players, each with the slot they hold.
  final List<H2hDrawSeat> seats;
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
/// **One opponent a round, by a fixed schedule.** Each member holds a slot
/// of a 20-seat round-robin (the circle method): rounds 1 to 19 meet every
/// other seat once. Nothing is random.
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

  /// How long before a regular day's first kickoff the system approves it
  /// when no admin did.
  static const Duration autoApproveLead = Duration(hours: 24);

  /// The first month the league is played for everyone, as a UTC midnight on
  /// its first day. Its draw is seeded from the month before.
  static final DateTime firstMonth = DateTime.utc(2026, 11);

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
  /// a round did not play it.
  static List<H2hStanding> table({
    required int capacity,
    required List<H2hMember> members,
    required List<H2hRoundRef> rounds,
    required List<H2hRoundScore> scores,
  }) {
    final bySlot = <int, H2hMember>{
      for (final member in members) member.slot: member,
    };
    final byKey = <String, H2hRoundScore>{
      for (final score in scores) _key(score.userId, score.round): score,
    };
    final tallies = <UserId, _Tally>{
      for (final member in members) member.userId: _Tally(),
    };

    for (final round in rounds) {
      if (members.isEmpty) {
        break;
      }
      final day = DateTime.utc(round.day.year, round.day.month, round.day.day);
      var total = 0;
      for (final member in members) {
        total += byKey[_key(member.userId, round.number)]?.points ?? 0;
      }
      final count = members.length;

      for (final member in members) {
        final mine = byKey[_key(member.userId, round.number)];
        final points = mine?.points ?? 0;
        final present = mine?.present ?? false;
        final candidate =
            bySlot[opponentSlot(
              slot: member.slot,
              round: round.number,
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
          match = H2hMatch(
            round: round.number,
            day: day,
            opponentId: opponent.userId,
            points: points,
            opponentPoints: theirPoints.toDouble(),
            present: present,
            opponentPresent: theyPlayed,
            result: _versus(
              points: points,
              present: present,
              opponentPoints: theirPoints,
              opponentPresent: theyPlayed,
            ),
          );
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

    return List<H2hStanding>.unmodifiable([
      for (final member in members) tallies[member.userId]!.toStanding(member),
    ]);
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
  }) {
    const divisions = H2hDivision.values;
    final merged = <H2hDivision, List<_Ranked>>{
      for (final division in divisions) division: <_Ranked>[],
    };
    for (final group in groups) {
      for (final placing in group.placings) {
        merged[group.division]!.add(_Ranked(placing, group.division));
      }
    }
    final lists = <List<_Ranked>>[
      for (final division in divisions) merged[division]!..sort(_compareRanked),
    ];

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

  static int _compareRanked(_Ranked a, _Ranked b) {
    final byRank = a.placing.rank.compareTo(b.placing.rank);
    if (byRank != 0) {
      return byRank;
    }
    final sa = a.placing.standing;
    final sb = b.placing.standing;
    final byLevel = _compareLevel(sa, sb);
    if (byLevel != 0) {
      return byLevel;
    }
    final byExact = sb.exactCount.compareTo(sa.exactCount);
    if (byExact != 0) {
      return byExact;
    }
    return sa.userId.value.compareTo(sb.userId.value);
  }

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
