import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /seasons/{id}/duel-wins reads the wins', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'wins': {'p-1': 3},
      }),
      token: 'jwt-abc',
    );

    final result = await LeaderboardsApi(ctx.transport).seasonDuelWins('s-1');

    expect((result as Ok<SeasonDuelWinsDto>).value.of('p-1'), 3);
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/seasons/s-1/duel-wins');
  });
}
