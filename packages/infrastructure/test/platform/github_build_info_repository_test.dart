import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

http.Response _release(
  List<Map<String, String>> assets, {
  String name = 'Build abc',
}) => http.Response(
  jsonEncode({
    'name': name,
    'published_at': '2026-01-02T00:00:00Z',
    'assets': assets
        .map((a) => {'name': a['name'], 'browser_download_url': a['url']})
        .toList(),
  }),
  200,
);

void main() {
  group('the build number in a release name (batch 147)', () {
    test('read from "Build <sha> #<number>"', () {
      expect(
        GithubBuildInfoRepository.buildNumberOf('Build 4e0c6e9 #812'),
        812,
      );
    });

    test('absent from an older name, or not a name', () {
      expect(GithubBuildInfoRepository.buildNumberOf('Build 4e0c6e9'), isNull);
      expect(GithubBuildInfoRepository.buildNumberOf('Build #0'), isNull);
      expect(GithubBuildInfoRepository.buildNumberOf(null), isNull);
      expect(GithubBuildInfoRepository.buildNumberOf(7), isNull);
    });

    test('carried by the release read', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-abc.apk', 'url': 'https://x/arm64.apk'},
            {'name': 'checksums.json', 'url': 'https://x/checksums.json'},
          ], name: 'Build abc #812');
        }
        return http.Response(
          jsonEncode({'nukhbaa-arm64-v8a-abc.apk': 'AA'}),
          200,
        );
      });

      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect((result as Ok<LatestBuild>).value.buildNumber, 812);
    });
  });

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

    test('the links page copy (nukhbaa.apk, no checksum) is ignored', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa.apk', 'url': 'https://x/stable.apk'},
            {'name': 'nukhbaa-arm64-v8a-abc.apk', 'url': 'https://x/arm64.apk'},
            {'name': 'checksums.json', 'url': 'https://x/checksums.json'},
          ]);
        }
        return http.Response(
          jsonEncode({'nukhbaa-arm64-v8a-abc.apk': 'AA'}),
          200,
        );
      });

      final result = await GithubBuildInfoRepository(client).fetchLatest();
      final build = (result as Ok<LatestBuild>).value;
      expect(build.apkUrl, 'https://x/arm64.apk');
      expect(build.assets.map((a) => a.url), ['https://x/arm64.apk']);
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

    test(
      'an APK with its own digest needs no checksums.json (batch 157)',
      () async {
        final List<Uri> asked = <Uri>[];
        final client = MockClient((req) async {
          asked.add(req.url);
          return http.Response(
            jsonEncode({
              'name': 'Build abc #723',
              'published_at': '2026-10-15T23:12:00Z',
              'assets': [
                {
                  'name': 'nukhbaa-arm64-v8a-abc.apk',
                  'browser_download_url': 'https://x/arm64.apk',
                  'digest': 'sha256:${'AB' * 32}',
                },
                {
                  'name': 'nukhbaa.apk',
                  'browser_download_url': 'https://x/stable.apk',
                  'digest': 'sha256:${'cd' * 32}',
                },
                {
                  'name': 'checksums.json',
                  'browser_download_url': 'https://x/checksums.json',
                  'digest': 'sha256:${'ef' * 32}',
                },
              ],
            }),
            200,
          );
        });

        final result = await GithubBuildInfoRepository(client).fetchLatest();

        final build = (result as Ok<LatestBuild>).value;
        expect(build.apkUrl, 'https://x/arm64.apk');
        expect(build.sha256, 'ab' * 32);
        expect(build.assets.map((a) => a.url), ['https://x/arm64.apk']);
        expect(build.buildNumber, 723);
        expect(asked, hasLength(1), reason: 'one GitHub call, no download');
      },
    );

    test('a digest that is not sha256 is not trusted', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'published_at': '2026-10-15T23:12:00Z',
              'assets': [
                {
                  'name': 'nukhbaa-arm64-v8a-abc.apk',
                  'browser_download_url': 'https://x/arm64.apk',
                  'digest': 'md5:0123',
                },
                {
                  'name': 'checksums.json',
                  'browser_download_url': 'https://x/checksums.json',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'nukhbaa-arm64-v8a-abc.apk': 'AA'}),
          200,
        );
      });

      final result = await GithubBuildInfoRepository(client).fetchLatest();

      expect((result as Ok<LatestBuild>).value.sha256, 'aa');
    });

    test('a failed answer is reused, not asked again at every open '
        '(batch 157)', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('rate limited', 403);
      });
      final repository = GithubBuildInfoRepository(client);

      final first = await repository.fetchLatest();
      final callsForOne = calls;
      final second = await repository.fetchLatest();
      final third = await repository.fetchLatest();

      expect(first, isA<Err<LatestBuild>>());
      expect(second, isA<Err<LatestBuild>>());
      expect(third, isA<Err<LatestBuild>>());
      expect(calls, callsForOne, reason: 'the failure is remembered');
      expect(
        (first as Err<LatestBuild>).error.cause.toString(),
        contains('403'),
      );
    });

    test('once the failure is old, GitHub is asked again', () async {
      var failing = true;
      final client = MockClient((req) async {
        if (failing) return http.Response('down', 502);
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-a.apk', 'url': 'https://x/a.apk'},
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
        failureTtl: Duration.zero,
      );

      expect(await repository.fetchLatest(), isA<Err<LatestBuild>>());
      failing = false;
      final again = await repository.fetchLatest();

      expect((again as Ok<LatestBuild>).value.apkUrl, 'https://x/a.apk');
    });

    test('a token goes to the API only, never to the download', () async {
      final Map<String, String?> auth = <String, String?>{};
      final client = MockClient((req) async {
        auth[req.url.host] = req.headers['Authorization'];
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-a.apk', 'url': 'https://x/a.apk'},
            {'name': 'checksums.json', 'url': 'https://x/a.json'},
          ]);
        }
        return http.Response(
          jsonEncode({'nukhbaa-arm64-v8a-a.apk': 'AA'}),
          200,
        );
      });

      await GithubBuildInfoRepository(client, token: ' t0k ').fetchLatest();

      expect(auth['api.github.com'], 'Bearer t0k');
      expect(auth['x'], isNull);
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
