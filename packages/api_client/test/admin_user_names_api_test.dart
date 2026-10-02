import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  const user = UserSummaryDto(
    id: '11111111-1111-4111-8111-111111111111',
    email: 'a@t.io',
    displayName: 'أحمد سالم',
    status: 'active',
  );

  test('renameUser posts the name and the reason to the account', () async {
    final ctx = buildTransport((request) async => okJson(user.toJson()));

    final result = await AdminApi(
      ctx.transport,
    ).renameUser(user.id, displayName: 'أحمد سالم', reason: 'اسم مكرر');

    expect(result, const Result<UserSummaryDto>.ok(user));
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/admin/users/${user.id}/display-name');
    expect(jsonDecode(sent.body), {
      'schema_version': 1,
      'display_name': 'أحمد سالم',
      'reason': 'اسم مكرر',
    });
  });

  test('a taken name comes back as its validation error', () async {
    final ctx = buildTransport(
      (request) async => errorEnvelope(
        400,
        'identity.display_name_taken',
        'هذا الاسم مستخدم، اختر اسمًا آخر',
      ),
    );

    final result = await AdminApi(
      ctx.transport,
    ).renameUser(user.id, displayName: 'أحمد', reason: 'اسم مكرر');

    final error = (result as Err<UserSummaryDto>).error;
    expect(error.code, 'identity.display_name_taken');
    expect(error.kind, ErrorKind.validation);
  });

  test('duplicateNames reads every group', () async {
    const dto = DuplicateNamesDto(
      groups: [
        [user, user],
      ],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).duplicateNames();

    expect(result, const Result<DuplicateNamesDto>.ok(dto));
    expect(ctx.captured.single.url.path, '/admin/duplicate-names');
    expect(ctx.captured.single.method, 'GET');
  });
}
