import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';

/// In-memory [UserDirectory] fake: accepts the write and records it, so a
/// rejected offset is visible as "the directory was never reached".
final class _RecordingUserDirectory implements UserDirectory {
  UserId? lastUserId;
  int? lastMinutes;

  @override
  Future<Result<void>> updateUtcOffsetMinutes(
    UserId userId,
    int minutes,
  ) async {
    lastUserId = userId;
    lastMinutes = minutes;
    return const Result.ok(null);
  }

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> updateDisplayName(UserId userId, String displayName) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();

  @override
  Future<Result<User?>> findUser(UserId id) => throw UnimplementedError();
}

AuthenticatedUser _principal() => const AuthenticatedUser(
  userId: UserId(_uuid),
  role: PlatformRole.user,
  email: 'a@example.com',
  displayName: 'Human',
);

void main() {
  group('UpdateTimeZoneOffset', () {
    test('records the offset against the principal itself', () async {
      final directory = _RecordingUserDirectory();
      final useCase = UpdateTimeZoneOffset(userDirectory: directory);

      final result = await useCase(principal: _principal(), offsetMinutes: 180);

      expect(result.isOk, isTrue);
      expect(directory.lastUserId, const UserId(_uuid));
      expect(directory.lastMinutes, 180);
    });

    test('accepts a quarter-hour zone west of UTC', () async {
      final directory = _RecordingUserDirectory();
      final useCase = UpdateTimeZoneOffset(userDirectory: directory);

      final result = await useCase(
        principal: _principal(),
        offsetMinutes: -210,
      );

      expect(result.isOk, isTrue);
      expect(directory.lastMinutes, -210);
    });

    test('rejects an offset outside the inhabited range', () async {
      final directory = _RecordingUserDirectory();
      final useCase = UpdateTimeZoneOffset(userDirectory: directory);

      final result = await useCase(principal: _principal(), offsetMinutes: 900);

      expect(result.isErr, isTrue);
      expect(directory.lastMinutes, isNull);
    });

    test('rejects an offset that is not a whole quarter-hour', () async {
      final directory = _RecordingUserDirectory();
      final useCase = UpdateTimeZoneOffset(userDirectory: directory);

      final result = await useCase(principal: _principal(), offsetMinutes: 185);

      expect(result.isErr, isTrue);
      expect(directory.lastMinutes, isNull);
    });
  });
}
