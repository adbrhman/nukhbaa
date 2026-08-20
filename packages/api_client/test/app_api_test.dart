import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AppApi.latestBuild (GET /app/latest-build)', () {
    test('200 -> Ok(LatestBuildDto)', () async {
      const dto = LatestBuildDto(
        publishedAt: '2026-08-20T12:00:00.000Z',
        apkUrl: 'https://example.com/a.apk',
      );
      final ctx = buildTransport((_) async => okJson(dto.toJson()));

      final result = await AppApi(ctx.transport).latestBuild();

      expect(result, const Result<LatestBuildDto>.ok(dto));
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/app/latest-build');
    });

    test('503 -> Err(transient)', () async {
      final ctx = buildTransport(
        (_) async =>
            errorEnvelope(503, 'app.latest_build_unavailable', 'unreachable'),
      );

      final result = await AppApi(ctx.transport).latestBuild();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuildDto>).error.kind, ErrorKind.transient);
    });
  });
}
