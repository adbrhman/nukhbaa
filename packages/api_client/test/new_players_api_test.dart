import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 202: the admin reads the new players and writes first to one.
void main() {
  const String player = '11111111-1111-4111-8111-111111111111';

  test('newPlayers reads the window and round-trips the list', () async {
    final dto = NewPlayersDto(
      days: 7,
      players: [
        NewPlayerDto(
          user: const UserSummaryDto(
            id: player,
            email: 'p@t.io',
            displayName: 'ملك التوقعات',
            status: 'active',
          ),
          joinedAt: DateTime.utc(2026, 11, 2, 12),
          phoneAccounts: 11,
          predictions: 10,
          nameHint: 'title',
        ),
      ],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).newPlayers(days: 7);

    expect(result, Result<NewPlayersDto>.ok(dto));
    expect(ctx.captured.single.url.path, '/admin/new-players');
    expect(ctx.captured.single.url.queryParameters, {'days': '7'});
    expect(
      NewPlayersDto.fromJson(
        jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
      ),
      dto,
    );
  });

  test('messagePlayer posts the text to the player', () async {
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{
        'schema_version': 1,
        'id': 7,
        'sender': 'support',
        'body': 'أرسل اسمك',
        'created_at': '2026-11-02T13:00:00.000Z',
      }),
    );

    await AdminApi(ctx.transport).messagePlayer(player, 'أرسل اسمك');

    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/admin/support/players/$player/messages');
    expect(jsonDecode(sent.body), containsPair('body', 'أرسل اسمك'));
  });
}
