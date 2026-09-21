import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('MyBadgesDto', () {
    const dto = MyBadgesDto(
      badges: [
        BadgeDto(
          code: 'first_prediction',
          current: 1,
          target: 1,
          unlockedAt: '2026-09-20T08:00:00.000Z',
        ),
        BadgeDto(code: 'predictions_25', current: 7, target: 25),
      ],
    );

    test('round-trips through JSON', () {
      expect(MyBadgesDto.fromJson(dto.toJson()), dto);
    });

    test('writes the wire names', () {
      final json = dto.toJson();
      expect(json['schema_version'], 1);
      final first = (json['badges']! as List).first as Map<String, Object?>;
      expect(first, {
        'code': 'first_prediction',
        'current': 1,
        'target': 1,
        'unlocked_at': '2026-09-20T08:00:00.000Z',
      });
    });

    test('a badge not held carries a null moment', () {
      final json = dto.toJson();
      final second = (json['badges']! as List)[1] as Map<String, Object?>;
      expect(second['unlocked_at'], isNull);
      expect(BadgeDto.fromJson(second).unlockedAt, isNull);
    });

    test('tolerates a body with no badges and missing keys', () {
      final parsed = MyBadgesDto.fromJson(const {});
      expect(parsed.badges, isEmpty);
      expect(parsed.schemaVersion, 1);

      final line = BadgeDto.fromJson(const {'code': 'league_elite'});
      expect(line.current, 0);
      expect(line.target, 1);
      expect(line.unlockedAt, isNull);
    });
  });
}
