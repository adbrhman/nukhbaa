import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /me/referral sends the install id as a query', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'code': 'ABCDEFGH',
        'month_points': 3,
        'season_points': 7,
        'invited_count': 5,
        'pending_count': 2,
        'month_cap': 20,
      }),
      token: 'jwt-abc',
    );

    final result = await AuthApi(
      ctx.transport,
    ).myReferral(installId: 'inst-12345678');

    final summary = (result as Ok<ReferralSummaryDto>).value;
    expect(summary.code, 'ABCDEFGH');
    expect(summary.monthPoints, 3);
    expect(summary.monthCap, 20);
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/me/referral');
    expect(req.url.queryParameters['install'], 'inst-12345678');
  });

  test('GET /me/referral without an install id sends no query', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'code': 'ABCDEFGH'}),
    );

    await AuthApi(ctx.transport).myReferral();

    expect(ctx.captured.single.url.queryParameters, isEmpty);
  });

  test('POST /me/referral/claim sends the code and the install id', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'status': 'claimed'}),
      token: 'jwt-abc',
    );

    final result = await AuthApi(
      ctx.transport,
    ).claimReferral(code: 'ABCDEFGH', installId: 'inst-12345678');

    expect((result as Ok<ReferralStatusDto>).value.status, 'claimed');
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/me/referral/claim');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['code'], 'ABCDEFGH');
    expect(body['install_id'], 'inst-12345678');
  });
}
