import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [CrestCatalog] (script 265, migration 0210).
///
/// The list is read by every start of the app, so it is held for [ttl] and
/// dropped by every write made through this catalog: the owner's change
/// reaches the next start at once on this server, and within [ttl] after a
/// change made elsewhere. Every write keeps its event in the same
/// statement.
///
/// Total: never throws; a malformed row is a transient `media.row_corrupt`.
final class PostgresCrestCatalog implements CrestCatalog {
  /// Creates the catalog over [_connection]; [now] is injectable for tests.
  PostgresCrestCatalog(
    this._connection, {
    this.ttl = const Duration(minutes: 5),
    DateTime Function() now = DateTime.now,
  }) : _held = TtlCache<int, CrestList>(ttl: ttl, maxEntries: 1, now: now);

  final PostgresConnection _connection;

  /// How long the list is held.
  final Duration ttl;

  final TtlCache<int, CrestList> _held;

  static const String _listSql = '''
SELECT s.clubs_enabled, c.slug, c.object_path, c.status, c.reason,
       c.complainant, c.changed_at
FROM media.crest_settings s
LEFT JOIN media.club_crests c ON true
WHERE s.id
ORDER BY c.slug
''';

  static const String _eventsSql = '''
SELECT e.slug, e.action, e.reason, e.complainant, e.at
FROM media.crest_events e
ORDER BY e.at DESC, e.id DESC
LIMIT @limit
''';

  static const String _moveSql = '''
WITH moved AS (
  UPDATE media.club_crests
  SET status = @to,
      reason = @reason,
      complainant = nullif(@complainant, ''),
      changed_at = now(),
      changed_by = @by::uuid
  WHERE slug = @slug
    AND status = ANY (string_to_array(@from, ','))
  RETURNING slug
), logged AS (
  INSERT INTO media.crest_events (slug, action, reason, complainant, actor_id)
  SELECT m.slug, @action, @reason, nullif(@complainant, ''), @by::uuid
  FROM moved m
  RETURNING id
)
SELECT count(*)::int AS moved FROM logged
''';

  static const String _switchSql = '''
WITH switched AS (
  UPDATE media.crest_settings
  SET clubs_enabled = @enabled::boolean,
      changed_at = now(),
      changed_by = @by::uuid
  WHERE id
  RETURNING id
)
INSERT INTO media.crest_events (action, reason, actor_id)
SELECT CASE WHEN @enabled::boolean THEN 'clubs_on' ELSE 'clubs_off' END,
       @reason, @by::uuid
FROM switched
RETURNING id
''';

  @override
  Future<Result<CrestList>> crests() async {
    final CrestList? held = _held.read(0);
    if (held != null) return Result.ok(held);
    final int startedAt = _held.generation;
    final result = await _connection.query(_listSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty || rows.first['clubs_enabled'] is! bool) {
      return const Result.err(_corrupt);
    }
    final List<ClubCrest> crests = <ClubCrest>[];
    for (final Map<String, dynamic> row in rows) {
      final Object? slug = row['slug'];
      if (slug == null) continue;
      final CrestStatus? status = CrestStatus.tryParse(
        row['status']?.toString(),
      );
      final Object? path = row['object_path'];
      if (slug is! String || path is! String || status == null) {
        return const Result.err(_corrupt);
      }
      crests.add(
        ClubCrest(
          slug: slug,
          objectPath: path,
          status: status,
          reason: row['reason'] as String?,
          complainant: row['complainant'] as String?,
          changedAt: _time(row['changed_at']),
        ),
      );
    }
    final CrestList list = CrestList(
      clubsEnabled: rows.first['clubs_enabled'] as bool,
      crests: List<ClubCrest>.unmodifiable(crests),
    );
    _held.write(0, list, startedAt: startedAt);
    return Result.ok(list);
  }

  @override
  Future<Result<List<CrestEvent>>> events({int limit = 50}) async {
    final result = await _connection.query(
      _eventsSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<CrestEvent> events = <CrestEvent>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? action = row['action'];
      final Object? reason = row['reason'];
      final DateTime? at = _time(row['at']);
      if (action is! String || reason is! String || at == null) {
        return const Result.err(_corrupt);
      }
      events.add(
        CrestEvent(
          action: action,
          slug: row['slug'] as String?,
          reason: reason,
          complainant: row['complainant'] as String?,
          at: at,
        ),
      );
    }
    return Result.ok(events);
  }

  @override
  Future<Result<bool>> setStatus({
    required String slug,
    required Set<CrestStatus> from,
    required CrestStatus to,
    required String action,
    required String reason,
    required String? complainant,
    required UserId by,
  }) async {
    final result = await _connection.query(
      _moveSql,
      parameters: {
        'slug': slug,
        'from': [for (final CrestStatus s in from) s.wireValue].join(','),
        'to': to.wireValue,
        'action': action,
        'reason': reason,
        'complainant': complainant ?? '',
        'by': by.value,
      },
    );
    _held.clear();
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? moved = rows.isEmpty ? null : rows.first['moved'];
    return moved is int ? Result.ok(moved > 0) : const Result.err(_corrupt);
  }

  @override
  Future<Result<void>> setClubsEnabled({
    required bool enabled,
    required String reason,
    required UserId by,
  }) async {
    final result = await _connection.query(
      _switchSql,
      parameters: {'enabled': enabled, 'reason': reason, 'by': by.value},
    );
    _held.clear();
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.err(_corrupt) : const Result.ok(null),
    };
  }

  static DateTime? _time(Object? raw) => switch (raw) {
    final DateTime t => t.toUtc(),
    final String s => DateTime.tryParse(s)?.toUtc(),
    _ => null,
  };

  static const AppError _corrupt = AppError.transient(
    'media.row_corrupt',
    'A crest row is invalid',
  );
}
