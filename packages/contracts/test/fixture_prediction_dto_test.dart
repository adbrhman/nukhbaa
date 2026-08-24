import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FixturePredictionCommandDto', () {
    test('round-trips through JSON with snake_case keys', () {
      const dto = FixturePredictionCommandDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );
      final json = dto.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'schema_version',
          'home_goals',
          'away_goals',
          'is_double',
        ]),
      );
      expect(FixturePredictionCommandDto.fromJson(json), dto);
    });

    test('defaults is_double to false when absent (back-compat)', () {
      final decoded = FixturePredictionCommandDto.fromJson(const {
        'home_goals': 0,
        'away_goals': 0,
      });
      expect(decoded.isDouble, isFalse);
      expect(decoded.schemaVersion, 1);
    });

    test(
      'body carries no fixture/participant field (both server-resolved)',
      () {
        const dto = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 1);
        expect(dto.toJson().keys, isNot(contains('fixture_id')));
        expect(dto.toJson().keys, isNot(contains('participant_id')));
      },
    );

    test('value equality is by field, not identity', () {
      const a = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 0);
      const b = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 0);
      const c = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('FixturePredictionDto', () {
    const dto = FixturePredictionDto(
      id: 'p1',
      participantId: 'part1',
      fixtureId: 'f1',
      submittedAt: '2026-08-01T12:00:00Z',
      homeGoals: 2,
      awayGoals: 0,
      isDouble: true,
    );

    test('round-trips through JSON', () {
      expect(FixturePredictionDto.fromJson(dto.toJson()), dto);
    });

    test('carries no round reference on the wire', () {
      expect(dto.toJson().keys, isNot(contains('round_id')));
    });

    test('defaults schema_version to 1 when absent (back-compat)', () {
      final decoded = FixturePredictionDto.fromJson(const {
        'id': 'p1',
        'participant_id': 'part1',
        'fixture_id': 'f1',
        'submitted_at': '2026-08-01T12:00:00Z',
        'home_goals': 1,
        'away_goals': 1,
      });
      expect(decoded.schemaVersion, 1);
      expect(decoded.isDouble, isFalse);
    });

    test('value equality is by field, not identity', () {
      final same = FixturePredictionDto.fromJson(dto.toJson());
      expect(same, dto);
      expect(same.hashCode, dto.hashCode);
    });
  });
}
