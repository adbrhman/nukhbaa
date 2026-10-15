import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// Projects a [MyFixtureScore] onto the versioned wire shape
/// [MyFixtureScoreDto] (`GET /me/fixture-scores`, script 75).
///
/// Integrity boundary (Axioms 2/5): the grade and points are echoed exactly
/// as scoring stored them -- the grade as its stable `wireValue` token, never
/// a Dart enum name -- and the final score as recorded. Nothing here is
/// client-writable, and nothing is derived.
MyFixtureScoreDto myFixtureScoreToDto(MyFixtureScore score) {
  return MyFixtureScoreDto(
    participantId: score.participantId.value,
    fixtureId: score.fixture.value,
    grade: score.grade?.wireValue,
    points: score.points,
    resultHomeGoals: score.result?.homeGoals,
    resultAwayGoals: score.result?.awayGoals,
  );
}
