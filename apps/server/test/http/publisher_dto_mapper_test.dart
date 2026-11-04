import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('a setting goes to the wire and back unchanged', () {
    final setting = PlatformIntensity.defaults(
      PublishPlatform.instagram,
    ).copyWith(enabled: true, goals: GoalCoverage.key, dailyCap: 5);

    final wire = PublisherSettingDto.fromJson(
      publisherSettingDto(setting).toJson(),
    );
    final back = publisherSettingOf(wire);

    expect(back, Result<PlatformIntensity>.ok(setting));
  });

  test('an unknown platform or coverage is refused', () {
    final bad = publisherSettingOf(
      const PublisherSettingDto(
        platform: 'tiktok',
        enabled: true,
        goals: 'all',
        finalResult: true,
        holdSeconds: 180,
        minGapSeconds: 0,
        dailyCap: 5,
      ),
    );

    expect(bad, isA<Err<PlatformIntensity>>());
    expect(
      (bad as Err<PlatformIntensity>).error.code,
      'publisher.setting_invalid',
    );
  });

  test('the overview lists every platform, in order, and the linked ones', () {
    final dto = publisherOverviewDto(
      PublisherOverview(
        mode: PublisherMode.dryRun,
        settings: <PublishPlatform, PlatformIntensity>{
          PublishPlatform.x: PlatformIntensity.defaults(PublishPlatform.x),
        },
        candidates: <CoverageCandidate>[
          CoverageCandidate(
            fixtureId: 'f1',
            homeName: 'الهلال',
            awayName: 'النصر',
            leagueName: 'دوري روشن السعودي',
            kickoffAt: DateTime.utc(2026, 11, 7, 17),
            covered: true,
          ),
        ],
        posts: <PostView>[
          PostView(
            id: 'p1',
            fixtureId: 'f1',
            matchLabel: 'الهلال - النصر',
            kind: PostKind.goal,
            platform: PublishPlatform.facebook,
            state: PostState.published,
            body: 'هدف',
            cardPath: 'goals/f1/g.jpg',
            createdAt: DateTime.utc(2026, 11, 7, 17, 15),
            attempts: 1,
            reactions: 9,
          ),
        ],
        badges: const <StoredBadge>[],
        linked: <PublishPlatform>{PublishPlatform.facebook},
      ),
    );

    final json = PublisherOverviewDto.fromJson(dto.toJson());
    expect(json.mode, 'dry_run');
    expect(json.settings.map((s) => s.platform), <String>[
      'facebook',
      'instagram',
      'x',
    ]);
    expect(json.candidates.single.kickoffAt, '2026-11-07T17:00:00.000Z');
    expect(json.posts.single.hasCard, isTrue);
    expect(json.posts.single.state, 'published');
    expect(json.posts.single.reactions, 9);
    expect(json.linked, <String>['facebook']);
  });
}
