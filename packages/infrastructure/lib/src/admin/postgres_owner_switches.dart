import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [OwnerSwitches] over `ops.owner_switches` (script 286,
/// migration 0218). Read on every call: nothing is cached, so a switch
/// turned off takes effect on the next run. Also the owners' hands on them,
/// [OwnerSwitchSettings] (script 289).
///
/// Total: never throws; a malformed row is a transient `ops.row_corrupt`.
// NK289_03
final class PostgresOwnerSwitches
    implements OwnerSwitches, OwnerSwitchSettings {
  /// Creates the switches over an open [PostgresConnection].
  const PostgresOwnerSwitches(this._connection);

  final PostgresConnection _connection;

  // NK286_02
  static const String _sql = '''
SELECT is_on
FROM ops.owner_switches
WHERE switch_key = @key
''';

  @override
  Future<Result<bool>> isOn(OwnerSwitch which) async {
    final result = await _connection.query(
      _sql,
      parameters: {'key': which.key},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(true);
    }
    final Object? value = rows.first['is_on'];
    if (value is! bool) {
      return const Result.err(
        AppError.transient('ops.row_corrupt', 'An owner switch is not a flag'),
      );
    }
    return Result.ok(value);
  }

  static const String _allSql = '''
SELECT switch_key, is_on, reason, changed_by::text AS changed_by, changed_at
FROM ops.owner_switches
''';

  static const String _setSql = '''
INSERT INTO ops.owner_switches (switch_key, is_on, reason, changed_by, changed_at)
VALUES (@key, @on::boolean, @reason, @by::uuid, now())
ON CONFLICT (switch_key) DO UPDATE
SET is_on = excluded.is_on,
    reason = excluded.reason,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at
RETURNING switch_key
''';

  @override
  Future<Result<List<OwnerSwitchState>>> all() async {
    final result = await _connection.query(_allSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final Map<OwnerSwitch, Map<String, dynamic>> rows =
        <OwnerSwitch, Map<String, dynamic>>{};
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final OwnerSwitch? which = OwnerSwitch.byKey(
        row['switch_key']?.toString() ?? '',
      );
      if (which != null) rows[which] = row;
    }
    final List<OwnerSwitchState> out = <OwnerSwitchState>[];
    for (final OwnerSwitch which in OwnerSwitch.values) {
      final Map<String, dynamic>? row = rows[which];
      if (row == null) continue;
      final Object? on = row['is_on'];
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
      if (parsed is Err<UserId>) return const Result.err(_corrupt);
      if (on is! bool || at == null || (reason != null && reason is! String)) {
        return const Result.err(_corrupt);
      }
      out.add(
        OwnerSwitchState(
          which: which,
          isOn: on,
          reason: reason as String?,
          changedBy: parsed is Ok<UserId> ? parsed.value : null,
          changedAt: at,
        ),
      );
    }
    return Result.ok(out);
  }

  @override
  Future<Result<void>> set({
    required OwnerSwitch which,
    required bool on,
    required String reason,
    required UserId by,
  }) async {
    final result = await _connection.query(
      _setSql,
      parameters: {
        'key': which.key,
        'on': on,
        'reason': reason,
        'by': by.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.err(_corrupt) : const Result.ok(null),
    };
  }

  static const AppError _corrupt = AppError.transient(
    'ops.row_corrupt',
    'An owner switch row is invalid',
  );
}
