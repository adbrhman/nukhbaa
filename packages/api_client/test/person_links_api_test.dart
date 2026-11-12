import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 263: the owner admin lists, sets and unlinks one person's
/// accounts.
void main() {
  const String main = '11111111-1111-4111-8111-111111111111';
  const String second = '22222222-2222-4222-8222-222222222222';
  const String other = '33333333-3333-4333-8333-333333333333';

  test('personLinks reads the people', () async {
    const dto = PersonLinksDto(
      people: <LinkedPersonDto>[
        LinkedPersonDto(
          mainId: main,
          accounts: <LinkedAccountDto>[
            LinkedAccountDto(
              user: UserSummaryDto(
                id: main,
                status: 'active',
                displayName: 'عبدالرحمن المغربي',
              ),
              counted: true,
              hidden: false,
            ),
          ],
        ),
      ],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).personLinks();

    expect(result, const Result<PersonLinksDto>.ok(dto));
    expect(ctx.captured.single.url.path, '/admin/person-links');
  });

  test('setPerson puts the second and the others', () async {
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{'set': true}),
    );

    final result = await AdminApi(
      ctx.transport,
    ).setPerson(main, secondId: second, otherIds: <String>[other]);

    expect(result, const Result<bool>.ok(true));
    final sent = ctx.captured.single;
    expect(sent.method, 'PUT');
    expect(sent.url.path, '/admin/person-links/$main');
    expect(jsonDecode(sent.body), <String, Object?>{
      'second_id': second,
      'other_ids': <Object?>[other],
    });
  });

  test('without a second account none is sent', () async {
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{'set': true}),
    );

    await AdminApi(
      ctx.transport,
    ).setPerson(main, otherIds: <String>[second, other]);

    expect(jsonDecode(ctx.captured.single.body), <String, Object?>{
      'other_ids': <Object?>[second, other],
    });
  });

  test('unlinkPerson deletes and reads the count', () async {
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{'unlinked': 3}),
    );

    final result = await AdminApi(ctx.transport).unlinkPerson(main);

    expect(result, const Result<int>.ok(3));
    expect(ctx.captured.single.method, 'DELETE');
  });
}
