import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips through JSON', () {
    const dto = SeasonDuelWinsDto(wins: {'p1': 3, 'p2': 1});

    final back = SeasonDuelWinsDto.fromJson(dto.toJson());

    expect(back.wins, {'p1': 3, 'p2': 1});
    expect(back.of('p1'), 3);
    expect(back.of('p9'), 0);
    expect(dto.toJson()['schema_version'], 1);
  });

  test('a count that is not a positive integer is left out', () {
    final dto = SeasonDuelWinsDto.fromJson(const {
      'wins': {'p1': 2, 'p2': 0, 'p3': 'x'},
    });

    expect(dto.wins, {'p1': 2});
    expect(SeasonDuelWinsDto.fromJson(const {}).wins, isEmpty);
  });
}
