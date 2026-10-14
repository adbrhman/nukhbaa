import 'package:api_client/api_client.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('DELETE /groups/{id}/members/me leaves the league', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'left': true}),
      token: 'jwt-abc',
    );

    final result = await GroupsApi(ctx.transport).leaveGroup('g-1');

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/groups/g-1/members/me');
  });

  test('DELETE /groups/{id}/members/{userId} removes a member', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'removed': true}),
      token: 'jwt-abc',
    );

    final result = await GroupsApi(ctx.transport).removeMember('g-1', 'u-2');

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/groups/g-1/members/u-2');
  });

  test('DELETE /groups/{id} deletes the league', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'deleted': true}),
      token: 'jwt-abc',
    );

    final result = await GroupsApi(ctx.transport).deleteGroup('g-1');

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/groups/g-1');
  });
}
