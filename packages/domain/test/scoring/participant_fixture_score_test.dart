import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  const fixtureA = FixtureRef('11111111-1111-1111-1111-111111111111');
  const fixtureB = FixtureRef('22222222-2222-2222-2222-222222222222');
  const participantId = ParticipantId('33333333-3333-3333-3333-333333333333');

  group('ParticipantFixtureScore.fromGraded', () {
    test('builds a score when the result matches the fixture', () {
      const result = FixtureScoreResult(
        fixture: fixtureA,
        grade: FixtureScoreGrade.exactScoreline,
        points: 3,
      );

      final scored = ParticipantFixtureScore.fromGraded(
        fixture: fixtureA,
        participantId: participantId,
        rulesetVersion: 1,
        result: result,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final value = (scored as Ok<ParticipantFixtureScore>).value;
      expect(value.fixture, fixtureA);
      expect(value.participantId, participantId);
      expect(value.rulesetVersion, 1);
      expect(value.points, 3);
    });

    test('rejects a result for a different fixture', () {
      const result = FixtureScoreResult(
        fixture: fixtureB,
        grade: FixtureScoreGrade.incorrect,
        points: 0,
      );

      final scored = ParticipantFixtureScore.fromGraded(
        fixture: fixtureA,
        participantId: participantId,
        rulesetVersion: 1,
        result: result,
      );

      expect(scored, isA<Err<ParticipantFixtureScore>>());
      expect(
        (scored as Err<ParticipantFixtureScore>).error.code,
        'scoring.fixture_mismatch',
      );
    });
  });
}
