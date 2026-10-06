import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('POST /me/screen-views sends the counts', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'recorded': 2}),
      token: 'jwt-abc',
    );

    final result = await AuthApi(
      ctx.transport,
    ).reportScreenViews(const {'duels': 2, 'home': 1});

    expect((result as Ok<ScreenViewsAckDto>).value.recorded, 2);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/me/screen-views');
    expect(req.headers['authorization'], 'Bearer jwt-abc');
    expect((jsonDecode(req.body) as Map<String, Object?>)['opens'], {
      'duels': 2,
      'home': 1,
    });
  });
}
