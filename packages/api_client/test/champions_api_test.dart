import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const Map<String, Object?> _champion = {
  'season_id': 's-9',
  'season_label': '09/2026',
  'user_id': 'u-1',
  'display_name': 'Ahmad',
  'points': 42,
  'exact_count': 6,
  'decided_count': 30,
  'referral_points': 0,
  'crowned_at': '2026-10-01T12:00:00.000Z',
  'celebrate_until': '2026-10-03T12:00:00.000Z',
  'photo_url': '/champions/s-9/photos/u-1?v=1',
};

void main() {
  test('GET /champions reads every champion', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'champions': [_champion],
      }),
    );

    final result = await LeaderboardsApi(ctx.transport).champions();

    final list = (result as Ok<MonthChampionsDto>).value;
    expect(list.champions.single.displayName, 'Ahmad');
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/champions');
  });

  test('the picture is fetched from the URL the server built', () async {
    final ctx = buildTransport(
      (_) async => http.Response.bytes(const [137, 80, 78, 71], 200),
    );

    final result = await LeaderboardsApi(
      ctx.transport,
    ).championPhotoBytes('/champions/s-9/photos/u-1?v=1');

    expect((result as Ok<Uint8List?>).value, [137, 80, 78, 71]);
    expect(ctx.captured.single.url.path, '/champions/s-9/photos/u-1');
    expect(ctx.captured.single.url.queryParameters['v'], '1');
  });

  test('GET /admin/champions/{id} reads the preview', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'season_id': 's-9',
        'season_label': '09/2026',
        'ended': true,
        'unscored_fixtures': 0,
        'crowned': <String>[],
        'candidates': [
          {
            'rank': 1,
            'user_id': 'u-1',
            'display_name': 'Ahmad',
            'points': 42,
            'exact_count': 6,
            'decided_count': 30,
            'referral_points': 0,
          },
        ],
      }),
    );

    final result = await AdminApi(ctx.transport).championCandidates('s-9');

    final preview = (result as Ok<ChampionCandidatesDto>).value;
    expect(preview.candidates.single.userId, 'u-1');
    expect(ctx.captured.single.url.path, '/admin/champions/s-9');
  });

  test('POST /admin/champions/{id} sends the chosen players', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'champions': [_champion],
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).crownChampions(seasonId: 's-9', userIds: const ['u-1'], force: true);

    expect((result as Ok<MonthChampionsDto>).value.champions, hasLength(1));
    expect(ctx.captured.single.method, 'POST');
    expect(ctx.captured.single.url.path, '/admin/champions/s-9');
    expect(jsonDecode(ctx.captured.single.body), {
      'user_ids': ['u-1'],
      'force': true,
    });
  });

  test('the picture goes up as bytes with its type', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'champions': [_champion],
      }),
    );

    final result = await AdminApi(ctx.transport).setChampionPhoto(
      seasonId: 's-9',
      userId: 'u-1',
      bytes: const [137, 80, 78, 71],
      contentType: 'image/png',
    );

    expect(result, isA<Ok<MonthChampionsDto>>());
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/admin/champions/s-9/photos/u-1');
    expect(sent.headers['content-type'], startsWith('image/png'));
    expect(sent.request.bodyBytes, [137, 80, 78, 71]);
  });

  test('a refusal carries its code', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(409, 'champion.not_first', 'not first'),
    );

    final result = await AdminApi(
      ctx.transport,
    ).crownChampions(seasonId: 's-9', userIds: const ['u-2']);

    expect((result as Err<MonthChampionsDto>).error.code, 'champion.not_first');
  });
}
