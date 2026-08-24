import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the domain [ParticipantFixtureScore] aggregate onto the versioned
/// wire shape [ParticipantFixtureScoreDto] (API ADR §4), and a fixture's whole
/// list onto [FixtureScoresDto] — the per-fixture sibling of
/// `roundScoreToDto`/`roundScoresToJson` (docs/project-context.md, Axiom 4
/// Amendment).
///
/// Integrity boundary (Axioms 2/5): a score is a **server-produced read
/// value** — the grade token and points are echoed exactly as the domain
/// scoring function computed them; nothing here is client-writable. The grade
/// crosses the wire as its stable [FixtureScoreGrade.wireValue] token, never a
/// Dart enum name. Names a fixture by id only (Axiom 3); carries no
/// round/group reference (Axiom 4).
ParticipantFixtureScoreDto fixtureScoreToDto(
  ParticipantFixtureScore score, {
  String displayName = '',
}) {
  return ParticipantFixtureScoreDto(
    fixtureId: score.fixture.value,
    participantId: score.participantId.value,
    rulesetVersion: score.rulesetVersion,
    grade: score.result.grade.wireValue,
    points: score.points,
    displayName: displayName,
  );
}

/// Shapes every participant's [ParticipantFixtureScore] for a fixture into the
/// whole-fixture read response [FixtureScoresDto]. [fixtureId] is the
/// requested fixture (the same fixture every score shares).
Map<String, Object?> fixtureScoresToJson(
  String fixtureId,
  List<ParticipantFixtureScore> scores, {
  Map<String, String> displayNames = const {},
}) {
  return FixtureScoresDto(
    fixtureId: fixtureId,
    scores: [
      for (final score in scores)
        fixtureScoreToDto(
          score,
          displayName: displayNames[score.participantId.value] ?? '',
        ),
    ],
  ).toJson();
}
