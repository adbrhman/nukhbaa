import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

// NK289_13
/// Script 289: the owners' switches, read and turned from the app.
void main() {
  test('ownerSwitches reads the page', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'schema_version': 1,
        'switches': [
          {
            'key': 'crowning',
            'is_on': true,
            'reason': null,
            'changed_by': null,
            'changed_at': '2026-11-20T00:00:00.000Z',
          },
        ],
      }),
    );

    final result = await AdminApi(ctx.transport).ownerSwitches();

    final OwnerSwitchDto line =
        (result as Ok<OwnerSwitchesDto>).value.switches.single;
    expect(line.key, 'crowning');
    expect(line.isOn, isTrue);
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/owner/switches');
  });

  test('setOwnerSwitch puts the flag and its reason', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'key': 'crowning',
        'is_on': false,
        'reason': 'مراجعة',
        'changed_by': 'you',
        'changed_at': '2026-11-30T18:00:00.000Z',
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).setOwnerSwitch('crowning', on: false, reason: 'مراجعة');

    final OwnerSwitchDto line = (result as Ok<OwnerSwitchDto>).value;
    expect(line.isOn, isFalse);
    expect(line.changedBy, OwnerSwitchDto.byYou);
    final sent = ctx.captured.single;
    expect(sent.method, 'PUT');
    expect(sent.url.path, '/owner/switches/crowning');
    expect(jsonDecode(sent.body), <String, Object?>{
      'is_on': false,
      'reason': 'مراجعة',
    });
  });
}
