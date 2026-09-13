import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [AnnouncementRepository] over `notification.announcements`
/// (migration 0043), `identity.users` and `notification.device_tokens`
/// (migration 0039).
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter (Security ADR §2), and speaks only in domain types.
final class PostgresAnnouncementRepository implements AnnouncementRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresAnnouncementRepository(this._connection);

  final PostgresConnection _connection;

  static const String _saveSql = '''
INSERT INTO notification.announcements (id, title, body, author_id, created_at)
VALUES (@id, @title, @body, @author_id, @created_at)
''';

  // The ids arrive as one comma-separated string rather than an array
  // parameter: binding a `uuid[]` through the driver is what produced the 503
  // on `/rounds/{id}/fixtures`, and `string_to_array` avoids that class of bug
  // entirely while staying a bound parameter.
  static const String _findByIdsSql = '''
SELECT id::text AS id,
       title,
       body,
       author_id::text AS author_id,
       created_at
FROM notification.announcements
WHERE id::text = ANY(string_to_array(@ids, ','))
''';

  // LEFT JOIN, not JOIN: a user with no registered device is still part of the
  // audience -- they read the announcement in the app. Suspended accounts are
  // excluded; a sanctioned user is not addressed.
  static const String _audienceSql = '''
SELECT u.id::text AS user_id,
       dt.token AS token
FROM identity.users u
LEFT JOIN notification.device_tokens dt ON dt.user_id = u.id
WHERE u.status = 'active'
ORDER BY u.id
''';

  @override
  Future<Result<void>> save(Announcement announcement) async {
    final result = await _connection.query(
      _saveSql,
      parameters: {
        'id': announcement.id.value,
        'title': announcement.title,
        'body': announcement.body,
        'author_id': announcement.authorId.value,
        'created_at': announcement.createdAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<Announcement>>> findByIds(List<AnnouncementId> ids) async {
    if (ids.isEmpty) {
      return const Result.ok(<Announcement>[]);
    }
    final result = await _connection.query(
      _findByIdsSql,
      parameters: {
        'ids': [for (final id in ids) id.value].join(','),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(_map(value)),
    };
  }

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() async {
    final result = await _connection.query(_audienceSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        _audience(value),
      ),
    };
  }

  // A row that cannot be rebuilt is skipped rather than failing the whole
  // read: Tier-3, and one corrupt announcement must not empty an inbox.
  List<Announcement> _map(List<Map<String, dynamic>> rows) {
    final announcements = <Announcement>[];
    for (final row in rows) {
      final id = row['id'];
      final title = row['title'];
      final body = row['body'];
      final authorId = row['author_id'];
      final createdAt = row['created_at'];
      if (id is! String ||
          title is! String ||
          body is! String ||
          authorId is! String ||
          createdAt is! DateTime) {
        continue;
      }
      final parsedId = AnnouncementId.tryParse(id);
      final parsedAuthor = UserId.tryParse(authorId);
      if (parsedId is! Ok<AnnouncementId> || parsedAuthor is! Ok<UserId>) {
        continue;
      }
      announcements.add(
        Announcement.fromStored(
          id: parsedId.value,
          authorId: parsedAuthor.value,
          title: title,
          body: body,
          createdAt: createdAt.toUtc(),
        ),
      );
    }
    return List<Announcement>.unmodifiable(announcements);
  }

  List<AnnouncementRecipient> _audience(List<Map<String, dynamic>> rows) {
    final tokensByUser = <String, List<String>>{};
    for (final row in rows) {
      final userId = row['user_id'];
      if (userId is! String) {
        continue;
      }
      final tokens = tokensByUser.putIfAbsent(userId, () => <String>[]);
      final token = row['token'];
      if (token is String && token.isNotEmpty) {
        tokens.add(token);
      }
    }

    final recipients = <AnnouncementRecipient>[];
    for (final entry in tokensByUser.entries) {
      final user = UserId.tryParse(entry.key);
      if (user is! Ok<UserId>) {
        continue;
      }
      recipients.add(
        AnnouncementRecipient(
          userId: user.value,
          tokens: List<String>.unmodifiable(entry.value),
        ),
      );
    }
    return List<AnnouncementRecipient>.unmodifiable(recipients);
  }
}
