import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('TeamsApi.listTeams (GET /teams)', () {
    test('200 array -> Ok(List<TeamDto>) in server order', () async {
      const a = TeamDto(
        id: 't-1',
        name: 'Real Madrid',
        shortName: 'RMA',
        crestUrl: 'https://example.com/rma.svg',
      );
      const b = TeamDto(
        id: 't-2',
        name: 'Barcelona',
        shortName: null,
        crestUrl: null,
      );
      final ctx = buildTransport((_) async => okJson([a.toJson(), b.toJson()]));

      final result = await TeamsApi(ctx.transport).listTeams();

      expect(result, const Result<List<TeamDto>>.ok([a, b]));
      expect(ctx.captured.single.url.path, '/teams');
      expect(ctx.captured.single.method, 'GET');
    });

    test('empty catalog -> Ok(<empty>), not an error', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await TeamsApi(ctx.transport).listTeams();

      expect((result as Ok<List<TeamDto>>).value, isEmpty);
    });

    test('401 (unauthenticated) -> Err, no client-side oracle', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(401, 'auth.unauthenticated', 'sign in'),
      );

      final result = await TeamsApi(ctx.transport).listTeams();

      expect((result as Err<List<TeamDto>>).error.code, 'auth.unauthenticated');
    });
  });
}
