import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('LatestBuildDto', () {
    test('round-trips through JSON', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-08-20T12:00:00.000Z',
        apkUrl: 'https://example.com/a.apk',
      );
      final decoded = LatestBuildDto.fromJson(dto.toJson());
      expect(decoded, dto);
      expect(decoded.schemaVersion, LatestBuildDto.currentSchemaVersion);
    });

    test('defaults schema_version to 1 when absent (back-compat)', () {
      final decoded = LatestBuildDto.fromJson(const {
        'published_at': '2026-08-20T12:00:00.000Z',
        'apk_url': 'https://example.com/a.apk',
      });
      expect(decoded.schemaVersion, 1);
      expect(decoded.publishedAt, '2026-08-20T12:00:00.000Z');
    });
  });
}
