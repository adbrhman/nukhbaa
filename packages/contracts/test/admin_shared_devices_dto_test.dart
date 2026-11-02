import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Script 200: `GET /admin/shared-devices` survives the wire.
void main() {
  const a = UserSummaryDto(
    id: '11111111-1111-4111-8111-111111111111',
    email: 'a@t.io',
    displayName: 'أحمد',
    status: 'active',
  );
  const b = UserSummaryDto(
    id: '22222222-2222-4222-8222-222222222222',
    displayName: 'خالد',
    status: 'suspended',
  );

  test('round-trips through JSON text', () {
    final dto = SharedDevicesDto(
      devices: [
        SharedDeviceDto(users: [a, b], lastSeen: DateTime.utc(2026, 11, 2, 9)),
      ],
    );

    final back = SharedDevicesDto.fromJson(
      jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
    );

    expect(back, dto);
    expect(back.devices.single.users[1].status, 'suspended');
    expect(dto.toJson()['devices'], [
      {
        'users': [a.toJson(), b.toJson()],
        'last_seen': '2026-11-02T09:00:00.000Z',
      },
    ]);
  });

  test('no phones is an empty list', () {
    expect(
      SharedDevicesDto.fromJson(const {'schema_version': 1, 'devices': []}),
      const SharedDevicesDto(devices: []),
    );
  });
}
