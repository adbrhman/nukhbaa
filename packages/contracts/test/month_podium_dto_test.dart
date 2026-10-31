import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('the podium round-trips beside the champions', () {
    const dto = MonthChampionsDto(
      champions: [],
      podium: [
        MonthPodiumDto(
          seasonId: 's10',
          place: 3,
          userId: 'u3',
          displayName: 'ثالث',
          points: 120,
          exactCount: 6,
          decidedCount: 50,
        ),
        MonthPodiumDto(
          seasonId: 's10',
          place: 2,
          userId: 'u2',
          displayName: 'ثاني',
          points: 130,
          exactCount: 5,
          decidedCount: 50,
          photoUrl: '/champions/s10/photos/u2?v=1',
        ),
      ],
    );

    final back = MonthChampionsDto.fromJson(dto.toJson());

    expect([for (final p in back.podiumOf('s10')) p.place], [2, 3]);
    expect(back.podiumOf('s10').first.photoUrl, '/champions/s10/photos/u2?v=1');
    expect(back.podiumOf('s10').last.accuracyPercent, 12);
    expect(back.podiumOf('s9'), isEmpty);
  });

  test('a server before 0191 sends no podium', () {
    final back = MonthChampionsDto.fromJson(const {
      'schema_version': 1,
      'champions': <Object?>[],
    });

    expect(back.podium, isEmpty);
  });
}
