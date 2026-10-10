/// `PredictionApi.predictionsBoard` (2026-10-11): one GET with the started
/// fixtures of the day, the answer read into columns.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /seasons/{id}/predictions-board?fixtures=a,b', () async {
    final ctx = buildTransport(
      (_) async => okJson(const <String, Object?>{
        'schema_version': 1,
        'season_id': 's-1',
        'columns': [
          {
            'fixture_id': 'f-1',
            'error_code': null,
            'retryable': false,
            'predictions': [
              {
                'id': 'p-1',
                'participant_id': 'u-1',
                'fixture_id': 'f-1',
                'submitted_at': '2026-10-10T12:00:00.000Z',
                'home_goals': 1,
                'away_goals': 0,
              },
            ],
            'scores': {'fixture_id': 'f-1', 'scores': <Object?>[]},
            'reactions': {'reactions': <Object?>[]},
          },
          {
            'fixture_id': 'f-2',
            'error_code': 'db.query_timeout',
            'retryable': true,
          },
        ],
      }),
    );

    final result = await PredictionApi(
      ctx.transport,
    ).predictionsBoard(seasonId: 's-1', fixtureIds: const ['f-1', 'f-2']);

    final board = (result as Ok<PredictionsBoardDto>).value;
    expect(board.of('f-1')!.predictions.single.homeGoals, 1);
    expect(board.of('f-1')!.scores!.scores, isEmpty);
    expect(board.of('f-2')!.retryable, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/seasons/s-1/predictions-board');
    expect(req.url.queryParameters, {'fixtures': 'f-1,f-2'});
  });

  test('a refusal of the whole board arrives with its code', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(400, 'board.fixtures_invalid', 'bad'),
    );

    final result = await PredictionApi(
      ctx.transport,
    ).predictionsBoard(seasonId: 's-1', fixtureIds: const <String>[]);

    expect(
      (result as Err<PredictionsBoardDto>).error.code,
      'board.fixtures_invalid',
    );
  });
}
