import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('a champion round-trips, with its accuracy', () {
    const dto = MonthChampionDto(
      seasonId: 's-9',
      seasonLabel: '09/2026',
      userId: 'u-1',
      displayName: 'Ahmad',
      points: 42,
      exactCount: 6,
      decidedCount: 30,
      referralPoints: 2,
      crownedAt: '2026-10-01T12:00:00.000Z',
      celebrateUntil: '2026-10-03T12:00:00.000Z',
      photoUrl: '/champions/s-9/photos/u-1?v=1',
      prize: '150 ريال سعودي',
    );

    final back = MonthChampionDto.fromJson(dto.toJson());
    expect(back.prize, '150 ريال سعودي');

    expect(back.seasonLabel, '09/2026');
    expect(back.points, 42);
    expect(back.celebrateUntil, '2026-10-03T12:00:00.000Z');
    expect(back.photoUrl, '/champions/s-9/photos/u-1?v=1');
    expect(back.avatarUrl, isNull);
    expect(back.accuracyPercent, 20);
    expect(dto.toJson().containsKey('avatar_url'), isFalse);
  });

  test('the crowning body carries the prize only when there is one', () {
    expect(
      const CrownChampionsDto(userIds: ['u-1']).toJson().containsKey('prize'),
      isFalse,
    );
    final body = const CrownChampionsDto(
      userIds: ['u-1'],
      prize: '150 ريال سعودي',
    ).toJson();
    expect(CrownChampionsDto.prizeOf(body), '150 ريال سعودي');
    expect(CrownChampionsDto.prizeOf(const {'prize': 150}), isNull);
    expect(MonthChampionDto.fromJson(const {}).prize, isNull);
  });

  test('nothing decided means no accuracy', () {
    final dto = MonthChampionDto.fromJson(const {'decided_count': 0});
    expect(dto.accuracyPercent, isNull);
  });

  test('the list and the preview round-trip', () {
    final list = MonthChampionsDto.fromJson(
      const MonthChampionsDto(
        champions: [
          MonthChampionDto(
            seasonId: 's-9',
            seasonLabel: '09/2026',
            userId: 'u-1',
            displayName: 'Ahmad',
            points: 42,
            exactCount: 6,
            decidedCount: 30,
            referralPoints: 0,
            crownedAt: '2026-10-01T12:00:00.000Z',
            celebrateUntil: '2026-10-03T12:00:00.000Z',
          ),
        ],
      ).toJson(),
    );
    expect(list.champions.single.userId, 'u-1');

    final preview = ChampionCandidatesDto.fromJson(
      const ChampionCandidatesDto(
        seasonId: 's-9',
        seasonLabel: '09/2026',
        ended: true,
        unscoredFixtures: 1,
        crowned: ['u-1'],
        candidates: [
          ChampionCandidateDto(
            rank: 1,
            userId: 'u-1',
            displayName: 'Ahmad',
            points: 42,
            exactCount: 6,
            decidedCount: 30,
            referralPoints: 0,
          ),
        ],
      ).toJson(),
    );
    expect(preview.ended, isTrue);
    expect(preview.unscoredFixtures, 1);
    expect(preview.crowned, ['u-1']);
    expect(preview.candidates.single.rank, 1);
  });

  test('the crowning body reads only what it can trust', () {
    expect(
      CrownChampionsDto.userIdsOf(const {
        'user_ids': ['a', 'b'],
      }),
      ['a', 'b'],
    );
    expect(CrownChampionsDto.userIdsOf(const {}), isNull);
    expect(CrownChampionsDto.userIdsOf(const {'user_ids': 'a'}), isNull);
    expect(
      CrownChampionsDto.userIdsOf(const {
        'user_ids': ['a', 1],
      }),
      isNull,
    );
    expect(CrownChampionsDto.forceOf(const {'force': true}), isTrue);
    expect(CrownChampionsDto.forceOf(const {'force': 'yes'}), isFalse);
    expect(const CrownChampionsDto(userIds: ['a'], force: true).toJson(), {
      'user_ids': ['a'],
      'force': true,
    });
  });
}
