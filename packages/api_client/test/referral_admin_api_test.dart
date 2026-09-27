import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /admin/referral-overview reads the overview', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'enabled': true,
        'state_counts': {'paid': 2},
        'referrers': <Object?>[],
        'invitations': <Object?>[],
      }),
    );

    final result = await AdminApi(ctx.transport).referralOverview();

    final overview = (result as Ok<AdminReferralOverviewDto>).value;
    expect(overview.enabled, isTrue);
    expect(overview.stateCounts, {'paid': 2});
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/admin/referral-overview');
  });

  test('PUT /admin/referral-switch sends the switch', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'enabled': false}),
    );

    final result = await AdminApi(
      ctx.transport,
    ).setReferralsEnabled(enabled: false);

    expect((result as Ok<ReferralSwitchDto>).value.enabled, isFalse);
    final req = ctx.captured.single;
    expect(req.method, 'PUT');
    expect(req.url.path, '/admin/referral-switch');
    expect((jsonDecode(req.body) as Map<String, Object?>)['enabled'], false);
  });

  test(
    'POST /admin/referrals/{id} sends the decision and the reason',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {'schema_version': 1, 'status': 'revoked'}),
      );

      final result = await AdminApi(ctx.transport).reviewReferral(
        inviteeId: 'i-1',
        decision: 'revoke',
        reason: 'fake account',
      );

      expect((result as Ok<ReferralStatusDto>).value.status, 'revoked');
      final req = ctx.captured.single;
      expect(req.url.path, '/admin/referrals/i-1');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      expect(body['decision'], 'revoke');
      expect(body['reason'], 'fake account');
    },
  );
}
