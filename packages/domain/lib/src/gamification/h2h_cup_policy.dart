/// The Elite Cup of the head-to-head league (NK185, decided 2026-10-31).
///
/// After the 19 rounds of a month of the elite draw are all settled, the
/// first, second and third places of the four elite groups play three
/// separate cups ("paths"): the four first places, then the four second
/// places, then the four third places. Each path is a semi-final drawn at
/// random and a final; the paths never mix and a loser never moves to
/// another path.
///
/// The cup is played on four days, one after the other on the next
/// qualifying days (six fixtures or more; NK276, decided 2026-11-14): path
/// 1's semi-finals, then path 1's final; then the semi-finals of paths 2
/// and 3 side by side on one day, then their two finals side by side
/// ([H2hCupPolicy.days]). Two paths on one day are still two separate cups
/// on the same fixtures. A cup day is never scheduled before every stage of
/// the day before it is settled, so the day number is an expectation, never
/// a deadline. A stage whose day leaves no fixture to play is carried to
/// the next qualifying day with the same pairs; nothing is lost and nothing
/// is shortened.
///
/// A tie is judged on the stage's fixtures first: the side that predicted
/// wins over the side that did not; with both present, the higher points,
/// then more exact scorelines, then more right directions (NK319_01, owner
/// decision 2026-11-25), then the better month in the league
/// (prediction points, exact scorelines, league points, the group's number;
/// script 305, owner decision 2026-11-24); with neither present both lose.
///
/// NK357_01a (owner decision 2026-11-28): from December 2026 the cup is ONE
/// bracket of sixteen -- the first and the second place of each of the eight
/// elite groups -- played one round a day on path 1: the round of sixteen,
/// the quarter-finals, the semi-finals and the final
/// ([H2hCupPolicy.bracketDays]). The round of sixteen is drawn apart
/// ([H2hCupPolicy.drawBracket]): a group's first place meets the second place
/// of another group. The three-path cup above is unchanged for every month
/// before December 2026.
library;

import 'dart:math';

import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/gamification/h2h_league_policy.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:shared/shared.dart';

/// The identity of one stage of the Elite Cup -- a row of
/// `gamification.h2h_cup_stages` (migration 0190).
final class H2hCupStageId extends EntityId {
  /// Creates an id from its canonical UUID string.
  const H2hCupStageId(super.value);

  /// Parses an id from an untrusted [raw] string.
  static Result<H2hCupStageId> tryParse(String? raw) {
    if (raw == null || !uuidPattern.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'gamification.h2h_cup_stage_id_malformed',
          'Elite Cup stage id must be a UUID',
        ),
      );
    }
    return Result.ok(H2hCupStageId(raw));
  }
}

/// A round of a path.
enum H2hCupRound {
  // NK357_01b
  /// The round of sixteen of the bracket (December 2026 on): eight pairs.
  round16('round16'),

  /// The quarter-finals of the bracket: four pairs.
  quarter('quarter'),

  /// The two semi-finals, drawn at random.
  semi('semi'),

  /// The final between the semi-finals' winners.
  finale('final');

  const H2hCupRound(this.wire);

  /// The value stored in `h2h_cup_stages.stage`.
  final String wire;

  /// The round stored as [wire], or null for a value this build does not
  /// know.
  static H2hCupRound? fromWire(String wire) => switch (wire) {
    'round16' => H2hCupRound.round16,
    'quarter' => H2hCupRound.quarter,
    'semi' => H2hCupRound.semi,
    'final' => H2hCupRound.finale,
    _ => null,
  };
}

/// One step of the cup's order: a path (the place 1, 2 or 3) and a round.
final class H2hCupStep {
  /// Creates a step.
  const H2hCupStep(this.place, this.round, {this.bracket = false});

  /// The place in the elite groups the path is for: 1, 2 or 3.
  final int place;

  /// The round of the path.
  final H2hCupRound round;

  // NK357_01c
  /// Whether the step belongs to the one-bracket cup of December 2026 on
  /// ([H2hCupPolicy.bracketDays]). There the `semi` and the `final` are the
  /// third and the fourth day, not the first and the second of the three-path
  /// cup, so the same stored round needs the month's kind to be numbered.
  final bool bracket;

  /// [bracket], or a round only the bracket has.
  bool get inBracket =>
      bracket || round == H2hCupRound.round16 || round == H2hCupRound.quarter;

