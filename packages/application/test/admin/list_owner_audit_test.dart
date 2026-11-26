import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '00000000-0000-4000-8341-0000000000aa';
const _backup = '00000000-0000-4000-8341-0000000000ab';
const _admin = '00000000-0000-4000-8341-0000000000bb';
const _player = '00000000-0000-4000-8341-0000000000cc';

/// The seats: [_owner] and [_backup]; [fails] breaks every lookup.
final class _Seats implements OwnerNotices {
  bool fails = false;
  int lookups = 0;

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async {
    lookups++;
    return fails
        ? const Result.err(AppError.transient('db.down', 'down'))
        : Result.ok(
            user == const UserId(_owner) || user == const UserId(_backup),
          );
  }

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

/// The read port in memory: [answer] is what it returns; it keeps how often
/// it was asked and with which limit.
final class _Reader implements OwnerAuditReader {
  int calls = 0;
  int? askedLimit;
  Result<List<OwnerAuditLine>> answer = Result.ok([
    OwnerAuditLine(
      source: OwnerAuditLine.sourceAdmin,
      id: 3,
      actorName: 'owner',
      method: 'PATCH',
      path: '/admin/fixtures/f-1/result',
      at: DateTime.utc(2026, 11, 26, 12, 30),
      target: 'A x B',
      result: '2-1',
    ),
    OwnerAuditLine(
      source: OwnerAuditLine.sourceOwner,
      id: 3,
      actorName: 'owner',
      method: 'POST',
      path: '/owner/switches',
      at: DateTime.utc(2026, 11, 26, 12),
    ),
  ]);

  @override
  Future<Result<List<OwnerAuditLine>>> latest({int limit = 200}) async {
    calls++;
    askedLimit = limit;
    return answer;
  }
}

// NK341_03
/// Plan 339 to 348, script 341: the owners' read of their own actions.
void main() {
  late _Seats seats;
  late _Reader reader;
  late ListOwnerAudit audit;
  const AuthenticatedUser owner = AuthenticatedUser(
    userId: UserId(_owner),
    role: PlatformRole.admin,
  );
  const AuthenticatedUser backup = AuthenticatedUser(
    userId: UserId(_backup),
    role: PlatformRole.admin,
  );
  const AuthenticatedUser admin = AuthenticatedUser(
    userId: UserId(_admin),
    role: PlatformRole.admin,
  );
  const AuthenticatedUser player = AuthenticatedUser(
    userId: UserId(_player),
    role: PlatformRole.user,
  );

  setUp(() {
    seats = _Seats();
    reader = _Reader();
    audit = ListOwnerAudit(reader: reader, owners: seats);
  });

  test('an owner seat reads both sources as the reader gave them', () async {
    final result = await audit(principal: owner);

    final lines = (result as Ok<List<OwnerAuditLine>>).value;
    expect(lines.map((l) => l.source), ['admin', 'owner']);
    expect(lines.map((l) => l.id), [3, 3]);
    expect(lines.first.target, 'A x B');
    expect(lines.first.result, '2-1');
    expect(lines.last.target, isNull);
    expect(reader.calls, 1);
  });

  test('a backup seat reads too', () async {
    final result = await audit(principal: backup);

    expect(result, isA<Ok<List<OwnerAuditLine>>>());
    expect(reader.calls, 1);
  });

  test('an admin without a seat is refused and nothing is read', () async {
    final result = await audit(principal: admin);

    expect(
      (result as Err<List<OwnerAuditLine>>).error.code,
      'admin.owner_only',
    );
    expect(reader.calls, 0);
  });

  test('a player is refused by the role gate before any lookup', () async {
    final result = await audit(principal: player);

    expect(
      (result as Err<List<OwnerAuditLine>>).error.code,
      'auth.insufficient_role',
    );
    expect(seats.lookups, 0);
    expect(reader.calls, 0);
  });

  test('a failed seat lookup refuses (fails closed)', () async {
    seats.fails = true;

    final result = await audit(principal: owner);

    expect(
      (result as Err<List<OwnerAuditLine>>).error.code,
      'admin.owner_only',
    );
    expect(reader.calls, 0);
  });

  test('the limit is clamped to 1..200 and defaults to 200', () async {
    final asked = <int>[];
    for (final int? limit in <int?>[null, 0, -3, 1, 5, 200, 201, 5000]) {
      await audit(principal: owner, limit: limit);
      asked.add(reader.askedLimit!);
    }

    expect(asked, [200, 200, 200, 1, 5, 200, 200, 200]);
  });

  test('a failing reader passes its error through', () async {
    reader.answer = const Result.err(AppError.transient('db.down', 'down'));

    final result = await audit(principal: owner);

    expect((result as Err<List<OwnerAuditLine>>).error.code, 'db.down');
  });
}
