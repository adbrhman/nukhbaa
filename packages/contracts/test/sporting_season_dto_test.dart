import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('SportingSeasonLeaderboardDto survives a JSON round trip', () {
    const dto = SportingSeasonLeaderboardDto(
      label: '2026/2027',
      entries: [
        SportingSeasonEntryDto(
          rank: 1,
          userId: '00000000-0000-0000-0000-000000000001',
          displayName: 'عبدالرحمن',
          totalPoints: 45,
          fixturesScored: 70,
          exactCount: 7,
          decidedCount: 64,
          monthsPlayed: 2,
        ),
      ],
    );

    expect(SportingSeasonLeaderboardDto.fromJson(dto.toJson()), dto);
  });

  test('a missing entries key decodes to an empty board', () {
    final dto = SportingSeasonLeaderboardDto.fromJson(const {
      'label': '2026/2027',
    });
    expect(dto.entries, isEmpty);
  });
}
