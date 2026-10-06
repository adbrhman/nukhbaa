import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const _season = 's-1';
const _fixture = 'f-1';
const _target = 'p-2';

void main() {
  test('GET the reactions of a fixture', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'reactions': [
          {
            'participant_id': _target,
            'counts': {'fire': 2},
            'mine': 'fire',
          },
        ],
      }),
      token: 'jwt-abc',
    );

    final result = await PredictionApi(
      ctx.transport,
    ).listPredictionReactions(seasonId: _season, fixtureId: _fixture);

    final dto = (result as Ok<PredictionReactionsDto>).value;
    expect(dto.of(_target)!.counts, {'fire': 2});
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/seasons/$_season/fixtures/$_fixture/reactions');
  });

  test('PUT a reaction on a prediction', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'reacted': true, 'first': true}),
      token: 'jwt-abc',
    );

    final result = await PredictionApi(ctx.transport).reactToPrediction(
      seasonId: _season,
      fixtureId: _fixture,
      participantId: _target,
      kind: 'clap',
    );

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'PUT');
    expect(
      req.url.path,
      '/seasons/$_season/fixtures/$_fixture/predictions/$_target/reaction',
    );
    expect((jsonDecode(req.body) as Map<String, Object?>)['emoji'], 'clap');
  });

  test('DELETE takes the reaction back', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'removed': true}),
      token: 'jwt-abc',
    );

    final result = await PredictionApi(ctx.transport).removePredictionReaction(
      seasonId: _season,
      fixtureId: _fixture,
      participantId: _target,
    );

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'DELETE');
    expect(
      req.url.path,
      '/seasons/$_season/fixtures/$_fixture/predictions/$_target/reaction',
    );
  });
}
