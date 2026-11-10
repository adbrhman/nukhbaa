import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// The oldest supported Google Play build (script 253): sent only when an
/// admin set one, so the APK in players' hands reads the same payload it
/// always did, and the admin's request says a number or null.
void main() {
  group('LatestBuildDto, script 253', () {
    test('the Play minimum round-trips beside the APK one', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-11-10T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
        buildNumber: 870,
        minSupportedBuild: 870,
        minSupportedPlayBuild: 845,
      );
      final Map<String, Object?> json = dto.toJson();

      expect(json['min_supported_build'], 870);
      expect(json['min_supported_play_build'], 845);
      expect(LatestBuildDto.fromJson(json), dto);
      expect(
        LatestBuildDto.fromJson(json),
        isNot(
          const LatestBuildDto(
            publishedAt: '2026-11-10T00:00:00Z',
            apkUrl: 'https://example.com/a.apk',
            buildNumber: 870,
            minSupportedBuild: 870,
          ),
        ),
      );
    });

    test('not sent when unset, and an older payload reads as unset', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-11-10T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
        minSupportedBuild: 870,
      );

      expect(dto.toJson().containsKey('min_supported_play_build'), isFalse);
      expect(
        LatestBuildDto.fromJson(const {
          'schema_version': 2,
          'published_at': '2026-11-10T00:00:00Z',
          'apk_url': 'https://example.com/a.apk',
          'min_supported_build': 870,
        }).minSupportedPlayBuild,
        isNull,
      );
    });
  });

  group('PlayUpdatePolicyDto', () {
    test('the request carries a number or null, and is read back', () {
      final ({bool valid, int? value}) stored =
          PlayUpdatePolicyDto.buildNumberOf(
            PlayUpdatePolicyDto.request(buildNumber: 845),
          );
      final ({bool valid, int? value}) cleared =
          PlayUpdatePolicyDto.buildNumberOf(
            PlayUpdatePolicyDto.request(buildNumber: null),
          );

      expect(stored.valid, isTrue);
      expect(stored.value, 845);
      expect(cleared.valid, isTrue);
      expect(cleared.value, isNull);
    });

    test('a missing or non-integer number is not valid', () {
      expect(PlayUpdatePolicyDto.buildNumberOf(const {}).valid, isFalse);
      expect(
        PlayUpdatePolicyDto.buildNumberOf(const {'build_number': '845'}).valid,
        isFalse,
      );
      expect(
        PlayUpdatePolicyDto.buildNumberOf(const {'build_number': 845.5}).valid,
        isFalse,
      );
    });

    test('the answer round-trips', () {
      const dto = PlayUpdatePolicyDto(minSupportedPlayBuild: 845);

      expect(dto.toJson()['min_supported_play_build'], 845);
      expect(PlayUpdatePolicyDto.fromJson(dto.toJson()), dto);
      expect(
        PlayUpdatePolicyDto.fromJson(
          const PlayUpdatePolicyDto().toJson(),
        ).minSupportedPlayBuild,
        isNull,
      );
    });
  });
}
