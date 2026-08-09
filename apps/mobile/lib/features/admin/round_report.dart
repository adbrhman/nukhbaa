import 'package:contracts/contracts.dart';

/// One participant's row in the round report: total points, ranking, and the
/// per-fixture breakdown (grade + points from the scored read, plus the raw
/// predicted scoreline from the admin's raw-predictions read).
///
/// Pure UI-layer merge — no network, no server logic. [rank] is 1-based,
/// assigned by [buildRoundReport] after sorting by [totalPoints] descending
/// (ties keep the server's stable participant-id order, never re-sorted by
/// name — there is no display name on this wire shape).
final class RoundReportRow {
  const RoundReportRow({
    required this.rank,
    required this.participantId,
    required this.totalPoints,
    required this.cells,
  });

  final int rank;
  final String participantId;
  final int totalPoints;

  /// One cell per fixture, in the round's fixture order (Axiom 3: named by
  /// fixture id only).
  final List<RoundReportCell> cells;
}

/// One fixture's cell for one participant: the server-computed grade/points
/// (always present — the round is scored) plus the raw predicted scoreline
/// (nullable: a participant who predicted after this cell's fixture was
/// already covered by a `missed` grade never submitted a raw score for it).
final class RoundReportCell {
  const RoundReportCell({
    required this.fixtureId,
    required this.grade,
    required this.points,
    this.homeGoals,
    this.awayGoals,
    this.isDouble = false,
  });

  final String fixtureId;

  /// The stable wire token: `exact_scoreline` / `correct_outcome` /
  /// `incorrect` / `missed`.
  final String grade;
  final int points;
  final int? homeGoals;
  final int? awayGoals;
  final bool isDouble;

  bool get hasRawScore => homeGoals != null && awayGoals != null;
}

/// Merges a scored round's [scores] (grades + points) with the admin's raw
/// [rawPredictions] (predicted scorelines) into a ranked [RoundReportRow]
/// list, sorted by total points descending.
///
/// The fixture *column order* is taken from the first participant's
/// [RoundScoreDto.fixtureResults] (every participant's scored round shares
/// the same fixture set, in the same order — the round's frozen ruleset), so
/// every row renders the same columns even when a raw prediction for one of
/// them is missing.
List<RoundReportRow> buildRoundReport({
  required RoundScoresDto scores,
  required List<PredictionDto> rawPredictions,
}) {
  // participantId -> fixtureId -> raw FixtureScoreDto, for O(1) lookup while
  // building each row's cells.
  final rawByParticipant = <String, Map<String, FixtureScoreDto>>{};
  for (final prediction in rawPredictions) {
    final byFixture = <String, FixtureScoreDto>{
      for (final s in prediction.fixtureScores) s.fixtureId: s,
    };
    rawByParticipant[prediction.participantId] = byFixture;
  }

  final sorted = [...scores.scores]
    ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

  return [
    for (var i = 0; i < sorted.length; i++)
      _row(rank: i + 1, score: sorted[i], rawByParticipant: rawByParticipant),
  ];
}

RoundReportRow _row({
  required int rank,
  required RoundScoreDto score,
  required Map<String, Map<String, FixtureScoreDto>> rawByParticipant,
}) {
  final raw = rawByParticipant[score.participantId];
  return RoundReportRow(
    rank: rank,
    participantId: score.participantId,
    totalPoints: score.totalPoints,
    cells: [
      for (final fr in score.fixtureResults)
        RoundReportCell(
          fixtureId: fr.fixtureId,
          grade: fr.grade,
          points: fr.points,
          homeGoals: raw?[fr.fixtureId]?.homeGoals,
          awayGoals: raw?[fr.fixtureId]?.awayGoals,
          isDouble: raw?[fr.fixtureId]?.isDouble ?? false,
        ),
    ],
  );
}
