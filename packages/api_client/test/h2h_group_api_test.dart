import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.myH2hGroupRound', () {
    test(
      '200 -> Ok(H2hGroupRoundDto), GET /me/h2h-league/rounds/{n}/matches',
      () async {
        const expected = H2hGroupRoundDto(
          round: 2,
          day: '2026-10-11',
          status: 'settled',
          matches: [
            H2hGroupMatchDto(
              homeUserId: 'u-me',
              homeName: 'سامي',
              homeIsMe: true,
              homePoints: 9,
              awayUserId: 'u-2',
              awayName: 'نورة',
              awayPoints: 4,
              winner: 'home',
            ),
          ],
        );
        final ctx = buildTransport(
          (_) async => okJson(expected.toJson()),
          token: 'jwt-abc',
        );

        final result = await AuthApi(ctx.transport).myH2hGroupRound(2);

        expect(
          (result as Ok<H2hGroupRoundDto>).value.toJson(),
          expected.toJson(),
        );
        final req = ctx.captured.single;
        expect(req.method, 'GET');
        expect(req.url.path, '/me/h2h-league/rounds/2/matches');
        expect(req.headers['authorization'], 'Bearer jwt-abc');
      },
    );

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(409, 'h2h.round_unknown', 'no round'),
      );

      final result = await AuthApi(ctx.transport).myH2hGroupRound(7);

      expect((result as Err<H2hGroupRoundDto>).error.code, 'h2h.round_unknown');
    });
  });
}
