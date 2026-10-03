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

    test(
      'a new release still uploading: the last good build is kept',
      () async {
        // Y7GU: CI publishes the release, then uploads its APKs a minute
        // later. An update check in that minute used to fail.
        var uploading = false;
        final client = MockClient((req) async {
          if (req.url.path.endsWith('/releases/latest')) {
            return uploading
                ? _release([
                    {'name': 'notes.txt', 'url': 'https://x/new-notes.txt'},
                  ])
                : _release([
                    {
                      'name': 'nukhbaa-arm64-v8a-a.apk',
                      'url': 'https://x/a.apk',
                    },
                    {'name': 'checksums.json', 'url': 'https://x/a.json'},
                  ]);
          }
          return http.Response(
            jsonEncode({'nukhbaa-arm64-v8a-a.apk': 'AA'}),
            200,
          );
        });
        final repository = GithubBuildInfoRepository(
          client,
          cacheTtl: Duration.zero,
        );

        final first = await repository.fetchLatest();
        expect((first as Ok<LatestBuild>).value.apkUrl, 'https://x/a.apk');

        uploading = true;
        final during = await repository.fetchLatest();
        expect((during as Ok<LatestBuild>).value.apkUrl, 'https://x/a.apk');
      },
    );

    test(
      'a server started during the upload finds the previous release',
      () async {
        final client = MockClient((req) async {
          final String path = req.url.path;
          if (path.endsWith('/releases/latest')) {
            return _release([
              {'name': 'notes.txt', 'url': 'https://x/new-notes.txt'},
            ]);
          }
          if (path.endsWith('/releases')) {
            expect(req.url.queryParameters['per_page'], '5');
            return http.Response(
              jsonEncode([
                {
                  'published_at': '2026-10-03T17:20:00Z',
                  'assets': [
                    {
                      'name': 'notes.txt',
                      'browser_download_url': 'https://x/n',
                    },
                  ],
                },
                {
                  'published_at': '2026-10-03T16:00:00Z',
                  'draft': true,
                  'assets': [
                    {
                      'name': 'nukhbaa-arm64-v8a-d.apk',
                      'browser_download_url': 'https://x/draft.apk',
                    },
                    {
                      'name': 'checksums.json',
                      'browser_download_url': 'https://x/d.json',
                    },
                  ],
                },
                {
                  'published_at': '2026-10-03T14:00:00Z',
                  'assets': [
                    {
                      'name': 'nukhbaa-arm64-v8a-p.apk',
                      'browser_download_url': 'https://x/previous.apk',
                    },
                    {
                      'name': 'checksums.json',
                      'browser_download_url': 'https://x/p.json',
                    },
                  ],
                },
              ]),
              200,
            );
          }
          if (req.url.toString() == 'https://x/d.json') {
            return http.Response(
              jsonEncode({'nukhbaa-arm64-v8a-d.apk': 'DD'}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'nukhbaa-arm64-v8a-p.apk': 'PP'}),
            200,
          );
        });

        final result = await GithubBuildInfoRepository(client).fetchLatest();

        final build = (result as Ok<LatestBuild>).value;
        expect(build.apkUrl, 'https://x/previous.apk');
        expect(build.sha256, 'pp');
        expect(build.publishedAt, DateTime.utc(2026, 10, 3, 14));
      },
    );

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
