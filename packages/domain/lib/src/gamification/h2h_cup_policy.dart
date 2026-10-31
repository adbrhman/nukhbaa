/// The Elite Cup of the head-to-head league (NK185, decided 2026-10-31).
///
/// After the 19 rounds of a month of the elite draw are all settled, the
/// first, second and third places of the four elite groups play three
/// separate cups ("paths"): the four first places, then the four second
/// places, then the four third places. Each path is a semi-final drawn at
/// random and a final; the paths never mix and a loser never moves to
/// another path.
///
/// The stages are played one after the other on the next qualifying days
/// (six fixtures or more): path 1's semi-finals, path 1's final, path 2's
/// semi-finals, ... A stage is never scheduled before the one before it is
/// settled, so the day number is an expectation, never a deadline. A stage
/// whose day leaves no fixture to play is carried to the next qualifying
/// day with the same pairs; nothing is lost and nothing is shortened.
///
/// A tie is judged on the stage's fixtures only (the monthly points never
/// decide it): the side that predicted wins over the side that did not;
/// with both present, the higher points, then more exact scorelines, then
/// the better league month (league points, prediction points, exact
/// scorelines, the group's number); with neither present both lose.
library;

import 'dart:math';

import 'package:domain/src/competition/competition_id.dart';
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
    'semi' => H2hCupRound.semi,
    'final' => H2hCupRound.finale,
    _ => null,
  };
}

/// One step of the cup's order: a path (the place 1, 2 or 3) and a round.
final class H2hCupStep {
  /// Creates a step.
  const H2hCupStep(this.place, this.round);

  /// The place in the elite groups the path is for: 1, 2 or 3.
  final int place;

  /// The round of the path.
  final H2hCupRound round;

  /// The expected league day of the step when nothing was late: 20 to 25.
  int get expectedDay =>
      H2hCupPolicy.firstCupDay +
      (place - 1) * 2 +
      (round == H2hCupRound.semi ? 0 : 1);

  @override
  bool operator ==(Object other) =>
      other is H2hCupStep && other.place == place && other.round == round;

  @override
  int get hashCode => Object.hash(place, round);

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

  /// 1 or 2 for the semi-finals, 1 for the final.
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

  /// Whether the side predicted at least one of them.
  bool get present => predicted > 0;
}

/// How a pair was decided.
enum H2hCupOutcome {
  /// More prediction points.
  points('points'),

  /// Level on points, more exact scorelines.
  exact('exact'),

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

  /// The steps of a cup, in the order they are played.
  static const List<H2hCupStep> order = <H2hCupStep>[
    H2hCupStep(1, H2hCupRound.semi),
    H2hCupStep(1, H2hCupRound.finale),
    H2hCupStep(2, H2hCupRound.semi),
    H2hCupStep(2, H2hCupRound.finale),
    H2hCupStep(3, H2hCupRound.semi),
    H2hCupStep(3, H2hCupRound.finale),
  ];

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
    return H2hCupDecision(
      winner: compareLeague(homeEntry, awayEntry) <= 0
          ? homeEntry.userId
          : awayEntry.userId,
      outcome: H2hCupOutcome.league,
    );
  }

  /// Negative when [a] had the better league month: league points, then
  /// prediction points, then exact scorelines, then the lower group number.
  static int compareLeague(H2hCupEntry a, H2hCupEntry b) {
    if (a.leaguePoints != b.leaguePoints) {
      return b.leaguePoints.compareTo(a.leaguePoints);
    }
    if (a.pointsFor != b.pointsFor) {
      return b.pointsFor.compareTo(a.pointsFor);
    }
    if (a.exactCount != b.exactCount) {
      return b.exactCount.compareTo(a.exactCount);
    }
    return a.groupNumber.compareTo(b.groupNumber);
  }
}
