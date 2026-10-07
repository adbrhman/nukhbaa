import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres [FixtureVisibilityStore] over
/// `competition.fixture_schedules.hidden_at` (migration 0098).
///
/// One statement per call, whatever the number of fixtures, and only rows
/// whose state actually changes are touched, so the answer names exactly
/// the fixtures to audit. [onChanged] runs after every call that changed a
/// row, so a cache in front of the schedule reads drops what it held (the
/// composition root passes the schedule cache's `forget`).
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresFixtureVisibilityStore implements FixtureVisibilityStore {
  /// Creates the store over [_connection].
  const PostgresFixtureVisibilityStore(this._connection, {this.onChanged});

  final PostgresConnection _connection;

  /// Called after a call that changed at least one fixture.
  final void Function()? onChanged;

  // The ids travel as one comma-separated string cast server-side, the way
  // the score announcements bind theirs: no array parameter to encode.
  static const String _hideSql = '''
UPDATE competition.fixture_schedules
   SET hidden_at = now()
 WHERE fixture_id = ANY(string_to_array(@fixture_ids, ',')::uuid[])
   AND hidden_at IS NULL
RETURNING fixture_id::text AS fixture_id
''';

  static const String _showSql = '''
UPDATE competition.fixture_schedules
   SET hidden_at = NULL
 WHERE fixture_id = ANY(string_to_array(@fixture_ids, ',')::uuid[])
   AND hidden_at IS NOT NULL
RETURNING fixture_id::text AS fixture_id
''';

  @override
  Future<Result<List<FixtureRef>>> setHidden(
    List<FixtureRef> fixtures, {
    required bool hidden,
  }) async {
    if (fixtures.isEmpty) {
      return const Result.ok(<FixtureRef>[]);
    }
    final result = await _connection.query(
      hidden ? _hideSql : _showSql,
      parameters: {
        'fixture_ids': [for (final f in fixtures) f.value].join(','),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final changed = <FixtureRef>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final parsed = FixtureRef.tryParse(row['fixture_id']?.toString());
      if (parsed is Err<FixtureRef>) {
        return const Result.err(
          AppError.transient(
            'competition.fixture_visibility_corrupt',
            'A changed fixture_schedules row has an invalid fixture_id',
          ),
        );
      }
      changed.add((parsed as Ok<FixtureRef>).value);
    }
    if (changed.isNotEmpty) {
      onChanged?.call();
    }
    // In the order asked for, not the order Postgres returned them.
    final byId = {for (final f in changed) f.value: f};
    return Result.ok([
      for (final f in fixtures)
        if (byId.containsKey(f.value)) byId[f.value]!,
    ]);
  }
}
