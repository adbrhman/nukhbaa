import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// A club the list lacks is added from the admin panel (script 91).
void main() {
  test('POST /admin/teams sends the name and the league and reads the '
      'club', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'name': 'نادي جديد',
        'short_name': null,
        'crest_url': null,
        'league_id': 'abababab-abab-4bab-8bab-abababababab',
      }),
    );

    final result = await AdminApi(ctx.transport).addTeam(
      name: 'نادي جديد',
      leagueId: 'abababab-abab-4bab-8bab-abababababab',
    );

    final TeamDto team = (result as Ok<TeamDto>).value;
    expect(team.id, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    expect(team.crestUrl, isNull);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/admin/teams');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['name'], 'نادي جديد');
    expect(body['league_id'], 'abababab-abab-4bab-8bab-abababababab');
  });

  test('a club already on file comes back as its code and message', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'football_data.team_exists',
        'النادي «بشكتاش» في القائمة من قبل، فاختره منها. لم يُضَف مرة ثانية.',
      ),
    );

    final result = await AdminApi(ctx.transport).addTeam(name: 'بشكتاش');

    final AppError error = (result as Err<TeamDto>).error;
    expect(error.code, 'football_data.team_exists');
    expect(error.message, contains('«بشكتاش»'));
    expect(
      (jsonDecode(ctx.captured.single.body) as Map<String, Object?>)
          .containsKey('league_id'),
      isTrue,
    );
  });
}