  /// The cup day the step is played on, 1 to 4. Three-path cup
  /// ([H2hCupPolicy.days]): path 1's semi-finals, path 1's final, the
  /// semi-finals of paths 2 and 3, the finals of paths 2 and 3. Bracket
  /// ([H2hCupPolicy.bracketDays]): the round of sixteen, the quarter-finals,
  /// the semi-finals, the final.
  int get cupDay {
    if (inBracket) {
      return switch (round) {
        H2hCupRound.round16 => 1,
        H2hCupRound.quarter => 2,
        H2hCupRound.semi => 3,
        H2hCupRound.finale => 4,
      };
    }
    return place == 1
        ? (round == H2hCupRound.semi ? 1 : 2)
        : (round == H2hCupRound.semi ? 3 : 4);
  }

  /// The expected league day of the step when nothing was late: 20 to 23.
  int get expectedDay => H2hCupPolicy.firstCupDay + cupDay - 1;

  @override
  bool operator ==(Object other) =>
      other is H2hCupStep &&
      other.place == place &&
      other.round == round &&
      other.inBracket == inBracket;

  @override
  int get hashCode => Object.hash(place, round, inBracket);

  @override
  String toString() => 'H2hCupStep($place, ${round.wire})';
}

/// A qualifier of a path, with what the league tie-break reads.
final class H2hCupEntry {
  /// Creates an entry.
  const H2hCupEntry({
    required this.userId,
    required this.place,
    required this.groupNumber,
    required this.leaguePoints,
    required this.pointsFor,
    required this.exactCount,
  });

  /// The player.
  final UserId userId;

  /// His place in his elite group: the path he plays.
  final int place;

  /// His elite group: 1 to 4.
  final int groupNumber;

  /// His league points of the month.
  final int leaguePoints;

  /// His prediction points of the month.
  final int pointsFor;

  /// His exact scorelines of the month.
  final int exactCount;
}

/// A pair of a stage: [home] against [away].
final class H2hCupPair {
  /// Creates a pair.
  const H2hCupPair({
    required this.slot,
    required this.home,
    required this.away,
  });

  /// 1 or 2 for the semi-finals, 1 for the final; NK357_01d: 1 to 8 in the
  /// bracket's round of sixteen, 1 to 4 in its quarter-finals.
  final int slot;

  /// The first side.
  final UserId home;

  /// The second side.
  final UserId away;
}

/// What one side did on the stage's fixtures.
final class H2hCupSide {
  /// Creates a side.
  const H2hCupSide({
    required this.points,
    required this.exact,
    required this.predicted,
    this.direction = 0,
  });

  /// No prediction on the stage's fixtures.
  static const H2hCupSide absent = H2hCupSide(
    points: 0,
    exact: 0,
    predicted: 0,
  );

  /// Prediction points on the stage's fixtures.
  final int points;

  /// Exact scorelines on them.
  final int exact;

  /// Predictions made on them.
  final int predicted;

  // NK319_01
  /// Right directions on them: the right outcome without the exact
  /// scoreline. The cup's tie-break after the exact scorelines.
  final int direction;

  /// Whether the side predicted at least one of them.
  bool get present => predicted > 0;
}

/// How a pair was decided.
enum H2hCupOutcome {
  /// More prediction points.
  points('points'),

  /// Level on points, more exact scorelines.
  exact('exact'),

  // NK319_01
  /// Level on both, more right directions.
  direction('direction'),

  /// Level on both, the better league month.
  league('league'),

  /// Only one side predicted.
  walkover('walkover'),

  /// Neither side predicted: both lose.
  bothAbsent('both_absent');

  const H2hCupOutcome(this.wire);

  /// The value stored in `h2h_cup_results.outcome`.
  final String wire;
}

/// The decision of one pair.
final class H2hCupDecision {
  /// Creates a decision.
  const H2hCupDecision({required this.winner, required this.outcome});

  /// The winner, or null when both lost.
  final UserId? winner;

  /// Why.
  final H2hCupOutcome outcome;
}

/// The Elite Cup's rules.
abstract final class H2hCupPolicy {
  /// The paths: the first, second and third places.
  static const List<int> places = <int>[1, 2, 3];

  /// The league day a cup is expected to open on, when the league ended on
  /// day 19.
  static const int firstCupDay = 20;

