import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('searchPlayers asks for the trimmed name and reads the list', () async {
    final ctx = buildTransport(
      (_) async => okJson({
        'schema_version': 1,
        'players': [
          {'user_id': 'u-1', 'display_name': 'Badr'},
        ],
      }),
    );

    final result = await DuelsApi(ctx.transport).searchPlayers(' Bad ');

    final dto = (result as Ok<DuelPlayersDto>).value;
    expect(dto.players.single.displayName, 'Badr');
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/duels/players');
    expect(req.url.queryParameters['q'], 'Bad');
  });
}
