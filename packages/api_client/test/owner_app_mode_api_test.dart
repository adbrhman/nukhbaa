import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

// NK292_16
/// Script 292: the app's mode, read and set from the owners' page.
void main() {
  test('ownerAppMode reads and setOwnerAppMode puts', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'schema_version': 1,
        'mode': 'closed',
        'reason': 'صيانة',
        'changed_by': 'you',
        'changed_at': '2026-11-20T12:00:00.000Z',
      }),
    );
    final AdminApi api = AdminApi(ctx.transport);

    final read = await api.ownerAppMode();
    final set = await api.setOwnerAppMode('closed', reason: 'صيانة');

    expect((read as Ok<AppModeDto>).value.mode, AppModeDto.closed);
    expect(set, isA<Ok<AppModeDto>>());
    expect(ctx.captured.first.method, 'GET');
    expect(ctx.captured.last.method, 'PUT');
    expect(ctx.captured.last.url.path, '/owner/mode');
    expect(jsonDecode(ctx.captured.last.body), {
      'mode': 'closed',
      'reason': 'صيانة',
    });
  });
}
