import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// A league the list lacks is added from the add-match form (script 139).
void main() {
  test('POST /admin/leagues sends the name and reads the league', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'name': 'كأس السوبر الأفريقي',
        'short_name': null,
        'logo_url': null,
        'is_continental': true,
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).addLeague(name: 'كأس السوبر الأفريقي');

    final LeagueDto league = (result as Ok<LeagueDto>).value;
    expect(league.id, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    expect(league.isContinental, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/admin/leagues');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body, <String, Object?>{'name': 'كأس السوبر الأفريقي'});
  });

  test('a league already on file comes back as its code and '
      'message', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'football_data.league_exists',
        'الدوري «ديربيات كبرى» في القائمة من قبل، فاختره منها. '
            'لم يُضَف مرة ثانية.',
      ),
    );

    final result = await AdminApi(
      ctx.transport,
    ).addLeague(name: 'ديربيات كبري');

    final AppError error = (result as Err<LeagueDto>).error;
    expect(error.code, 'football_data.league_exists');
    expect(error.message, contains('«ديربيات كبرى»'));
  });
}