  /// The days of a cup, first to last, with the steps each day holds
  /// (NK276, decided 2026-11-14): the first places' semi-finals, their
  /// final, then the second and third places' semi-finals together, then
  /// their two finals together. A day starts only once every stage of the
  /// day before it is decided.
  static const List<List<H2hCupStep>> days = <List<H2hCupStep>>[
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.semi)],
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.finale)],
    <H2hCupStep>[
      H2hCupStep(2, H2hCupRound.semi),
      H2hCupStep(3, H2hCupRound.semi),
    ],
    <H2hCupStep>[
      H2hCupStep(2, H2hCupRound.finale),
      H2hCupStep(3, H2hCupRound.finale),
    ],
  ];

  /// The steps of a cup, in the order they are played: [days], day by day.
  static const List<H2hCupStep> order = <H2hCupStep>[
    H2hCupStep(1, H2hCupRound.semi),
    H2hCupStep(1, H2hCupRound.finale),
    H2hCupStep(2, H2hCupRound.semi),
    H2hCupStep(3, H2hCupRound.semi),
    H2hCupStep(2, H2hCupRound.finale),
    H2hCupStep(3, H2hCupRound.finale),
  ];

  // NK357_01e
  /// Whether the cup of [month] is the one bracket of sixteen: December 2026
  /// and every month after it, the months of the eight elite groups
  /// (`H2hLeaguePolicy.usesDecemberRules`). Selected from the month itself,
  /// never today's date.
  static bool isBracket(DateTime month) =>
      H2hLeaguePolicy.usesDecemberRules(month);

  /// Places of each elite group that go to the bracket: the first and the
  /// second.
  static const int bracketQualifiers = 2;

  /// The players of a full bracket: [bracketQualifiers] of each of the eight
  /// elite groups.
  static const int bracketSize = H2hLeaguePolicy.fairGroups * bracketQualifiers;

  /// The days of the bracket, one round a day, all on path 1 (owner decision
  /// 2026-11-28): the round of sixteen, the quarter-finals, the semi-finals
  /// and the final. A day starts only once the round before it is decided.
  static const List<List<H2hCupStep>> bracketDays = <List<H2hCupStep>>[
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.round16, bracket: true)],
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.quarter, bracket: true)],
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.semi, bracket: true)],
    <H2hCupStep>[H2hCupStep(1, H2hCupRound.finale, bracket: true)],
  ];

  /// The days of the cup of [month]: [bracketDays] for a bracket month (see
  /// [isBracket]), else the three paths' [days].
  static List<List<H2hCupStep>> daysOf(DateTime month) =>
      isBracket(month) ? bracketDays : days;

  /// The titles the cup of [month] ends with: one, the bracket's champion,
  /// for a bracket month; else one for each of the [places].
  static int titleCountOf(DateTime month) =>
      isBracket(month) ? 1 : places.length;

  /// The round a stage plays when [survivors] players are left: more than
  /// eight, the round of sixteen; five to eight, the quarter-finals; three or
  /// four, the semi-finals; two, the final; fewer than two, none (the one
  /// left is the champion, or nobody). A full bracket goes 16, 8, 4, 2, 1; a
  /// pair nobody played leaves fewer, and the round follows the players left,
  /// never the day.
  static H2hCupRound? roundFor(int survivors) {
    if (survivors > 8) {
      return H2hCupRound.round16;
    }
    if (survivors > 4) {
      return H2hCupRound.quarter;
    }
    if (survivors > 2) {
      return H2hCupRound.semi;
    }
    if (survivors == 2) {
      return H2hCupRound.finale;
    }
    return null;
  }

  /// Whether a month whose [settledRounds] (settled or void, every round
  /// approved) number [roundCount] has finished its league: all 19 rounds
  /// approved and judged.
  static bool leagueFinished({
    required int roundCount,
    required int judgedRounds,
  }) => roundCount >= 19 && judgedRounds >= 19;

  /// The semi-finals of [entries] drawn with [random]: two pairs of four;
  /// with three, one pair and a bye ([byeOf]); with two, the final itself
  /// is the only pair.
  static List<H2hCupPair> drawSemis(List<H2hCupEntry> entries, Random random) {
    final players = [for (final e in entries) e.userId]..shuffle(random);
    return [
      for (var i = 0; i + 1 < players.length && i < 4; i += 2)
        H2hCupPair(slot: i ~/ 2 + 1, home: players[i], away: players[i + 1]),
    ];
  }

  /// The entry of [entries] left without a pair by [pairs] (three entries),
  /// or null.
  static UserId? byeOf(List<H2hCupEntry> entries, List<H2hCupPair> pairs) {
    final paired = <UserId>{
      for (final p in pairs) ...[p.home, p.away],
    };
    for (final e in entries) {
      if (!paired.contains(e.userId)) {
        return e.userId;
      }
    }
    return null;
  }

  // NK357_01f
  /// The round of sixteen drawn from [entries] with [random]: the spaced
  /// draw (owner decision 2026-11-28). Each first place of an elite group
  /// meets the second place of ANOTHER group, so two players of one group
  /// never meet in the first round. Which first meets which second is
  /// random, and so is the slot of each pair; the slots decide who meets
  /// whom later (the winners of slots 1 and 2 meet in the quarter-final, and
  /// so on).
  ///
  /// The draw reshuffles until no pair shares a group (a few tries for eight
  /// groups); with one group alone, which a real month never has, the last
  /// shuffle stands. A group with no second place leaves a first over, and
  /// the players over are paired among themselves; an odd one out is the bye
  /// ([byeOf]).
  static List<H2hCupPair> drawBracket(
    List<H2hCupEntry> entries,
    Random random,
  ) {
    final firsts = <H2hCupEntry>[
      for (final e in entries)
        if (e.place == 1) e,
    ];
    final seconds = <H2hCupEntry>[
      for (final e in entries)
        if (e.place != 1) e,
    ];
    final matched = firsts.length < seconds.length
        ? firsts.length
        : seconds.length;
    var apart = false;
    for (var attempt = 0; attempt < 500 && !apart; attempt++) {
      firsts.shuffle(random);
      seconds.shuffle(random);
      apart = true;
      for (var i = 0; i < matched; i++) {
        if (firsts[i].groupNumber == seconds[i].groupNumber) {
          apart = false;
          break;
        }
      }
    }
    final made = <List<UserId>>[
      for (var i = 0; i < matched; i++) [firsts[i].userId, seconds[i].userId],
    ];
    final rest = <UserId>[
      for (final e in firsts.skip(matched)) e.userId,
      for (final e in seconds.skip(matched)) e.userId,
    ]..shuffle(random);
    for (var i = 0; i + 1 < rest.length; i += 2) {
      made.add([rest[i], rest[i + 1]]);
    }
    made.shuffle(random);
    return [
      for (var i = 0; i < made.length; i++)
        H2hCupPair(slot: i + 1, home: made[i][0], away: made[i][1]),
    ];
  }

  /// The pairs of a later round of the bracket: [survivors], in the order of
  /// the slots they won, two at a time (the first with the second, the third
  /// with the fourth, and so on). An odd one out has a bye and goes through
  /// without playing; the caller keeps him.
  static List<H2hCupPair> pairsOf(List<UserId> survivors) => [
    for (var i = 0; i + 1 < survivors.length; i += 2)
      H2hCupPair(slot: i ~/ 2 + 1, home: survivors[i], away: survivors[i + 1]),
  ];

  /// Decides one pair on the stage's fixtures; [homeEntry] and [awayEntry]
  /// carry the league month for the last tie-break.
  static H2hCupDecision decide({
    required H2hCupSide home,
    required H2hCupSide away,
    required H2hCupEntry homeEntry,
    required H2hCupEntry awayEntry,
  }) {
    if (!home.present && !away.present) {
      return const H2hCupDecision(
        winner: null,
        outcome: H2hCupOutcome.bothAbsent,
      );
    }
    if (home.present != away.present) {
      return H2hCupDecision(
        winner: home.present ? homeEntry.userId : awayEntry.userId,
        outcome: H2hCupOutcome.walkover,
      );
    }
    if (home.points != away.points) {
      return H2hCupDecision(
        winner: home.points > away.points ? homeEntry.userId : awayEntry.userId,
        outcome: H2hCupOutcome.points,
      );
    }
    if (home.exact != away.exact) {
      return H2hCupDecision(
        winner: home.exact > away.exact ? homeEntry.userId : awayEntry.userId,
        outcome: H2hCupOutcome.exact,
      );
    }
    // NK319_01
    if (home.direction != away.direction) {
      return H2hCupDecision(
        winner: home.direction > away.direction
            ? homeEntry.userId
            : awayEntry.userId,
        outcome: H2hCupOutcome.direction,
      );
    }
    return H2hCupDecision(
      winner: compareLeague(homeEntry, awayEntry) <= 0
          ? homeEntry.userId
          : awayEntry.userId,
      outcome: H2hCupOutcome.league,
    );
  }

  // NK305_01
  /// Negative when [a] had the better month in the league: prediction
  /// points, then exact scorelines, then league points, then the lower group
  /// number (owner decision 2026-11-24: the month's points first -- league
  /// points alone are not level between two groups).
  static int compareLeague(H2hCupEntry a, H2hCupEntry b) {
    if (a.pointsFor != b.pointsFor) {
      return b.pointsFor.compareTo(a.pointsFor);
    }
    if (a.exactCount != b.exactCount) {
      return b.exactCount.compareTo(a.exactCount);
    }
    if (a.leaguePoints != b.leaguePoints) {
      return b.leaguePoints.compareTo(a.leaguePoints);
    }
    return a.groupNumber.compareTo(b.groupNumber);
  }
}
