import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('POST /groups/{id}/invitations invites a player by id', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'invited': true}),
      token: 'jwt-abc',
    );

    final result = await GroupsApi(ctx.transport).invite('g-1', 'u-2');

    expect((result as Ok<bool>).value, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/groups/g-1/invitations');
    expect(jsonDecode(req.body), {'user_id': 'u-2'});
  });

  test('GET /groups/invitations reads my invitations', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'invitations': [
          {
            'id': 'i-1',
            'group_id': 'g-1',
            'group_name': 'Office',
            'inviter_name': 'Sara',
            'status': 'pending',
            'created_at': '2026-10-07T12:00:00.000Z',
          },
        ],
      }),
      token: 'jwt-abc',
    );

    final result = await GroupsApi(ctx.transport).myInvitations();

    final GroupInvitationsDto dto = (result as Ok<GroupInvitationsDto>).value;
    expect(dto.invitations.single.inviterName, 'Sara');
    expect(ctx.captured.single.url.path, '/groups/invitations');
  });

  test('accept and decline answer with the status', () async {
    final ctx = buildTransport(
      (request) async => okJson({
        'status': request.url.path.endsWith('/accept')
            ? 'accepted'
            : 'declined',
      }),
      token: 'jwt-abc',
    );
    final GroupsApi api = GroupsApi(ctx.transport);

    expect(
      await api.acceptInvitation('i-1'),
      const Result<String>.ok('accepted'),
    );
    expect(
      await api.declineInvitation('i-1'),
      const Result<String>.ok('declined'),
    );
    expect(ctx.captured.map((r) => r.url.path), <String>[
      '/groups/invitations/i-1/accept',
      '/groups/invitations/i-1/decline',
    ]);
    expect(ctx.captured.every((r) => r.method == 'POST'), isTrue);
  });
}
