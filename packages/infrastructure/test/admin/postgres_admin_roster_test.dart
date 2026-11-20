import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_admin_roster.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
    this.parameters.add(parameters);
    return _answers.removeAt(0);
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

const String _id = '00000000-0223-4000-8223-000000000002';
const String _by = '00000000-0223-4000-8223-000000000001';

// NK294_12
/// Script 294: the adapter the composition root wires for the owners'
/// hand on the admins. Its table and function are checked by
/// `supabase/tests/0223_admin_role_changes_test.sql`.
void main() {
  test('reads the admins', () async {
    final connection = _Connection([
      const Result.ok([
        {
          'id': _id,
          'display_name': 'خالد',
          'email': 'k@t.io',
          'status': 'suspended',
        },
      ]),
    ]);

    final result = await PostgresAdminRoster(connection).admins();

    final AdminMember member = (result as Ok<List<AdminMember>>).value.single;
    expect(member.displayName, 'خالد');
    expect(member.active, isFalse);
    expect(connection.sql.single, contains("role = 'admin'"));
  });

  test('promotes from user only, revokes from admin only', () async {
    final connection = _Connection([
      const Result.ok([
        {'id': _id},
      ]),
      const Result.ok([]),
    ]);
    final roster = PostgresAdminRoster(connection);

    final promoted = await roster.setRole(user: const UserId(_id), admin: true);
    final revoked = await roster.setRole(user: const UserId(_id), admin: false);

    expect((promoted as Ok<bool>).value, isTrue);
    expect((revoked as Ok<bool>).value, isFalse);
    expect(connection.sql.first, contains("AND role = 'user'"));
    expect(connection.sql.last, contains("AND role = 'admin'"));
  });

  test('ends the sessions through the function', () async {
    final connection = _Connection([
      const Result.ok([
        {'ended': 3},
      ]),
    ]);

    final result = await PostgresAdminRoster(
      connection,
    ).endSessions(const UserId(_id));

    expect((result as Ok<int>).value, 3);
    expect(connection.sql.single, contains('admin.end_user_sessions'));
  });

  test('keeps a change and reads the log', () async {
    final connection = _Connection([
      const Result.ok([]),
      Result.ok([
        {
          'user_name': 'خالد',
          'action': 'revoke',
          'reason': 'سوء استخدام',
          'by_name': null,
          'occurred_at': DateTime.utc(2026, 11, 20, 12),
          'sessions_ended': 2,
        },
      ]),
    ]);
    final roster = PostgresAdminRoster(connection);

    await roster.record(
      user: const UserId(_id),
      action: 'revoke',
      reason: 'سوء استخدام',
      by: const UserId(_by),
      sessionsEnded: 2,
    );
    final changes = await roster.changes();

    expect(connection.parameters.first, {
      'user': _id,
      'action': 'revoke',
      'reason': 'سوء استخدام',
      'by': _by,
      'ended': 2,
    });
    final RoleChange line = (changes as Ok<List<RoleChange>>).value.single;
    expect(line.byName, isNull);
    expect(line.sessionsEnded, 2);
  });
}
