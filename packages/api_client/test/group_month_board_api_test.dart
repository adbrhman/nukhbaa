import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test(
    'GET /groups/{id}/seasons/{seasonId}/month-board reads the board',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'schema_version': 1,
          'season_id': 's-1',
          'entries': [
            {
              'rank': 1,
              'participant_id': 'p-1',
              'display_name': 'Friend',
              'total_points': 9,
              'fixtures_scored': 4,
            },
          ],
        }),
        token: 'jwt-abc',
      );

      final result = await GroupsApi(ctx.transport).monthBoard('g-1', 's-1');

      final FixtureLeaderboardDto board =
          (result as Ok<FixtureLeaderboardDto>).value;
      expect(board.entries.single.displayName, 'Friend');
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/groups/g-1/seasons/s-1/month-board');
    },
  );
}
