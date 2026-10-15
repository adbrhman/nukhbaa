import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// The build number and the oldest supported build (batch 147): sent only
/// when known, so an older client reads the same payload it always did.
void main() {
  group('LatestBuildDto, batch 147', () {
    test('build number and minimum round-trip', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-10-15T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
        buildNumber: 214,
        minSupportedBuild: 210,
      );
      final Map<String, Object?> json = dto.toJson();

      expect(json['build_number'], 214);
      expect(json['min_supported_build'], 210);
      expect(LatestBuildDto.fromJson(json), dto);
    });

    test('neither is sent when unknown, and an old payload reads as '
        'unknown', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-10-15T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
      );

      expect(dto.toJson().containsKey('build_number'), isFalse);
      expect(dto.toJson().containsKey('min_supported_build'), isFalse);
      final LatestBuildDto old = LatestBuildDto.fromJson(const {
        'schema_version': 2,
        'published_at': '2026-10-15T00:00:00Z',
        'apk_url': 'https://example.com/a.apk',
      });
      expect(old.buildNumber, isNull);
      expect(old.minSupportedBuild, isNull);
    });
  });

  group('AppUpdatePolicyDto', () {
    test('round-trips, null included', () {
      const raised = AppUpdatePolicyDto(
        latestBuild: 214,
        minSupportedBuild: 214,
      );
      const cleared = AppUpdatePolicyDto(latestBuild: 214);

      expect(AppUpdatePolicyDto.fromJson(raised.toJson()), raised);
      expect(AppUpdatePolicyDto.fromJson(cleared.toJson()), cleared);
      expect(cleared.toJson()['min_supported_build'], isNull);
    });

    test('the request carries to_latest, read back only as a boolean', () {
      expect(AppUpdatePolicyDto.request(toLatest: true), {'to_latest': true});
      expect(AppUpdatePolicyDto.toLatestOf(const {'to_latest': false}), false);
      expect(AppUpdatePolicyDto.toLatestOf(const {'to_latest': 'yes'}), isNull);
      expect(AppUpdatePolicyDto.toLatestOf(const {}), isNull);
    });
  });
}
