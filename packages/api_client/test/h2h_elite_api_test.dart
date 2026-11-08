import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.h2hEliteTables', () {
    test('200 -> Ok(H2hAdminGroupsDto), GET /me/h2h-league/elite', () async {
      const expected = H2hAdminGroupsDto(
        monthStart: '2026-11-01',
        drawn: true,
        isPilot: false,
        seatedCount: 12,
        rounds: [],
        groups: [
          H2hAdminGroupDto(
            leagueId: 'g-1',
            division: 1,
            groupIndex: 0,
            capacity: 20,
            promotionZone: 3,
            relegationZone: 0,
            standings: [
              H2hStandingDto(
                rank: 1,
                userId: 'u-me',
                displayName: 'سامي',
                played: 1,
                won: 1,
                drawn: 0,
                lost: 0,
                leaguePoints: 3,
                pointsFor: 9,
                exactCount: 0,
                form: ['win'],
                isMe: true,
              ),
            ],
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).h2hEliteTables();

      expect(
        (result as Ok<H2hAdminGroupsDto>).value.toJson(),
        expected.toJson(),
      );
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/h2h-league/elite');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(409, 'h2h.round_unknown', 'no'),
      );

      final result = await AuthApi(ctx.transport).h2hEliteTables();

      expect(
        (result as Err<H2hAdminGroupsDto>).error.code,
        'h2h.round_unknown',
      );
    });
  });
}
