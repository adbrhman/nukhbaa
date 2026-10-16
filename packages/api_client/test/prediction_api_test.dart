import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
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

  group('PredictionApi.myFixturePredictions (GET /me/fixture-predictions)', () {
    const storedFixturePrediction = FixturePredictionDto(
      id: 'fp-1',
      participantId: 'part-1',
      fixtureId: 'f-c',
      submittedAt: '2026-08-02T10:00:00Z',
      homeGoals: 3,
      awayGoals: 3,
    );

    test('200 -> Ok(List<FixturePredictionDto>)', () async {
      final ctx = buildTransport(
        (_) async => okJson([storedFixturePrediction.toJson()]),
      );

      final result = await PredictionApi(ctx.transport).myFixturePredictions();

      expect(
        result,
        const Result<List<FixturePredictionDto>>.ok([storedFixturePrediction]),
      );
      expect(ctx.captured.single.url.path, '/me/fixture-predictions');
    });

    test('never predicted a fixture -> Ok(<empty>)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await PredictionApi(ctx.transport).myFixturePredictions();

      expect((result as Ok<List<FixturePredictionDto>>).value, isEmpty);
    });

    test('network failure -> Err(transient) network_unreachable', () async {
      final ctx = buildTransport((_) async => throw Exception('timeout'));

      final result = await PredictionApi(ctx.transport).myFixturePredictions();

      expect(
        (result as Err<List<FixturePredictionDto>>).error.code,
        apiErrorNetworkUnreachable,
      );
    });
  });
  group('PredictionApi.getFixturePredictionDistribution', () {
    test('200 -> typed distribution DTO at the exact path', () async {
      const dto = FixturePredictionDistributionDto(
        homeWinPercentage: 68,
        awayWinPercentage: 32,
      );
      final ctx = buildTransport((_) async => okJson(dto.toJson()));

      final result = await PredictionApi(
        ctx.transport,
      ).getFixturePredictionDistribution(seasonId: 's-1', fixtureId: 'f-1');

      expect(result, const Result<FixturePredictionDistributionDto>.ok(dto));
      expect(
        ctx.captured.single.url.path,
        '/seasons/s-1/fixtures/f-1/prediction-distribution',
      );
      expect(ctx.captured.single.method, 'GET');
    });
  });
}
