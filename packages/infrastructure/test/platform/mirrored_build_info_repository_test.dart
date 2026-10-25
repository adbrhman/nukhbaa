import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Script 144: the update check (`GetLatestBuild`, behind
/// `GET /app/latest-build`) over the real GitHub reader, wrapped as the
/// composition root wraps it: each APK's address moves to the web mirror
/// once the mirror serves that very file, and stays GitHub's until then.

const String _sha = 'abc1234';
const String _arm64 = 'nukhbaa-arm64-v8a-$_sha.apk';
const String _v7a = 'nukhbaa-armeabi-v7a-$_sha.apk';
const String _download =
    'https://github.com/adbrhman/nukhbaa/releases/download/build-$_sha';
const String _digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// GitHub's API and the mirror, counting the mirror's `HEAD`s.
final class _Hosts {
  /// The files the mirror serves, and the type it serves them with.
  final Map<String, String> mirror = <String, String>{};
  final List<String> heads = <String>[];

  http.Client get client => MockClient((http.Request request) async {
    if (request.url.host == 'api.github.com') {
      return http.Response(
        jsonEncode(<String, Object?>{
          'name': 'Build $_sha #780',
          'published_at': '2026-10-25T09:00:00Z',
          'assets': <Map<String, Object?>>[
            <String, Object?>{
              'name': _arm64,
              'browser_download_url': '$_download/$_arm64',
              'digest': _digestA,
            },
            <String, Object?>{
              'name': _v7a,
              'browser_download_url': '$_download/$_v7a',
              'digest': _digestB,
            },
            <String, Object?>{
              'name': 'nukhbaa.apk',
              'browser_download_url': '$_download/nukhbaa.apk',
              'digest': _digestA,
            },
          ],
        }),
        200,
      );
    }
    if (request.url.host == 'nukhbaa.app' && request.method == 'HEAD') {
      final String name = request.url.pathSegments.last;
      heads.add(name);
      final String? type = mirror[name];
      return type == null
          ? http.Response('', 404, headers: const {'content-type': 'text/html'})
          : http.Response(
              '',
              200,
              headers: <String, String>{'content-type': type},
            );
    }
    return http.Response('unexpected ${request.url}', 500);
  });
}

void main() {
  late DateTime clock;
  late _Hosts hosts;

  setUp(() {
    clock = DateTime.utc(2026, 10, 25, 9);
    hosts = _Hosts();
  });

  GetLatestBuild check({Uri? base}) {
    final http.Client client = hosts.client;
    return GetLatestBuild(
      MirroredBuildInfoRepository(
        GithubBuildInfoRepository(client),
        client,
        base: base ?? Uri.parse('https://nukhbaa.app/apk/'),
        now: () => clock,
      ),
    );
  }

  Future<LatestBuild> read(GetLatestBuild useCase) async =>
      ((await useCase()) as Ok<LatestBuild>).value;

  test('an APK the mirror serves is downloaded from the mirror, with the '
      'release\'s checksum', () async {
    hosts.mirror[_arm64] = 'application/vnd.android.package-archive';
    hosts.mirror[_v7a] = 'application/vnd.android.package-archive';

    final LatestBuild build = await read(check());

    expect(build.apkUrl, 'https://nukhbaa.app/apk/$_arm64');
    expect(build.sha256, 'a' * 64);
    expect(
      <String, String>{
        for (final BuildAsset asset in build.assets) asset.abi: asset.url,
      },
      <String, String>{
        'arm64-v8a': 'https://nukhbaa.app/apk/$_arm64',
        'armeabi-v7a': 'https://nukhbaa.app/apk/$_v7a',
      },
    );
    expect(
      build.assets.firstWhere((BuildAsset a) => a.abi == 'armeabi-v7a').sha256,
      'b' * 64,
    );
    expect(build.buildNumber, 780);
  });

  test('an APK not on the mirror yet keeps GitHub\'s address, and is asked '
      'again only after two minutes', () async {
    final GetLatestBuild useCase = check();

    final LatestBuild before = await read(useCase);
    expect(before.apkUrl, '$_download/$_arm64');
    expect(hosts.heads.where((String n) => n == _arm64), hasLength(1));

    hosts.mirror[_arm64] = 'application/vnd.android.package-archive';
    clock = clock.add(const Duration(minutes: 1));
    expect((await read(useCase)).apkUrl, '$_download/$_arm64');
    expect(hosts.heads.where((String n) => n == _arm64), hasLength(1));

    clock = clock.add(const Duration(minutes: 2));
    expect((await read(useCase)).apkUrl, 'https://nukhbaa.app/apk/$_arm64');
    expect(hosts.heads.where((String n) => n == _arm64), hasLength(2));
  });

  test('a file the mirror served is never asked again', () async {
    hosts.mirror[_arm64] = 'application/vnd.android.package-archive';
    hosts.mirror[_v7a] = 'application/vnd.android.package-archive';
    final GetLatestBuild useCase = check();

    await read(useCase);
    await read(useCase);
    clock = clock.add(const Duration(hours: 5));
    await read(useCase);

    expect(hosts.heads.where((String n) => n == _arm64), hasLength(1));
    expect(hosts.heads.where((String n) => n == _v7a), hasLength(1));
  });

  test('a page instead of the APK (the wrong type) is not the file', () async {
    hosts.mirror[_arm64] = 'text/html';

    expect((await read(check())).apkUrl, '$_download/$_arm64');
  });

  test('NUKHBA_APK_MIRROR: the mirror by default, off, or another https '
      'folder', () {
    expect(
      MirroredBuildInfoRepository.baseFrom(const <String, String>{}),
      Uri.parse('https://nukhbaa.app/apk/'),
    );
    expect(
      MirroredBuildInfoRepository.baseFrom(const <String, String>{
        'NUKHBA_APK_MIRROR': 'off',
      }),
      isNull,
    );
    expect(
      MirroredBuildInfoRepository.baseFrom(const <String, String>{
        'NUKHBA_APK_MIRROR': 'https://example.org/files',
      }),
      Uri.parse('https://example.org/files/'),
    );
    expect(
      MirroredBuildInfoRepository.baseFrom(const <String, String>{
        'NUKHBA_APK_MIRROR': 'http://example.org/files/',
      }),
      isNull,
    );
  });

  test(
    'without a mirror every address is GitHub\'s and nothing is asked',
    () async {
      final http.Client client = hosts.client;
      final GetLatestBuild useCase = GetLatestBuild(
        MirroredBuildInfoRepository(
          GithubBuildInfoRepository(client),
          client,
          base: null,
        ),
      );

      expect(
        ((await useCase()) as Ok<LatestBuild>).value.apkUrl,
        '$_download/$_arm64',
      );
      expect(hosts.heads, isEmpty);
    },
  );
}
