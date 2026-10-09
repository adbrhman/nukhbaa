import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.myH2hLeague', () {
    test('200 -> Ok(MyH2hLeagueDto), GET /me/h2h-league', () async {
      const expected = MyH2hLeagueDto(
        state: 'open',
        monthStart: '2026-11-01',
        startsOn: '2026-11-01',
        isPilot: false,
        division: 3,
        groupIndex: 0,
        myRank: 2,
        promotionZone: 3,
        relegationZone: 3,
        standings: [
          H2hStandingDto(
            rank: 2,
            userId: 'u-1',
            displayName: 'Nora',
            played: 1,
            won: 1,
            drawn: 0,
            lost: 0,
            leaguePoints: 3,
            pointsFor: 9,
            exactCount: 1,
            form: ['win'],
            isMe: true,
          ),
        ],
        rounds: [
          H2hRoundViewDto(
            round: 1,
            day: '2026-11-01',
            status: 'settled',
            fixtureCount: 7,
            opponentUserId: 'u-2',
            opponentName: 'Sami',
            myPoints: 9,
            opponentPoints: 4,
            result: 'win',
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).myH2hLeague();

      expect((result as Ok<MyH2hLeagueDto>).value.toJson(), expected.toJson());
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/h2h-league');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('a month that has not started parses with no table', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'schema_version': 1,
          'state': 'not_started',
          'month_start': '2026-10-01',
          'starts_on': '2026-11-01',
          'is_pilot': false,
          'division': null,
          'group_index': null,
          'my_rank': 0,
          'promotion_zone': 0,
          'relegation_zone': 0,
          'standings': <Object?>[],
          'rounds': <Object?>[],
        }),
      );

      final result = await AuthApi(ctx.transport).myH2hLeague();

      final value = (result as Ok<MyH2hLeagueDto>).value;
      expect(value.state, 'not_started');
      expect(value.startsOn, '2026-11-01');
      expect(value.division, isNull);
      expect(value.standings, isEmpty);
    });

    test('a server error arrives as Err with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'db.down', 'down'),
      );

      final result = await AuthApi(ctx.transport).myH2hLeague();

      expect((result as Err<MyH2hLeagueDto>).error.code, 'db.down');
    });
  });
}
