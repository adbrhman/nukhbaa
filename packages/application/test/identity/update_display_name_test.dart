import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _id = UserId('aaaaaaaa-0000-0000-0000-000000000001');
const _principal = AuthenticatedUser(userId: _id, role: PlatformRole.user);

User _user(String displayName) => User(
  id: _id,
  email: 'n72914939@gmail.com',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: displayName,
);

/// A directory holding one user, recording every rename it performs.
final class _Directory implements UserDirectory {
  _Directory(this.current);

  User current;
  final List<String> renames = <String>[];

  @override
  Future<Result<User?>> findUser(UserId id) async => Result.ok(current);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    renames.add(displayName);
    current = _user(displayName);
    return Result.ok(current);
  }

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();
}

void main() {
  test('an account that never chose a name chooses it once', () async {
    final directory = _Directory(_user('n72914939'));
    final useCase = UpdateDisplayName(userDirectory: directory);

    final first = await useCase(principal: _principal, displayName: ' Ali ');
    final second = await useCase(principal: _principal, displayName: 'Omar');

    expect((first as Ok<User>).value.displayName, 'Ali');
    expect((second as Err<User>).error.code, 'identity.display_name_immutable');
    expect(directory.renames, ['Ali']);
  });

  test('a registered name stays immutable', () async {
    final directory = _Directory(_user('Abdulrahman'));

    final result = await UpdateDisplayName(userDirectory: directory)(
      principal: _principal,
      displayName: 'Ali',
    );

    expect((result as Err<User>).error.code, 'identity.display_name_immutable');
    expect(directory.renames, isEmpty);
  });

  test('the automatic name itself is not a choice', () async {
    final directory = _Directory(_user('n72914939'));

    final result = await UpdateDisplayName(userDirectory: directory)(
      principal: _principal,
      displayName: 'n72914939',
    );

    expect(
      (result as Err<User>).error.code,
      'identity.display_name_is_default',
    );
    expect(directory.renames, isEmpty);
  });

  test('an empty name is refused before any lookup', () async {
    final directory = _Directory(_user('n72914939'));

    final result = await UpdateDisplayName(userDirectory: directory)(
      principal: _principal,
      displayName: '   ',
    );

    expect((result as Err<User>).error.code, 'identity.display_name_empty');
    expect(directory.renames, isEmpty);
  });
}
