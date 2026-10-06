import 'package:api_client/api_client.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('POST /notifications/read_all answers how many were marked', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'marked': 3}),
      token: 'jwt-abc',
    );

    final result = await NotificationsApi(ctx.transport).markAllRead();

    expect((result as Ok<int>).value, 3);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/notifications/read_all');
    expect(req.headers['authorization'], 'Bearer jwt-abc');
  });
}
