import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// A player's points in one month, for the admin (batch 146b).
void main() {
  test('GET /admin/users/{id}/points names the month', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'played': true,
        'month_points': 3,
        'streak_bonus': 0,
        'entries': [
          {
            'id': 'e1',
            'fixture_id': 'f1',
            'home_team': 'Arsenal',
            'away_team': 'Chelsea',
            'kind': 'fixture_score',
            'amount': 3,
            'occurred_at': '2026-10-10T21:00:00.000Z',
          },
        ],
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).playerPoints('u-1', seasonId: 's-10');

    final PlayerMonthPointsDto month =
        (result as Ok<PlayerMonthPointsDto>).value;
    expect(month.monthPoints, 3);
    expect(month.entries.single.homeTeam, 'Arsenal');
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/admin/users/u-1/points');
    expect(req.url.queryParameters['season'], 's-10');
  });
}
