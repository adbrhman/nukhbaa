import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('CompetitionApi.myFixtureScores (GET /me/fixture-scores)', () {
    const scored = MyFixtureScoreDto(
      participantId: 'part-1',
      fixtureId: 'f-1',
      grade: 'exact_scoreline',
      points: 6,
      resultHomeGoals: 2,
      resultAwayGoals: 1,
    );
    const waiting = MyFixtureScoreDto(
      participantId: 'part-1',
      fixtureId: 'f-2',
      resultHomeGoals: 0,
      resultAwayGoals: 0,
    );

    test('200 -> Ok(List<MyFixtureScoreDto>), one GET', () async {
      final ctx = buildTransport(
        (_) async => okJson([scored.toJson(), waiting.toJson()]),
        token: 'jwt',
      );

      final result = await CompetitionApi(ctx.transport).myFixtureScores();

      expect((result as Ok<List<MyFixtureScoreDto>>).value, [scored, waiting]);
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/fixture-scores');
      expect(req.headers['authorization'], 'Bearer jwt');
    });

    test('nothing scored yet -> Ok(<empty>)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(ctx.transport).myFixtureScores();

      expect((result as Ok<List<MyFixtureScoreDto>>).value, isEmpty);
    });

    test('503 -> a transient error the app may try again', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'db.query_timeout', 'slow'),
      );

      final result = await CompetitionApi(ctx.transport).myFixtureScores();

      final error = (result as Err<List<MyFixtureScoreDto>>).error;
      expect(error.kind, ErrorKind.transient);
      expect(error.code, 'db.query_timeout');
    });
  });
}
