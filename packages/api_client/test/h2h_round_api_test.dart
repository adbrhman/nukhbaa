import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.myH2hRound', () {
    test('200 -> Ok(MyH2hRoundDto), GET /me/h2h-league/rounds/{n}', () async {
      const expected = MyH2hRoundDto(
        round: 3,
        day: '2026-11-10',
        status: 'live',
        fixtureCount: 2,
        firstKickoff: '2026-11-10T12:00:00.000Z',
        opponentUserId: 'u-2',
        opponentName: 'Sami',
        myPoints: 6,
        opponentPoints: 0,
        result: 'win',
        mine: H2hSideTotalsDto(predicted: 2, exact: 1, doubles: 1),
        theirs: H2hSideTotalsDto(predicted: 1, exact: 0, doubles: 0),
        fixtures: [
          H2hRoundFixtureDto(
            fixtureId: 'f-1',
            homeTeam: 'Al Hilal',
            awayTeam: 'Al Nassr',
            kickoffAt: '2026-11-10T12:00:00.000Z',
            state: 'finished',
            homeGoals: 2,
            awayGoals: 1,
            mine: H2hPickDto(
              homeGoals: 2,
              awayGoals: 1,
              isDouble: true,
              points: 6,
              exact: true,
            ),
            theirs: H2hPickDto(homeGoals: 0, awayGoals: 1, isDouble: false),
            theirsHidden: false,
          ),
          H2hRoundFixtureDto(
            fixtureId: 'f-2',
            homeTeam: 'Al Ittihad',
            awayTeam: 'Al Ahli',
            kickoffAt: '2026-11-10T15:00:00.000Z',
            state: 'not_started',
            mine: H2hPickDto(homeGoals: 1, awayGoals: 0, isDouble: false),
            theirsHidden: true,
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).myH2hRound(3);

      final value = (result as Ok<MyH2hRoundDto>).value;
      expect(value.toJson(), expected.toJson());
      expect(value.fixtures[1].theirs, isNull);
      expect(value.fixtures[1].theirsHidden, isTrue);
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/h2h-league/rounds/3');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(409, 'h2h.not_seated', 'no seat'),
      );

      final result = await AuthApi(ctx.transport).myH2hRound(1);

      expect((result as Err<MyH2hRoundDto>).error.code, 'h2h.not_seated');
    });
  });
}
