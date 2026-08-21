import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('LatestBuildDto', () {
    test('schema v2 round-trips assets + sha256', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-01-01T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
        sha256: 'abc',
        assets: [
          BuildAssetDto(
            abi: 'arm64-v8a',
            url: 'https://example.com/arm64.apk',
            sha256: 'deadbeef',
          ),
        ],
      );
      final parsed = LatestBuildDto.fromJson(dto.toJson());
      expect(parsed, dto);
      expect(parsed.assets.single.abi, 'arm64-v8a');
      expect(parsed.schemaVersion, 2);
    });

    test('parses a schema-v1 payload (no assets/sha256)', () {
      final parsed = LatestBuildDto.fromJson(const {
        'schema_version': 1,
        'published_at': '2026-01-01T00:00:00Z',
        'apk_url': 'https://example.com/a.apk',
      });
      expect(parsed.assets, isEmpty);
      expect(parsed.sha256, isNull);
      expect(parsed.apkUrl, 'https://example.com/a.apk');
      expect(parsed.schemaVersion, 1);
    });

    test('parses multiple assets', () {
      final parsed = LatestBuildDto.fromJson(const {
        'schema_version': 2,
        'published_at': '2026-01-01T00:00:00Z',
        'apk_url': 'https://example.com/arm64.apk',
        'sha256': 'aa',
        'assets': [
          {'abi': 'arm64-v8a', 'url': 'https://x/arm64.apk', 'sha256': 'aa'},
          {'abi': 'armeabi-v7a', 'url': 'https://x/v7a.apk', 'sha256': 'bb'},
        ],
      });
      expect(parsed.assets.length, 2);
      expect(parsed.assets.map((a) => a.abi).toSet(), {
        'arm64-v8a',
        'armeabi-v7a',
      });
    });

    test('equality and hashCode are value-based', () {
      const a = LatestBuildDto(
        publishedAt: 't',
        apkUrl: 'u',
        sha256: 's',
        assets: [BuildAssetDto(abi: 'arm64-v8a', url: 'u', sha256: 's')],
      );
      const b = LatestBuildDto(
        publishedAt: 't',
        apkUrl: 'u',
        sha256: 's',
        assets: [BuildAssetDto(abi: 'arm64-v8a', url: 'u', sha256: 's')],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
