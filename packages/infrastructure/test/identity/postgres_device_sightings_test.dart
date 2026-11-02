import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/identity/postgres_device_sightings.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  String? lastSql;
  Map<String, Object?>? lastParameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    lastSql = sql;
    lastParameters = parameters;
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _row(
  String phone,
  String id,
  DateTime seen, {
  String status = 'active',
}) => {
  'phone_key': phone,
  'last_seen': seen,
  'id': id,
  'email': '$id@t.io',
  'role': 'user',
  'status': status,
  'display_name': 'name $id',
};

/// Script 200: the store the composition root wires for `GET /me` and
/// `GET /admin/shared-devices`. Its SQL runs against the migration in
/// `supabase/tests/0197_shared_devices_test.sql`.
void main() {
  test('consecutive rows with one key form one phone, in order', () async {
    final seen = DateTime.utc(2026, 11, 2, 9);
    final connection = _FakeConnection(
      Result.ok([
        _row('{a,b,c}', _a, seen),
        _row('{a,b,c}', _b, seen),
        _row('{a,b,c}', _c, seen, status: 'suspended'),
        _row('{a,b}', _a, DateTime.utc(2026, 10, 1)),
        _row('{a,b}', _b, DateTime.utc(2026, 10, 1)),
      ]),
    );

    final result = await PostgresDeviceSightings(
      connection,
    ).sharedDevices(limit: 9);

    final phones = (result as Ok<List<SharedDeviceGroup>>).value;
    expect(phones, hasLength(2));
    expect(phones[0].users.map((u) => u.id.value), [_a, _b, _c]);
    expect(phones[0].users[2].status, UserStatus.suspended);
    expect(phones[0].lastSeen, seen);
    expect(phones[1].users, hasLength(2));
    expect(phones[1].lastSeen, DateTime.utc(2026, 10, 1));
    expect(connection.lastParameters, {'limit': 9});
  });

  test('no rows is no phones', () async {
    final result = await PostgresDeviceSightings(
      _FakeConnection(const Result.ok([])),
    ).sharedDevices(limit: 5);

    expect((result as Ok<List<SharedDeviceGroup>>).value, isEmpty);
  });

  test('a malformed row is a transient row_corrupt', () async {
    final result = await PostgresDeviceSightings(
      _FakeConnection(
        Result.ok([
          {..._row('{a}', _a, DateTime.utc(2026)), 'status': 'gone'},
        ]),
      ),
    ).sharedDevices(limit: 5);

    final error = (result as Err<List<SharedDeviceGroup>>).error;
    expect(error.code, 'identity.row_corrupt');
    expect(error.kind, ErrorKind.transient);
  });

  test('a sighting stores the install and the account', () async {
    final connection = _FakeConnection(const Result.ok([]));

    final result = await PostgresDeviceSightings(connection).record(
      installId: '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      userId: const UserId(_a),
    );

    expect(result, isA<Ok<void>>());
    expect(connection.lastSql, contains('identity.install_accounts'));
    expect(connection.lastParameters, {
      'install': '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      'user_id': _a,
    });
  });

  test('a failed write is passed on', () async {
    final result = await PostgresDeviceSightings(
      _FakeConnection(
        const Result.err(AppError.transient('db.unavailable', 'down')),
      ),
    ).record(installId: 'x', userId: const UserId(_a));

    expect((result as Err<void>).error.code, 'db.unavailable');
  });
}
