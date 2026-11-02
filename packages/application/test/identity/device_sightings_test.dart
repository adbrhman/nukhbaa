import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';

final class _Sightings implements DeviceSightings {
  final List<(String, String)> recorded = <(String, String)>[];
  List<SharedDeviceGroup> groups = const <SharedDeviceGroup>[];
  int? lastLimit;

  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) async {
    recorded.add((installId, userId.value));
    return const Result.ok(null);
  }

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({
    required int limit,
  }) async {
    lastLimit = limit;
    return Result.ok(groups);
  }
}

User _user(String id) => User(
  id: UserId(id),
  email: '$id@t.io',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: id,
);

/// Script 200: the phones accounts are played from.
void main() {
  const phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

  group('InstallId', () {
    test('reads the app id, trimmed and in lower case', () {
      expect(InstallId.parse(phone), phone);
      expect(InstallId.parse(' ${phone.toUpperCase()}\n'), phone);
    });

    test('anything else is no id', () {
      expect(InstallId.parse(null), isNull);
      expect(InstallId.parse(''), isNull);
      expect(InstallId.parse('abc'), isNull);
      expect(InstallId.parse('${phone}0'), isNull);
      expect(InstallId.parse(phone.replaceAll('-', '')), isNull);
    });
  });

  group('RecordDeviceSighting', () {
    test('records the caller on the install', () async {
      final sightings = _Sightings();

      final result = await RecordDeviceSighting(sightings: sightings)(
        principal: userPrincipal('11111111-1111-4111-8111-111111111111'),
        installId: phone.toUpperCase(),
      );

      expect(result, isA<Ok<void>>());
      expect(sightings.recorded, [
        (phone, '11111111-1111-4111-8111-111111111111'),
      ]);
    });

    test('no id or a malformed one records nothing', () async {
      final sightings = _Sightings();
      final record = RecordDeviceSighting(sightings: sightings);

      await record(principal: userPrincipal('u'), installId: null);
      await record(principal: userPrincipal('u'), installId: 'x');

      expect(sightings.recorded, isEmpty);
    });
  });

  group('AdminListSharedDevices', () {
    test('an admin reads the phones, bounded', () async {
      final sightings = _Sightings()
        ..groups = [
          SharedDeviceGroup(
            users: [_user('a'), _user('b')],
            lastSeen: DateTime.utc(2026, 11, 2),
          ),
        ];

      final result = await AdminListSharedDevices(devices: sightings)(
        principal: adminPrincipal('admin'),
      );

      final groups = (result as Ok<List<SharedDeviceGroup>>).value;
      expect(groups.single.users.map((u) => u.id.value), ['a', 'b']);
      expect(sightings.lastLimit, AdminListSharedDevices.maxGroups);
    });

    test('a player is refused and nothing is read', () async {
      final sightings = _Sightings();

      final result = await AdminListSharedDevices(devices: sightings)(
        principal: userPrincipal('player'),
      );

      expect(
        (result as Err<List<SharedDeviceGroup>>).error.kind,
        ErrorKind.authorization,
      );
      expect(sightings.lastLimit, isNull);
    });
  });
}
