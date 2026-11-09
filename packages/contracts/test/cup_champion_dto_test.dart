import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('a cup champion round-trips, and leaves out what it lacks', () {
    const dto = CupChampionDto(
      monthStart: '2026-11-01',
      place: 2,
      how: 'walkover',
      userId: 'u-1',
      displayName: 'Ahmad',
      photoUrl: '/cup-champions/2026-11-01/2/photo?v=1',
    );

    final back = CupChampionDto.fromJson(dto.toJson());
    expect(back.monthStart, '2026-11-01');
    expect(back.place, 2);
    expect(back.how, 'walkover');
    expect(back.displayName, 'Ahmad');
    expect(back.photoUrl, '/cup-champions/2026-11-01/2/photo?v=1');
    expect(back.avatarUrl, isNull);
    expect(dto.toJson().containsKey('avatar_url'), isFalse);
  });

  test('the list reads its champions and tolerates a bare payload', () {
    final list = CupChampionsDto.fromJson(const {
      'schema_version': 1,
      'champions': [
        {'month_start': '2026-11-01', 'place': 1, 'user_id': 'u-1'},
        'not a map',
      ],
    });
    expect(list.champions, hasLength(1));
    expect(list.champions.single.how, '');
    expect(list.toJson()['schema_version'], 1);

    expect(CupChampionsDto.fromJson(const {}).champions, isEmpty);
  });
}
