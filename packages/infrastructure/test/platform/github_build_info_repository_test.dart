import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

String _releaseBody({
  String publishedAt = '2026-08-20T12:00:00Z',
  bool includeApk = true,
}) => jsonEncode({
  'tag_name': 'latest',
  'published_at': publishedAt,
  'assets': [
    if (includeApk)
      {
        'name': 'nukhbaa.apk',
        'browser_download_url': 'https://example.com/nukhbaa.apk',
      },
    {
      'name': 'source.zip',
      'browser_download_url': 'https://example.com/source.zip',
    },
  ],
});

void main() {
  group('GithubBuildInfoRepository.fetchLatest', () {
    test(
      'maps a 200 response to LatestBuild (published_at + apk url)',
      () async {
        final repo = GithubBuildInfoRepository(
          MockClient((_) async => http.Response(_releaseBody(), 200)),
        );

        final result = await repo.fetchLatest();

        expect(result.isOk, isTrue);
        final build = (result as Ok<LatestBuild>).value;
        expect(build.publishedAt, DateTime.parse('2026-08-20T12:00:00Z'));
        expect(build.apkUrl, 'https://example.com/nukhbaa.apk');
      },
    );

    test(
      'caches a successful read within the TTL (one network call)',
      () async {
        var calls = 0;
        final repo = GithubBuildInfoRepository(
          MockClient((_) async {
            calls++;
            return http.Response(_releaseBody(), 200);
          }),
        );

        await repo.fetchLatest();
        await repo.fetchLatest();

        expect(calls, 1);
      },
    );

    test('returns a transient error on a non-200 response', () async {
      final repo = GithubBuildInfoRepository(
        MockClient((_) async => http.Response('not found', 404)),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });

    test('returns a transient error when no .apk asset is published', () async {
      final repo = GithubBuildInfoRepository(
        MockClient(
          (_) async => http.Response(_releaseBody(includeApk: false), 200),
        ),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });

    test('returns a transient error on a network failure', () async {
      final repo = GithubBuildInfoRepository(
        MockClient((_) async => throw Exception('boom')),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });
  });
}
