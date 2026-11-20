import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

// NK294_14
/// Script 294: the owners' page of admins, read and acted on.
void main() {
  test('ownerAdmins reads the page', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'schema_version': 1,
        'admins': [
          {
            'id': 'u-1',
            'display_name': 'المالك',
            'email': null,
            'active': true,
            'is_owner': true,
          },
        ],
        'changes': <Object?>[],
      }),
    );

    final result = await AdminApi(ctx.transport).ownerAdmins();

    expect((result as Ok<OwnerAdminsDto>).value.admins.single.isOwner, isTrue);
    expect(ctx.captured.single.url.path, '/owner/admins');
  });

  test('actOnAdmin posts the action and its reason', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'action': 'revoke',
        'sessions_ended': 2,
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).actOnAdmin('u-2', 'revoke', reason: 'سوء استخدام');

    expect(result, const Result<int>.ok(2));
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/owner/admins/u-2');
    expect(jsonDecode(sent.body), {
      'action': 'revoke',
      'reason': 'سوء استخدام',
    });
  });
}
