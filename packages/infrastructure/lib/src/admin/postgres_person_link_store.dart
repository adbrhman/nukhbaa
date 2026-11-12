import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PersonLinkStore] over `identity.person_links` and its
/// two functions (script 263, migration 0209), which hide and show the
/// accounts (`identity.users.hidden_at`) in the same transaction. The
/// boards drop a hidden account within their cache's life, as for the
/// owner's own hiding (0207).
///
/// Total: never throws; a malformed row is a transient
/// `identity.row_corrupt`.
final class PostgresPersonLinkStore implements PersonLinkStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresPersonLinkStore(this._connection);

  final PostgresConnection _connection;

  /// The most linked accounts one list returns.
  static const int maxListed = 500;

  static const String _listSql = '''
SELECT l.person_id::text AS person_id, u.id::text AS id, u.email,
       u.role::text AS role, u.status::text AS status, u.display_name,
       l.counted, u.hidden_at
FROM identity.person_links l
JOIN identity.users u ON u.id = l.user_id
ORDER BY l.person_id, (l.user_id = l.person_id) DESC, l.counted DESC,
         u.display_name, u.id
LIMIT @limit
''';

  static const String _setSql = '''
SELECT identity.set_person(
  @main::uuid,
  nullif(@second, '')::uuid,
  string_to_array(@others, ',')::uuid[],
  @by::uuid
) AS outcome
''';

  static const String _unlinkSql = '''
SELECT identity.unlink_person(@main::uuid) AS unlinked
''';

  @override
  Future<Result<List<LinkedPerson>>> list() async {
    final result = await _connection.query(
      _listSql,
      parameters: {'limit': maxListed},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final Map<String, List<LinkedAccount>> byPerson =
        <String, List<LinkedAccount>>{};
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final String? person = row['person_id']?.toString();
      final User? user = _user(row);
      final Object? counted = row['counted'];
      if (person == null || user == null || counted is! bool) {
        return Result.err(_corrupt);
      }
      (byPerson[person] ??= <LinkedAccount>[]).add(
        LinkedAccount(
          user: user,
          counted: counted,
          hidden: row['hidden_at'] != null,
        ),
      );
    }
    final List<LinkedPerson> people = <LinkedPerson>[];
    for (final MapEntry<String, List<LinkedAccount>> entry
        in byPerson.entries) {
      final Result<UserId> main = UserId.tryParse(entry.key);
      if (main is Err<UserId>) return Result.err(_corrupt);
      people.add(
        LinkedPerson(
          main: (main as Ok<UserId>).value,
          accounts: List<LinkedAccount>.unmodifiable(entry.value),
        ),
      );
    }
    return Result.ok(people);
  }

  @override
  Future<Result<PersonLinkRefusal?>> set({
    required UserId main,
    required UserId? second,
    required List<UserId> others,
    required UserId by,
  }) async {
    final result = await _connection.query(
      _setSql,
      parameters: {
        'main': main.value,
        'second': second?.value ?? '',
        'others': [for (final UserId id in others) id.value].join(','),
        'by': by.value,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    return switch (rows.isEmpty ? null : rows.first['outcome']?.toString()) {
      'ok' => const Result.ok(null),
      'too_few' => const Result.ok(PersonLinkRefusal.tooFew),
      'duplicate' => const Result.ok(PersonLinkRefusal.duplicate),
      'unknown' => const Result.ok(PersonLinkRefusal.unknown),
      'taken' => const Result.ok(PersonLinkRefusal.taken),
      _ => const Result.err(_corrupt),
    };
  }

  @override
  Future<Result<int>> unlink(UserId main) async {
    final result = await _connection.query(
      _unlinkSql,
      parameters: {'main': main.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? unlinked = rows.isEmpty ? null : rows.first['unlinked'];
    return unlinked is int ? Result.ok(unlinked) : const Result.err(_corrupt);
  }

  static User? _user(Map<String, dynamic> row) {
    final Result<UserId> id = UserId.tryParse(row['id']?.toString());
    final Result<PlatformRole> role = PlatformRole.tryParse(
      row['role']?.toString(),
    );
    final UserStatus? status = switch (row['status']?.toString()) {
      'active' => UserStatus.active,
      'suspended' => UserStatus.suspended,
      _ => null,
    };
    if (id is! Ok<UserId> || role is! Ok<PlatformRole> || status == null) {
      return null;
    }
    return User(
      id: id.value,
      email: row['email'] as String?,
      role: role.value,
      status: status,
      displayName: (row['display_name'] as String?) ?? '',
    );
  }

  static const AppError _corrupt = AppError.transient(
    'identity.row_corrupt',
    'A person-link row is invalid',
  );
}
