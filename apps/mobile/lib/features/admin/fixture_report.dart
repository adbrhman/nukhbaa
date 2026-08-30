import 'package:contracts/contracts.dart';

/// One participant's row in the fixture report: rank, total points for this
/// single fixture, the server-computed grade, and the raw predicted
/// scoreline from the admin's raw-predictions read.
///
/// Pure UI-layer merge — no network, no server logic. [rank] is 1-based,
/// assigned by [buildFixtureReport] after sorting by [points] descending
/// (ties keep the server's stable participant-id order, never re-sorted by
/// name — there is no display name guaranteed on this wire shape).
///
/// The per-fixture sibling of the retired `RoundReportRow` — one
/// fixture means one grade/points pair per participant, so there is no
/// per-fixture cell list to wrap (unlike the round report's `cells`).
final class FixtureReportRow {
  const FixtureReportRow({
    required this.rank,
    required this.participantId,
    required this.grade,
    required this.points,
    this.displayName = '',
    this.homeGoals,
    this.awayGoals,
    this.isDouble = false,
  });

  final int rank;
  final String participantId;
  final String displayName;

  /// The stable wire token: `exact_scoreline` / `correct_outcome` /
  /// `incorrect` / `missed` / `pending`.
  final String grade;
  final int points;

  /// The raw predicted scoreline (nullable: a participant who never
  /// predicted this fixture is covered by a `missed` grade with no raw
  /// score).
  final int? homeGoals;
  final int? awayGoals;
  final bool isDouble;

  bool get hasRawScore => homeGoals != null && awayGoals != null;
}

/// Merges a scored fixture's [scores] (grades + points) with the admin's raw
/// [rawPredictions] (predicted scorelines) into a ranked [FixtureReportRow]
/// list, sorted by points descending. The per-fixture sibling of
/// the retired `buildRoundReport`.
List<FixtureReportRow> buildFixtureReport({
  required FixtureScoresDto scores,
  required List<FixturePredictionDto> rawPredictions,
}) {
  final rawByParticipant = <String, FixturePredictionDto>{
    for (final p in rawPredictions) p.participantId: p,
  };

  final sorted = [...scores.scores]
    ..sort((a, b) => b.points.compareTo(a.points));

  return [
    for (var i = 0; i < sorted.length; i++)
      _row(rank: i + 1, score: sorted[i], rawByParticipant: rawByParticipant),
  ];
}

FixtureReportRow _row({
  required int rank,
  required ParticipantFixtureScoreDto score,
  required Map<String, FixturePredictionDto> rawByParticipant,
}) {
  final raw = rawByParticipant[score.participantId];
  return FixtureReportRow(
    rank: rank,
    participantId: score.participantId,
    displayName: score.displayName,
    grade: score.grade,
    points: score.points,
    homeGoals: raw?.homeGoals,
    awayGoals: raw?.awayGoals,
    isDouble: raw?.isDouble ?? false,
  );
}
