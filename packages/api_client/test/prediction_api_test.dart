import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  const storedPrediction = PredictionDto(
    id: 'p-1',
    participantId: 'part-1',
    roundId: 'r-1',
    submittedAt: '2026-08-01T10:00:00Z',
    fixtureScores: [
      FixtureScoreDto(fixtureId: 'f-a', homeGoals: 2, awayGoals: 1),
    ],
  );

  group('PredictionApi.submitPrediction (POST /rounds/{id}/predictions)', () {
    test(
      '200 -> Ok; posts a SubmitPredictionCommand body with ONLY scores',
      () async {
        final ctx = buildTransport(
          (_) async => okJson(storedPrediction.toJson()),
          token: 'jwt',
        );

        final result = await PredictionApi(ctx.transport).submitPrediction(
          roundId: 'r-1',
          fixtureScores: const [
            FixtureScoreDto(fixtureId: 'f-a', homeGoals: 2, awayGoals: 1),
          ],
        );

        expect(result, const Result<PredictionDto>.ok(storedPrediction));

        final req = ctx.captured.single;
        expect(req.method, 'POST');
        expect(req.url.path, '/rounds/r-1/predictions');
        expect(req.headers['content-type'], 'application/json');
        expect(req.headers['authorization'], 'Bearer jwt');

        final sent = jsonDecode(req.body) as Map<String, Object?>;
        // The body carries only fixture scores + schema version — never a
        // participant id and never any points/score (Security ADR §2 / Axiom 2).
        expect(sent.keys.toSet(), {'schema_version', 'fixture_scores'});
        final scores = sent['fixture_scores']! as List<Object?>;
        expect(scores.single, {
          'fixture_id': 'f-a',
          'home_goals': 2,
          'away_goals': 1,
          'is_double': false,
        });
      },
    );

    test('400 incomplete forecast -> Err(validation)', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(
          400,
          'prediction.incomplete_forecast',
          'Predict every fixture.',
        ),
      );

      final result = await PredictionApi(
        ctx.transport,
      ).submitPrediction(roundId: 'r-1', fixtureScores: const []);

      final err = (result as Err<PredictionDto>).error;
      expect(err.kind, ErrorKind.validation);
      expect(err.code, 'prediction.incomplete_forecast');
    });

    test('409 round locked -> Err(invariant)', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(409, 'prediction.round_locked', 'Locked.'),
      );

      final result = await PredictionApi(ctx.transport).submitPrediction(
        roundId: 'r-1',
        fixtureScores: const [
          FixtureScoreDto(fixtureId: 'f-a', homeGoals: 0, awayGoals: 0),
        ],
      );

      expect((result as Err<PredictionDto>).error.kind, ErrorKind.invariant);
    });

    test('network failure -> Err(transient) retryable', () async {
      final ctx = buildTransport((_) async => throw Exception('timeout'));

      final result = await PredictionApi(ctx.transport).submitPrediction(
        roundId: 'r-1',
        fixtureScores: const [
          FixtureScoreDto(fixtureId: 'f-a', homeGoals: 1, awayGoals: 1),
        ],
      );

      expect(
        (result as Err<PredictionDto>).error.code,
        apiErrorNetworkUnreachable,
      );
    });
  });

  group('PredictionApi.submitFixturePrediction '
      '(POST /seasons/{id}/fixtures/{fixtureId}/prediction)', () {
    const storedFixturePrediction = FixturePredictionDto(
      id: 'fp-1',
      participantId: 'part-1',
      fixtureId: 'f-a',
      submittedAt: '2026-08-01T10:00:00Z',
      homeGoals: 2,
      awayGoals: 1,
    );

    test('200 -> Ok; posts a FixturePredictionCommand body, is_double '
        'default false', () async {
      final ctx = buildTransport(
        (_) async => okJson(storedFixturePrediction.toJson()),
        token: 'jwt',
      );

      final result = await PredictionApi(ctx.transport).submitFixturePrediction(
        seasonId: 's-1',
        fixtureId: 'f-a',
        homeGoals: 2,
        awayGoals: 1,
      );

      expect(
        result,
        const Result<FixturePredictionDto>.ok(storedFixturePrediction),
      );

      final req = ctx.captured.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/seasons/s-1/fixtures/f-a/prediction');
      expect(req.headers['authorization'], 'Bearer jwt');

      final sent = jsonDecode(req.body) as Map<String, Object?>;
      expect(sent, {
        'schema_version': 1,
        'home_goals': 2,
        'away_goals': 1,
        'is_double': false,
      });
    });

    test('is_double: true is sent verbatim when passed', () async {
      final ctx = buildTransport(
        (_) async => okJson(storedFixturePrediction.toJson()),
      );

      await PredictionApi(ctx.transport).submitFixturePrediction(
        seasonId: 's-1',
        fixtureId: 'f-a',
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );

      final sent = jsonDecode(ctx.captured.single.body) as Map<String, Object?>;
      expect(sent['is_double'], isTrue);
    });

    test('400 malformed body -> Err(validation)', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(
          400,
          'request.field_missing',
          'Field "home_goals" is required.',
        ),
      );

      final result = await PredictionApi(ctx.transport).submitFixturePrediction(
        seasonId: 's-1',
        fixtureId: 'f-a',
        homeGoals: 0,
        awayGoals: 0,
      );

      expect(
        (result as Err<FixturePredictionDto>).error.kind,
        ErrorKind.validation,
      );
    });

    test('409 daily-double cap -> Err(invariant)', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(
          409,
          'prediction.daily_double_limit',
          'Only one double per day.',
        ),
      );

      final result = await PredictionApi(ctx.transport).submitFixturePrediction(
        seasonId: 's-1',
        fixtureId: 'f-a',
        homeGoals: 1,
        awayGoals: 0,
        isDouble: true,
      );

      final err = (result as Err<FixturePredictionDto>).error;
      expect(err.kind, ErrorKind.invariant);
      expect(err.code, 'prediction.daily_double_limit');
    });

    test('network failure -> Err(transient) network_unreachable', () async {
      final ctx = buildTransport((_) async => throw Exception('timeout'));

      final result = await PredictionApi(ctx.transport).submitFixturePrediction(
        seasonId: 's-1',
        fixtureId: 'f-a',
        homeGoals: 1,
        awayGoals: 1,
      );

      expect(
        (result as Err<FixturePredictionDto>).error.code,
        apiErrorNetworkUnreachable,
      );
    });
  });

  group('PredictionApi.getMyPrediction (GET /rounds/{id}/predictions)', () {
    test('200 -> Ok(PredictionDto)', () async {
      final ctx = buildTransport(
        (_) async => okJson(storedPrediction.toJson()),
      );

      final result = await PredictionApi(ctx.transport).getMyPrediction('r-1');

      expect(result, const Result<PredictionDto>.ok(storedPrediction));
      expect(ctx.captured.single.method, 'GET');
      expect(ctx.captured.single.url.path, '/rounds/r-1/predictions');
    });

    test('404 prediction.not_found -> Err(invariant) with that code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(404, 'prediction.not_found', 'Nothing yet.'),
      );

      final result = await PredictionApi(ctx.transport).getMyPrediction('r-1');

      final err = (result as Err<PredictionDto>).error;
      expect(err.kind, ErrorKind.invariant);
      expect(err.code, 'prediction.not_found');
    });
  });

  group('PredictionApi.listRoundPredictions (GET .../predictions/all)', () {
    test('200 -> Ok(List<PredictionDto>) at the /all path', () async {
      final ctx = buildTransport(
        (_) async => okJson([storedPrediction.toJson()]),
      );

      final result = await PredictionApi(
        ctx.transport,
      ).listRoundPredictions('r-1');

      expect(result, const Result<List<PredictionDto>>.ok([storedPrediction]));
      expect(ctx.captured.single.url.path, '/rounds/r-1/predictions/all');
    });

    test('locked round, nobody predicted -> Ok(<empty>)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await PredictionApi(
        ctx.transport,
      ).listRoundPredictions('r-1');

      expect((result as Ok<List<PredictionDto>>).value, isEmpty);
    });

    test('401 round_not_locked -> Err(authorization)', () async {
      final ctx = buildTransport(
        (_) async =>
            errorEnvelope(401, 'prediction.round_not_locked', 'Too early.'),
      );

      final result = await PredictionApi(
        ctx.transport,
      ).listRoundPredictions('r-1');

      final err = (result as Err<List<PredictionDto>>).error;
      expect(err.kind, ErrorKind.authorization);
      expect(err.code, 'prediction.round_not_locked');
    });
  });
}
