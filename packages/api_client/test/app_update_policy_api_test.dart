import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// The oldest supported build (batch 147): the admin's switch, and the
/// minimum the update check reads.
void main() {
  test(
    'PUT /admin/app/min-build sends to_latest and reads the policy',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'schema_version': 1,
          'latest_build': 214,
          'min_supported_build': 214,
        }),
      );

      final result = await AdminApi(
        ctx.transport,
      ).setMinSupportedBuild(toLatest: true);

      final AppUpdatePolicyDto policy =
          (result as Ok<AppUpdatePolicyDto>).value;
      expect(policy.minSupportedBuild, 214);
      expect(policy.latestBuild, 214);
      final req = ctx.captured.single;
      expect(req.method, 'PUT');
      expect(req.url.path, '/admin/app/min-build');
      expect((jsonDecode(req.body) as Map<String, Object?>)['to_latest'], true);
    },
  );

  test(
    'GET /app/latest-build reads the build number and the minimum',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'schema_version': 2,
          'published_at': '2026-10-15T00:00:00Z',
          'apk_url': 'https://example.com/a.apk',
          'build_number': 214,
          'min_supported_build': 210,
        }),
      );

      final result = await AppApi(ctx.transport).latestBuild();

      final LatestBuildDto build = (result as Ok<LatestBuildDto>).value;
      expect(build.buildNumber, 214);
      expect(build.minSupportedBuild, 210);
    },
  );
}
