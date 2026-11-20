import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [AnnouncementRequestStore] over
/// `notification.announcement_requests` (script 290, migration 0220), with
/// each author's display name from `identity.users`.
///
/// Total: never throws; a malformed row is a transient
/// `notification.row_corrupt`.
// NK290_04
final class PostgresAnnouncementRequestStore
    implements AnnouncementRequestStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresAnnouncementRequestStore(this._connection);

  final PostgresConnection _connection;

  static const String _holdSql = '''
INSERT INTO notification.announcement_requests (id, author_id, title, body)
VALUES (@id::uuid, @author::uuid, @title, @body)
ON CONFLICT (id) DO NOTHING
RETURNING id
''';

  static const String _select = '''
SELECT r.id::text AS id,
       r.author_id::text AS author_id,
       coalesce(u.display_name, '') AS author_name,
       r.title,
       r.body,
       r.status,
       r.created_at,
       r.decided_at,
       r.recipients
FROM notification.announcement_requests r
JOIN identity.users u ON u.id = r.author_id
''';

  static const String _byIdSql =
      '''
$_select
WHERE r.id = @id::uuid
''';

  static const String _latestSql =
      '''
$_select
ORDER BY (r.status = 'pending') DESC, r.created_at DESC
LIMIT @limit
''';

  static const String _byAuthorSql =
      '''
$_select
WHERE r.author_id = @author::uuid
ORDER BY r.created_at DESC
LIMIT @limit
''';

  static const String _decideSql = '''
UPDATE notification.announcement_requests
SET status = @to,
    decided_by = @by::uuid,
    decided_at = now(),
    recipients = @recipients::int
WHERE id = @id::uuid AND status = 'pending'
RETURNING id
''';

  @override
  Future<Result<(AnnouncementRequest, bool)>> hold({
    required AnnouncementId id,
    required UserId author,
    required String title,
    required String body,
  }) async {
    final inserted = await _connection.query(
      _holdSql,
      parameters: {
        'id': id.value,
        'author': author.value,
        'title': title,
        'body': body,
      },
    );
    if (inserted is Err<List<Map<String, dynamic>>>) {
      return Result.err(inserted.error);
    }
    final bool fresh =
        (inserted as Ok<List<Map<String, dynamic>>>).value.isNotEmpty;
    final Result<AnnouncementRequest?> stored = await byId(id);
    return switch (stored) {
      Err<AnnouncementRequest?>(:final error) => Result.err(error),
      Ok<AnnouncementRequest?>(:final value) =>
        value == null ? const Result.err(_corrupt) : Result.ok((value, fresh)),
    };
  }

  @override
  Future<Result<AnnouncementRequest?>> byId(AnnouncementId id) async {
    final Result<List<AnnouncementRequest>> rows = await _rows(_byIdSql, {
      'id': id.value,
    });
    return switch (rows) {
      Err<List<AnnouncementRequest>>(:final error) => Result.err(error),
      Ok<List<AnnouncementRequest>>(:final value) => Result.ok(
        value.isEmpty ? null : value.first,
      ),
    };
  }

  @override
  Future<Result<List<AnnouncementRequest>>> latest({int limit = 50}) =>
      _rows(_latestSql, {'limit': limit});

  @override
  Future<Result<List<AnnouncementRequest>>> byAuthor(
    UserId author, {
    int limit = 20,
  }) => _rows(_byAuthorSql, {'author': author.value, 'limit': limit});

  @override
  Future<Result<bool>> decide({
    required AnnouncementId id,
    required AnnouncementRequestStatus to,
    required UserId by,
    int? recipients,
  }) async {
    final result = await _connection.query(
      _decideSql,
      parameters: {
        'id': id.value,
        'to': to.wire,
        'by': by.value,
        'recipients': recipients,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  Future<Result<List<AnnouncementRequest>>> _rows(
    String sql,
    Map<String, Object?> parameters,
  ) async {
    final result = await _connection.query(sql, parameters: parameters);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<AnnouncementRequest> out = <AnnouncementRequest>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final AnnouncementRequest? request = _map(row);
      if (request == null) return const Result.err(_corrupt);
      out.add(request);
    }
    return Result.ok(out);
  }

  static AnnouncementRequest? _map(Map<String, dynamic> row) {
    final Result<AnnouncementId> id = AnnouncementId.tryParse(
      row['id']?.toString(),
    );
    final Result<UserId> author = UserId.tryParse(row['author_id']?.toString());
    final AnnouncementRequestStatus? status = AnnouncementRequestStatus.byWire(
      row['status']?.toString() ?? '',
    );
    final DateTime? createdAt = _time(row['created_at']);
    final Object? title = row['title'];
    final Object? body = row['body'];
    final Object? name = row['author_name'];
    final Object? recipients = row['recipients'];
    if (id is! Ok<AnnouncementId> ||
        author is! Ok<UserId> ||
        status == null ||
        createdAt == null ||
        title is! String ||
        body is! String ||
        name is! String ||
        (recipients != null && recipients is! int)) {
      return null;
    }
    return AnnouncementRequest(
      id: id.value,
      authorId: author.value,
      authorName: name,
      title: title,
      body: body,
      status: status,
      createdAt: createdAt,
      decidedAt: _time(row['decided_at']),
      recipients: recipients as int?,
    );
  }

  static DateTime? _time(Object? raw) => switch (raw) {
    final DateTime t => t.toUtc(),
    final String s => DateTime.tryParse(s)?.toUtc(),
    _ => null,
  };

  static const AppError _corrupt = AppError.transient(
    'notification.row_corrupt',
    'An announcement request row is invalid',
  );
}
