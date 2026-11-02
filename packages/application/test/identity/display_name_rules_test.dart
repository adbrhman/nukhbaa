import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const UserId _id = UserId('aaaaaaaa-0000-0000-0000-000000000001');
const AuthenticatedUser _principal = AuthenticatedUser(
  userId: _id,
  role: PlatformRole.user,
);

User _user(String displayName) => User(
  id: _id,
  email: 'n72914939@gmail.com',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: displayName,
);

/// A directory holding one player who never chose a name.
final class _Directory implements UserDirectory {
  User current = _user('n72914939');
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

/// The first name a player chooses, through the real use-case.
Future<(Result<User>, _Directory)> _choose(String name) async {
  final directory = _Directory();
  final result = await UpdateDisplayName(
    userDirectory: directory,
  ).call(principal: _principal, displayName: name);
  return (result, directory);
}

void main() {
  group('a name never passes for Nukhbaa\'s own accounts (M-4)', () {
    for (final String name in <String>[
      'دعم نُخبة',
      'دعم نخبه',
      'دعـم  نُـخبة',
      'الدعم',
      'نُخبة',
      'إدارة نخبة',
      'مشرف نُخبة',
      'نخبة الرسمي',
      'Nukhbaa Support',
      'nukhba_admin',
      'ADMIN',
    ]) {
      test(name, () async {
        final (Result<User> result, _Directory directory) = await _choose(name);
        expect(
          (result as Err<User>).error.code,
          'identity.display_name_reserved',
        );
        expect(directory.renames, isEmpty);
      });
    }
  });

  test('ordinary names, the word elite among them, are kept', () async {
    for (final String name in <String>[
      'خالد سالم',
      'نخبة الهلال',
      'Mohammed Elite',
      'مشرف القحطاني',
    ]) {
      final (Result<User> result, _Directory _) = await _choose(name);
      expect(result, isA<Ok<User>>(), reason: name);
    }
  });

  test('bidirectional overrides and invisible spaces are removed before the '
      'name is checked and stored', () async {
    final (Result<User> result, _Directory directory) = await _choose(
      '\u202Eخالد سالم\u200B\u200F',
    );
    expect((result as Ok<User>).value.displayName, 'خالد سالم');
    expect(directory.renames, <String>['خالد سالم']);

    final (Result<User> empty, _Directory _) = await _choose(
      '\u200B\u2060\uFEFF',
    );
    expect((empty as Err<User>).error.code, 'identity.display_name_empty');

    final (Result<User> hidden, _Directory _) = await _choose('دعم\u200Bنُخبة');
    expect((hidden as Err<User>).error.code, 'identity.display_name_reserved');
  });

  test('an emoji joined by U+200D stays whole', () async {
    final (Result<User> result, _Directory _) = await _choose(
      'سالم علي \u{1F468}\u200D\u{1F4BB}',
    );
    expect(
      (result as Ok<User>).value.displayName,
      'سالم علي \u{1F468}\u200D\u{1F4BB}',
    );
  });

  // Decided 2026-11-02: a new account's name is two-part.
  group('a new account chooses a two-part name', () {
    for (final String name in <String>[
      'خالد',
      'Ali',
      '  عبدالرحمن   ',
      'محمد 10',
      'سالم \u{1F468}\u200D\u{1F4BB}',
      'م ع',
      'محمد ـــ',
      'محمد.علي',
    ]) {
      test('"$name" is one name', () async {
        final (Result<User> result, _Directory directory) = await _choose(name);
        expect(
          (result as Err<User>).error.code,
          'identity.display_name_not_two_part',
        );
        expect(directory.renames, isEmpty);
      });
    }

    test('two words of two letters or more are kept', () async {
      for (final String name in <String>[
        'محمد علي',
        'أبو محمد',
        ' عبدالرحمن   المغربي ',
        'Mohammed Ali',
        'مُحَمَّد عَلِي',
      ]) {
        final (Result<User> result, _Directory _) = await _choose(name);
        expect(result, isA<Ok<User>>(), reason: name);
      }
    });
  });
}
