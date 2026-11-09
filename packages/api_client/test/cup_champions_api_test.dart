import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const Map<String, Object?> _champion = {
  'month_start': '2026-11-01',
  'place': 1,
  'how': 'final',
  'user_id': 'u-1',
  'display_name': 'Ahmad',
  'photo_url': '/cup-champions/2026-11-01/1/photo?v=1',
};

void main() {
  test('GET /cup-champions reads every champion of the cup', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'champions': [_champion],
      }),
    );

    final result = await LeaderboardsApi(ctx.transport).cupChampions();

    final list = (result as Ok<CupChampionsDto>).value;
    expect(list.champions.single.displayName, 'Ahmad');
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/cup-champions');
  });

  test('the picture is fetched from the URL the server built', () async {
    final ctx = buildTransport(
      (_) async => http.Response.bytes(const [137, 80, 78, 71], 200),
    );

    final result = await LeaderboardsApi(
      ctx.transport,
    ).championPhotoBytes('/cup-champions/2026-11-01/1/photo?v=1');

    expect((result as Ok<Uint8List?>).value, [137, 80, 78, 71]);
    expect(ctx.captured.single.url.path, '/cup-champions/2026-11-01/1/photo');
  });

  test('POST /admin/cup-champions/{month}/{place}/photo sends bytes', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'champions': [_champion],
      }),
    );

    final result = await AdminApi(ctx.transport).setCupChampionPhoto(
      monthStart: '2026-11-01',
      place: 1,
      bytes: const [137, 80, 78, 71],
      contentType: 'image/png',
    );

    expect((result as Ok<CupChampionsDto>).value.champions, hasLength(1));
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/admin/cup-champions/2026-11-01/1/photo');
    expect(sent.headers['content-type'], startsWith('image/png'));
    expect(sent.request.bodyBytes, [137, 80, 78, 71]);
  });

  test(
    'DELETE /admin/cup-champions/{month}/{place}/photo removes it',
    () async {
      final ctx = buildTransport(
        (_) async =>
            okJson(const {'schema_version': 1, 'champions': <Object?>[]}),
      );

      final result = await AdminApi(
        ctx.transport,
      ).removeCupChampionPhoto(monthStart: '2026-11-01', place: 3);

      expect((result as Ok<CupChampionsDto>).value.champions, isEmpty);
      expect(ctx.captured.single.method, 'DELETE');
      expect(
        ctx.captured.single.url.path,
        '/admin/cup-champions/2026-11-01/3/photo',
      );
    },
  );
}
