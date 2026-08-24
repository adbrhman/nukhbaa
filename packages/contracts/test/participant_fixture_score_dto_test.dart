import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ParticipantFixtureScoreDto', () {
    const dto = ParticipantFixtureScoreDto(
      fixtureId: 'f1',
      participantId: 'part1',
      rulesetVersion: 1,
      grade: 'exact_scoreline',
      points: 6,
      displayName: 'Ali',
    );

    test('round-trips through JSON', () {
      expect(ParticipantFixtureScoreDto.fromJson(dto.toJson()), dto);
    });

    test('carries no round reference on the wire', () {
      expect(dto.toJson().keys, isNot(contains('round_id')));
    });

    test('defaults display_name/schema_version when absent (back-compat)', () {
      final decoded = ParticipantFixtureScoreDto.fromJson(const {
        'fixture_id': 'f1',
        'participant_id': 'part1',
        'ruleset_version': 1,
        'grade': 'incorrect',
        'points': 0,
      });
      expect(decoded.displayName, '');
      expect(decoded.schemaVersion, 1);
    });

    test('value equality is by field, not identity', () {
      final same = ParticipantFixtureScoreDto.fromJson(dto.toJson());
      expect(same, dto);
      expect(same.hashCode, dto.hashCode);
    });
  });

  group('FixtureScoresDto', () {
    test('round-trips, preserving score order', () {
      const dto = FixtureScoresDto(
        fixtureId: 'f1',
        scores: [
          ParticipantFixtureScoreDto(
            fixtureId: 'f1',
            participantId: 'p1',
            rulesetVersion: 1,
            grade: 'exact_scoreline',
            points: 6,
          ),
          ParticipantFixtureScoreDto(
            fixtureId: 'f1',
            participantId: 'p2',
            rulesetVersion: 1,
            grade: 'incorrect',
            points: 0,
          ),
        ],
      );
      final decoded = FixtureScoresDto.fromJson(dto.toJson());
      expect(decoded, dto);
      expect(decoded.scores.first.participantId, 'p1');
      expect(decoded.scores.last.participantId, 'p2');
    });

    test('an empty score list is legitimate', () {
      const dto = FixtureScoresDto(fixtureId: 'f1', scores: []);
      final decoded = FixtureScoresDto.fromJson(dto.toJson());
      expect(decoded.scores, isEmpty);
    });
  });
}
