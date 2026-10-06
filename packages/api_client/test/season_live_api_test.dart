import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /seasons/{id}/live reads the live standing', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'fixtures': [
          {
            'fixture_id': 'f-1',
            'home_goals': 1,
            'away_goals': 0,
            'minute': 63,
            'finished': false,
            'my_points': 3,
          },
        ],
        'duels': <Object?>[],
        'rank_now': 4,
        'rank_if_ended': 2,
        'points_now': 3,
        'points_if_ended': 6,
        'players': 9,
      }),
      token: 'jwt-abc',
    );

    final result = await LeaderboardsApi(ctx.transport).seasonLive('s-1');

    final LiveStandingDto standing = (result as Ok<LiveStandingDto>).value;
    expect(standing.fixture('f-1')!.myPoints, 3);
    expect((standing.rankNow, standing.rankIfEnded), (4, 2));
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/seasons/s-1/live');
  });
}
