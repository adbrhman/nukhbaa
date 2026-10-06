import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ScreenViewsReportDto', () {
    test('round-trips through JSON', () {
      const dto = ScreenViewsReportDto(opens: {'home': 3, 'duels': 1});

      expect(dto.toJson(), {
        'schema_version': 1,
        'opens': {'home': 3, 'duels': 1},
      });
      expect(ScreenViewsReportDto.fromJson(dto.toJson()).opens, {
        'home': 3,
        'duels': 1,
      });
    });

    test('a count that is not an integer is left out', () {
      final dto = ScreenViewsReportDto.fromJson(const {
        'opens': {'home': 2, 'duels': 'x', 'badges': null},
      });

      expect(dto.opens, {'home': 2});
    });

    test('a missing map reads as empty', () {
      expect(ScreenViewsReportDto.fromJson(const {}).opens, isEmpty);
    });
  });

  test('ScreenViewsAckDto round-trips through JSON', () {
    const dto = ScreenViewsAckDto(recorded: 4);

    expect(dto.toJson(), {'schema_version': 1, 'recorded': 4});
    expect(ScreenViewsAckDto.fromJson(dto.toJson()).recorded, 4);
  });
}
