import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const _challengeId = 'd3d3d3d3-d3d3-4d3d-8d3d-d3d3d3d3d3d3';

const Map<String, Object?> _challengeJson = {
  'schema_version': 1,
  'id': _challengeId,
  'code': 'ABCDEFGHJKMN',
  'season_id': 's',
  'fixture_id': 'f',
  'home_team': 'Home',
  'away_team': 'Away',
  'kickoff_at': '2026-10-05T18:00:00.000Z',
  'challenger_user_id': 'u',
  'challenger_name': 'Ali',
  'is_private': false,
  'capacity': 5,
  'accepted_count': 0,
  'state': 'open',
  'is_mine': true,
  'is_for_me': false,
};

void main() {
  test('createChallenge posts the fixture and reads the 201 body', () async {
    final ctx = buildTransport(
      (_) async => http.Response(
        jsonEncode(_challengeJson),
        201,
        headers: const {'content-type': 'application/json'},
      ),
    );

    final result = await DuelsApi(
      ctx.transport,
    ).createChallenge(seasonId: 's', fixtureId: 'f');

    final dto = (result as Ok<DuelChallengeDto>).value;
    expect(dto.code, 'ABCDEFGHJKMN');
    expect(dto.isMine, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/duels/challenges');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['season_id'], 's');
    expect(body['fixture_id'], 'f');
    expect(body.containsKey('target_user_id'), isFalse);
  });

  test('acceptChallenge posts the prediction to the challenge', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'id': 'd',
        'challenge_id': _challengeId,
        'fixture_id': 'f',
        'accepted_at': '2026-10-05T12:00:00.000Z',
      }),
    );

    final result = await DuelsApi(
      ctx.transport,
    ).acceptChallenge(_challengeId, homeGoals: 2, awayGoals: 1);

    expect((result as Ok<DuelDto>).value.challengeId, _challengeId);
    final req = ctx.captured.single;
    expect(req.url.path, '/duels/challenges/$_challengeId/accept');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['home_goals'], 2);
    expect(body['away_goals'], 1);
    expect(body['is_double'], isFalse);
  });

  test('cancel and decline answer the new state', () async {
    final ctx = buildTransport((request) async {
      final status = request.url.path.endsWith('/cancel')
          ? 'cancelled'
          : 'declined';
      return okJson({'status': status});
    });
    final api = DuelsApi(ctx.transport);

    final cancelled = await api.cancelChallenge(_challengeId);
    final declined = await api.declineChallenge(_challengeId);

    expect((cancelled as Ok<String>).value, 'cancelled');
    expect((declined as Ok<String>).value, 'declined');
    expect(ctx.captured.map((c) => c.method), everyElement('POST'));
  });

  test('challengeByCode normalises the typed code', () async {
    final ctx = buildTransport((_) async => okJson(_challengeJson));

    await DuelsApi(ctx.transport).challengeByCode(' abcdefghjkmn ');

    expect(ctx.captured.single.url.path, '/duels/codes/ABCDEFGHJKMN');
  });

  test('a refusal arrives as the server code', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'social.duel_capacity_full',
        'This duel challenge is full',
      ),
    );

    final result = await DuelsApi(
      ctx.transport,
    ).acceptChallenge(_challengeId, homeGoals: 1, awayGoals: 1);

    final error = (result as Err<DuelDto>).error;
    expect(error.code, 'social.duel_capacity_full');
    expect(error.kind, ErrorKind.invariant);
  });

  test('myDuels reads both lists', () async {
    final ctx = buildTransport(
      (_) async => okJson({
        'schema_version': 1,
        'challenges': [_challengeJson],
        'duels': <Object?>[],
      }),
    );

    final result = await DuelsApi(ctx.transport).myDuels();

    final dto = (result as Ok<MyDuelsDto>).value;
    expect(dto.challenges.single.id, _challengeId);
    expect(dto.duels, isEmpty);
    expect(ctx.captured.single.url.path, '/me/duels');
  });
}
