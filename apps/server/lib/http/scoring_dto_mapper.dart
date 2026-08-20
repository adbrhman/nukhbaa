import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the domain [RoundScore] aggregate onto the versioned wire shape
/// [RoundScoreDto] (API ADR §4), and a list of them onto [RoundScoresDto].
///
/// This mapping lives here, once, so the scored-results read surface
/// (`GET /rounds/{id}/scores`) shapes a score identically everywhere.
///
/// Integrity boundary (Axioms 2/5): a score is a **server-produced read
/// value** — the grade token and points are echoed exactly as the domain
/// scoring function computed them; nothing here is client-writable, and there
/// is no inverse (the client never sends a score). The grade crosses the wire
/// as its stable [FixtureScoreGrade.wireValue] token (`exact_scoreline` /
/// `correct_outcome` / `incorrect`), never a Dart enum name, so a persisted or
/// transmitted value can never drift silently. The per-fixture breakdown echoes
/// the stored list order the aggregate preserves (the prediction's order).
/// Names a fixture by id only (Axiom 3); carries no group reference (Axiom 4).
RoundScoreDto roundScoreToDto(RoundScore score, {String displayName = ''}) {
  return RoundScoreDto(
    roundId: score.roundId.value,
    participantId: score.participantId.value,
    rulesetVersion: score.rulesetVersion,
    totalPoints: score.totalPoints,
    displayName: displayName,
    fixtureResults: [
      for (final fixture in score.fixtureResults)
        FixtureScoreResultDto(
          fixtureId: fixture.fixture.value,
          grade: fixture.grade.wireValue,
          points: fixture.points,
        ),
    ],
  );
}

/// Shapes every participant's [RoundScore] for a round into the whole-round
/// read response [RoundScoresDto], preserving the use-case's participant-ordered
/// list. [roundId] is the requested round (the same round every score shares).
Map<String, Object?> roundScoresToJson(
  String roundId,
  List<RoundScore> scores, {
  Map<String, String> displayNames = const {},
}) {
  return RoundScoresDto(
    roundId: roundId,
    scores: [
      for (final score in scores)
        roundScoreToDto(
          score,
          displayName: displayNames[score.participantId.value] ?? '',
        ),
    ],
  ).toJson();
}

/// Projects one [RoundReportEntry] onto its wire shape [RoundReportRowDto]
/// (Task 5). A pure server-computed read value, same integrity boundary as
/// [roundScoreToDto].
RoundReportRowDto roundReportEntryToDto(RoundReportEntry entry) {
  return RoundReportRowDto(
    participantId: entry.participantId.value,
    correctCount: entry.correctCount,
    incorrectCount: entry.incorrectCount,
    totalPoints: entry.totalPoints,
  );
}

/// Shapes every participant's [RoundReportEntry] for a round into the
/// whole-round report response [RoundReportDto].
Map<String, Object?> roundReportToJson(
  String roundId,
  List<RoundReportEntry> entries,
) {
  return RoundReportDto(
    roundId: roundId,
    rows: [for (final e in entries) roundReportEntryToDto(e)],
  ).toJson();
}
