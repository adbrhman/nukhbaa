import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('MyFixtureScoreDto', () {
    const scored = MyFixtureScoreDto(
      participantId: 'part1',
      fixtureId: 'f1',
      grade: 'exact_scoreline',
      points: 6,
      resultHomeGoals: 2,
      resultAwayGoals: 1,
    );

    test('round-trips through JSON', () {
      expect(MyFixtureScoreDto.fromJson(scored.toJson()), scored);
      expect(scored.toJson(), <String, Object?>{
        'schema_version': 1,
        'participant_id': 'part1',
        'fixture_id': 'f1',
        'grade': 'exact_scoreline',
        'points': 6,
        'result_home_goals': 2,
        'result_away_goals': 1,
      });
    });

    test('a result waiting to be scored leaves grade and points off', () {
      const waiting = MyFixtureScoreDto(
        participantId: 'part1',
        fixtureId: 'f2',
        resultHomeGoals: 0,
        resultAwayGoals: 0,
      );

      expect(waiting.toJson().keys, isNot(contains('grade')));
      expect(waiting.toJson().keys, isNot(contains('points')));
      final decoded = MyFixtureScoreDto.fromJson(waiting.toJson());
      expect(decoded.grade, isNull);
      expect(decoded.points, isNull);
      expect(decoded.resultHomeGoals, 0);
      expect(decoded, waiting);
    });

    test('defaults schema_version when absent', () {
      final decoded = MyFixtureScoreDto.fromJson(const {
        'participant_id': 'part1',
        'fixture_id': 'f1',
        'grade': 'incorrect',
        'points': 0,
      });
      expect(decoded.schemaVersion, 1);
      expect(decoded.resultHomeGoals, isNull);
    });

    test('value equality is by field, not identity', () {
      final same = MyFixtureScoreDto.fromJson(scored.toJson());
      expect(same, scored);
      expect(same.hashCode, scored.hashCode);
      expect(
        MyFixtureScoreDto.fromJson(<String, Object?>{
          ...scored.toJson(),
          'points': 3,
        }),
        isNot(scored),
      );
    });
  });
}
