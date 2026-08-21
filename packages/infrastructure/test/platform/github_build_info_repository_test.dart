import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

http.Response _release(List<Map<String, String>> assets) => http.Response(
  jsonEncode({
    'published_at': '2026-01-02T00:00:00Z',
    'assets': assets
        .map((a) => {'name': a['name'], 'browser_download_url': a['url']})
        .toList(),
  }),
  200,
);

void main() {
  group('GithubBuildInfoRepository (split-per-abi)', () {
    test('maps each ABI apk with its checksum; arm64 is primary', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-abc.apk', 'url': 'https://x/arm64.apk'},
            {'name': 'nukhbaa-armeabi-v7a-abc.apk', 'url': 'https://x/v7a.apk'},
            {'name': 'checksums.json', 'url': 'https://x/checksums.json'},
          ]);
        }
        return http.Response(
          jsonEncode({
            'nukhbaa-arm64-v8a-abc.apk': 'AA',
            'nukhbaa-armeabi-v7a-abc.apk': 'BB',
          }),
          200,
        );
      });

      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Ok<LatestBuild>>());
      final build = (result as Ok<LatestBuild>).value;
      expect(build.assets.length, 2);
      expect(build.apkUrl, 'https://x/arm64.apk'); // arm64 primary
      expect(build.sha256, 'aa'); // lowercased
      expect(build.assets.map((a) => a.abi).toSet(), {
        'arm64-v8a',
        'armeabi-v7a',
      });
    });

    test(
      'apk without a checksum entry is skipped (=> transient error)',
      () async {
        final client = MockClient((req) async {
          if (req.url.host == 'api.github.com') {
            return _release([
              {
                'name': 'nukhbaa-arm64-v8a-abc.apk',
                'url': 'https://x/arm64.apk',
              },
              {'name': 'checksums.json', 'url': 'https://x/c.json'},
            ]);
          }
          return http.Response(jsonEncode(<String, String>{}), 200);
        });
        final result = await GithubBuildInfoRepository(client).fetchLatest();
        expect(result, isA<Err<LatestBuild>>());
      },
    );

    test('universal apk with checksum is used when no ABI assets', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-universal-abc.apk', 'url': 'https://x/uni.apk'},
            {'name': 'checksums.json', 'url': 'https://x/c.json'},
          ]);
        }
        return http.Response(
          jsonEncode({'nukhbaa-universal-abc.apk': 'CC'}),
          200,
        );
      });
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Ok<LatestBuild>>());
      final build = (result as Ok<LatestBuild>).value;
      expect(build.assets, isEmpty);
      expect(build.apkUrl, 'https://x/uni.apk');
      expect(build.sha256, 'cc');
    });

    test('non-200 from GitHub => transient error', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });

    test('malformed release (no published_at) => transient error', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'assets': <Object?>[]}), 200),
      );
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });

    test('release with no apk at all => transient error', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'notes.txt', 'url': 'https://x/notes.txt'},
          ]);
        }
        return http.Response('{}', 200);
      });
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });
  });
}
