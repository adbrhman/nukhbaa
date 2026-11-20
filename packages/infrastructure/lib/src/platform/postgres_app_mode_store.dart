import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [AppModeStore] over `ops.app_mode` (script 292,
/// migration 0222): one row. Read on every call; the server's own cache
/// (`AppModeCache`) keeps it ten seconds at most.
///
/// Total: never throws; a malformed row is a transient `ops.row_corrupt`.
// NK292_03
final class PostgresAppModeStore implements AppModeStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresAppModeStore(this._connection);

  final PostgresConnection _connection;

  static const String _readSql = '''
SELECT mode, reason, changed_by::text AS changed_by, changed_at
FROM ops.app_mode
WHERE id
''';

  static const String _setSql = '''
INSERT INTO ops.app_mode (id, mode, reason, changed_by, changed_at)
VALUES (true, @mode, @reason, @by::uuid, now())
ON CONFLICT (id) DO UPDATE
SET mode = excluded.mode,
    reason = excluded.reason,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at
RETURNING mode
''';

  @override
  Future<Result<AppModeState>> read() async {
    final result = await _connection.query(_readSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      // No row yet (before 0222): the app works as it always did.
      return Result.ok(
        AppModeState(
          mode: AppMode.normal,
          changedAt: DateTime.utc(2026, 11, 20),
        ),
      );
    }
    final Map<String, dynamic> row = rows.first;
    final AppMode? mode = AppMode.byWire(row['mode']?.toString() ?? '');
    final DateTime? at = switch (row['changed_at']) {
      final DateTime t => t.toUtc(),
      final String s => DateTime.tryParse(s)?.toUtc(),
      _ => null,
    };
    final Object? reason = row['reason'];
    final Object? by = row['changed_by'];
    final Result<UserId>? parsed = by == null
        ? null
        : UserId.tryParse(by.toString());
    if (mode == null ||
        at == null ||
        parsed is Err<UserId> ||
        (reason != null && reason is! String)) {
      return const Result.err(_corrupt);
    }
    return Result.ok(
      AppModeState(
        mode: mode,
        reason: reason as String?,
        changedBy: parsed is Ok<UserId> ? parsed.value : null,
        changedAt: at,
      ),
    );
  }

  @override
  Future<Result<void>> set({
    required AppMode mode,
    required String reason,
    required UserId by,
  }) async {
    final result = await _connection.query(
      _setSql,
      parameters: {'mode': mode.wire, 'reason': reason, 'by': by.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.err(_corrupt) : const Result.ok(null),
    };
  }

  static const AppError _corrupt = AppError.transient(
    'ops.row_corrupt',
    'The app mode row is invalid',
  );
}
