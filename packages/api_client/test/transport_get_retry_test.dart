/// A GET that dies before reaching the server -- the pooled keep-alive
/// socket the server's proxy already closed while the app sat in the
/// background -- is tried once more on a fresh connection. A POST is never
/// repeated, and a GET that keeps failing still fails.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('a GET on a dead socket succeeds on the one retry', () async {
    int calls = 0;
    final ctx = buildTransport((_) async {
      calls++;
      if (calls == 1) {
        throw Exception('Connection closed before full header was received');
      }
      return okJson(const {
        'schema_version': 1,
        'window_days': 7,
        'overall': <String, Object?>{},
        'builds': <Object?>[],
      });
    }, token: 'jwt-abc');

    final result = await AdminApi(ctx.transport).frameStats();

    expect(result, isA<Ok<AdminFrameStatsDto>>());
    expect(calls, 2);
  });

  test('a GET that keeps failing still fails, after two tries', () async {
    int calls = 0;
    final ctx = buildTransport((_) async {
      calls++;
      throw Exception('network down');
    }, token: 'jwt-abc');

    final result = await AdminApi(ctx.transport).frameStats();

    expect(
      (result as Err<AdminFrameStatsDto>).error.code,
      apiErrorNetworkUnreachable,
    );
    expect(calls, 2);
  });

  test('a POST is never repeated', () async {
    int calls = 0;
    final ctx = buildTransport((_) async {
      calls++;
      throw Exception('Connection closed before full header was received');
    }, token: 'jwt-abc');

    final result = await AuthApi(
      ctx.transport,
    ).reportPushOpened(link: '/matches');

    expect(result, isA<Err<PushOpenedAckDto>>());
    expect(calls, 1);
  });
}
