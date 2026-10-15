import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// The admin's counted fixtures (batch 156).
void main() {
  test('round-trips', () {
    const dto = FixtureScoreCountsDto(counts: {'f1': 12, 'f2': 3});

    expect(FixtureScoreCountsDto.fromJson(dto.toJson()).counts, dto.counts);
  });

  test('a count that is not a number is left out', () {
    final dto = FixtureScoreCountsDto.fromJson(const {
      'counts': {'f1': 2, 'f2': 'x'},
    });

    expect(dto.counts, {'f1': 2});
  });
}
