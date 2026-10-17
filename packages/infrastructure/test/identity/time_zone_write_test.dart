import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _u1 = 'aaaaaaaa-0000-0000-0000-000000000001';
const _u2 = 'aaaaaaaa-0000-0000-0000-000000000002';

const _active = User(
  id: UserId(_u1),
  email: 'a@example.com',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: 'A',
);

const _down = Result<void>.err(AppError.transient('db.down', 'down'));

AuthenticatedUser _player(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.user);

final class _CountingDirectory implements UserDirectory {
  int offsetWrites = 0;
  final List<Result<void>> next = <Result<void>>[];

  @override
  Future<Result<void>> updateUtcOffsetMinutes(
    UserId userId,
    int minutes,
  ) async {
    offsetWrites++;
    return next.isEmpty ? const Result.ok(null) : next.removeAt(0);
  }

  @override
  Future<Result<User?>> findUser(UserId id) async => const Result.ok(_active);

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      const Result.ok(_active);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async => const Result.ok(_active);

  @override
  Future<Result<User>> setAvatar(
    UserId userId,
    List<int> bytes,
    String mime,
  ) async => const Result.ok(_active);

  @override
  Future<Result<User>> clearAvatar(UserId userId) async =>
      const Result.ok(_active);

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) async =>
      const Result.ok(null);
}

void main() {
  late _CountingDirectory inner;
  late DateTime clock;
  late UpdateTimeZoneOffset report;

  setUp(() {
    inner = _CountingDirectory();
    clock = DateTime.utc(2026, 10, 17, 21);
    report = UpdateTimeZoneOffset(
      userDirectory: CachedUserDirectory(inner, now: () => clock),
    );
  });

  Future<Result<void>> open(String user, int minutes) =>
      report(principal: _player(user), offsetMinutes: minutes);

  test('the same offset on every start is written once', () async {
    expect((await open(_u1, 180)).isOk, isTrue);
    expect((await open(_u1, 180)).isOk, isTrue);
    expect((await open(_u1, 180)).isOk, isTrue);

    expect(inner.offsetWrites, 1);
  });

  test('a changed offset is written, and so is the way back', () async {
    await open(_u1, 180);
    await open(_u1, 240);
    await open(_u1, 180);

    expect(inner.offsetWrites, 3);
  });

  test('each player is written once', () async {
    await open(_u1, 180);
    await open(_u2, 180);
    await open(_u2, 180);

    expect(inner.offsetWrites, 2);
  });

  test('a failed write is not remembered', () async {
    inner.next.add(_down);

    expect((await open(_u1, 180)).isOk, isFalse);
    expect((await open(_u1, 180)).isOk, isTrue);
    await open(_u1, 180);

    expect(inner.offsetWrites, 2);
  });

  test('an invalid offset is refused before any write', () async {
    expect((await open(_u1, 7)).isOk, isFalse);

    expect(inner.offsetWrites, 0);
  });

  test('the offset is written again after the ttl', () async {
    await open(_u1, 180);
    clock = clock.add(const Duration(hours: 13));
    await open(_u1, 180);

    expect(inner.offsetWrites, 2);
  });
}
