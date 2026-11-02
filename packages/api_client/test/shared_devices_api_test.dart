import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 200: the app names its install on every request, through the
/// real [ApiTransport] over [BuildHeaderClient], and the admin reads the
/// phones shared by several accounts.
void main() {
  const String phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

  ({AppApi api, List<http.Request> seen}) build(String? Function()? installId) {
    final List<http.Request> seen = <http.Request>[];
    final http.Client client = BuildHeaderClient(
      MockClient((http.Request request) async {
        seen.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'code': 'app.build_unknown',
            'message': 'unknown',
          }),
          503,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
      build: 775,
      installId: installId,
    );
    final ApiTransport transport = ApiTransport(
      baseUri: Uri.parse('https://api.test.example/'),
      httpClient: client,
      tokenProvider: () async => 'token',
      requestTimeout: null,
    );
    return (api: AppApi(transport), seen: seen);
  }

  test('every request carries the install id beside the build', () async {
    int reads = 0;
    final app = build(() {
      reads++;
      return phone;
    });

    await app.api.latestBuild();
    await app.api.latestBuild();

    expect(app.seen, hasLength(2));
    for (final http.Request request in app.seen) {
      expect(request.headers[appInstallHeader], phone);
      expect(request.headers[appBuildHeader], '775');
    }
    expect(reads, 2);
  });

  test('no id, or a store that fails, sends the request without it', () async {
    final none = build(() => null);
    final failing = build(() => throw StateError('keystore'));
    final absent = build(null);

    await none.api.latestBuild();
    await failing.api.latestBuild();
    await absent.api.latestBuild();

    for (final http.Request request in <http.Request>[
      ...none.seen,
      ...failing.seen,
      ...absent.seen,
    ]) {
      expect(request.headers.containsKey(appInstallHeader), isFalse);
      expect(request.headers[appBuildHeader], '775');
    }
  });

  test('sharedDevices reads every phone', () async {
    final dto = SharedDevicesDto(
      devices: [
        SharedDeviceDto(
          users: const [
            UserSummaryDto(
              id: '11111111-1111-4111-8111-111111111111',
              displayName: 'أحمد',
              status: 'active',
            ),
            UserSummaryDto(
              id: '22222222-2222-4222-8222-222222222222',
              displayName: 'خالد',
              status: 'suspended',
            ),
          ],
          lastSeen: DateTime.utc(2026, 11, 2, 9),
        ),
      ],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).sharedDevices();

    expect(result, Result<SharedDevicesDto>.ok(dto));
    expect(ctx.captured.single.url.path, '/admin/shared-devices');
    expect(ctx.captured.single.method, 'GET');
  });
}
