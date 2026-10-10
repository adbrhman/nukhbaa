/// `AdminApi.addH2hGroups` (2026-10-11): one POST with the count, the
/// groups opened read back; a refusal keeps its code.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('POST /admin/h2h/extra-groups with the count', () async {
    final ctx = buildTransport(
      (_) async => okJson(const <String, Object?>{
        'month_start': '2026-10-01',
        'groups': [
          {
            'league_id': '22222222-2222-4222-8222-222222222222',
            'division': 2,
            'group_index': 0,
            'seats': 20,
          },
        ],
        'seats': 20,
        'waiting': 52,
      }),
    );

    final result = await AdminApi(ctx.transport).addH2hGroups(groups: 1);

    final added = (result as Ok<H2hGroupsAddedDto>).value;
    expect(added.groups.single.division, 2);
    expect(added.waiting, 52);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/admin/h2h/extra-groups');
    expect(req.body, '{"groups":1}');
  });

  test('a refusal arrives with its code', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(409, 'h2h.groups_no_players', 'nobody'),
    );

    final result = await AdminApi(ctx.transport).addH2hGroups(groups: 2);

    expect(
      (result as Err<H2hGroupsAddedDto>).error.code,
      'h2h.groups_no_players',
    );
  });
}
