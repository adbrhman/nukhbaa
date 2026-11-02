import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [NewPlayerReader] over `identity.users` (script 202).
///
/// For each plain player who joined in the window: the most accounts seen
/// on any of his phones (push tokens, migration 0177; install ids,
/// migration 0197), every prediction he sent, and why his name may not be
/// his real one -- the name the database gave from the e-mail, digits, one
/// word, a title for its first word, or Latin letters only.
///
/// Total: never throws; a malformed row is a transient
/// `identity.row_corrupt`.
final class PostgresNewPlayerReader implements NewPlayerReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresNewPlayerReader(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
WITH recent AS (
  SELECT u.id, u.email, u.role::text AS role, u.status::text AS status,
         u.display_name, u.created_at
  FROM identity.users u
  WHERE u.role = 'user'
    AND u.created_at >= now() - (@days::int * interval '1 day')
  ORDER BY u.created_at DESC
  LIMIT @limit
),
phones AS (
  SELECT token_key AS phone_key, user_id
  FROM notification.device_token_owners
  UNION
  SELECT install_key, user_id
  FROM identity.install_accounts
),
mine AS (
  SELECT ph.phone_key, ph.user_id
  FROM phones ph
  JOIN recent r ON r.id = ph.user_id
),
sizes AS (
  SELECT m.user_id, max(s.accounts) AS accounts
  FROM mine m
  JOIN (
    SELECT phone_key, count(DISTINCT user_id) AS accounts
    FROM phones
    WHERE phone_key IN (SELECT phone_key FROM mine)
    GROUP BY phone_key
  ) s ON s.phone_key = m.phone_key
  GROUP BY m.user_id
),
predicted AS (
  SELECT pa.user_id, count(*) AS predictions
  FROM prediction.fixture_predictions fp
  JOIN competition.participants pa ON pa.id = fp.participant_id
  WHERE pa.user_id IN (SELECT id FROM recent)
  GROUP BY pa.user_id
)
SELECT r.id::text AS id,
       r.email,
       r.role,
       r.status,
       r.display_name,
       r.created_at,
       coalesce(sz.accounts, 0)::int AS phone_accounts,
       coalesce(pr.predictions, 0)::int AS predictions,
       CASE
         WHEN r.display_name IS NULL OR btrim(r.display_name) = ''
           OR r.display_name = identity.automatic_display_name(r.email)
           THEN 'automatic'
         WHEN r.display_name ~ '[0-9]' THEN 'digits'
         WHEN btrim(r.display_name) !~ '\\s' THEN 'one_word'
         WHEN split_part(btrim(r.display_name), ' ', 1) IN (
           'ملك', 'بطل', 'هلال', 'جبل', 'حاطب', 'سائق', 'دكتور', 'الموج',
           'العقيد', 'التبع', 'هنا', 'نجم', 'اسطورة', 'أسطورة', 'عاشق',
           'زعيم', 'قناص', 'المايسترو', 'الملك', 'الزعيم'
         ) THEN 'title'
         WHEN r.display_name ~ '^[A-Za-z ._-]+\$' THEN 'latin'
         ELSE NULL
       END AS name_hint
FROM recent r
LEFT JOIN sizes sz ON sz.user_id = r.id
LEFT JOIN predicted pr ON pr.user_id = r.id
ORDER BY r.created_at DESC, r.id
''';

  @override
  Future<Result<List<NewPlayer>>> newPlayers({
    required int days,
    required int limit,
  }) async {
    final result = await _connection.query(
      _sql,
      parameters: {'days': days, 'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _map(value),
    };
  }

  static Result<List<NewPlayer>> _map(List<Map<String, dynamic>> rows) {
    final List<NewPlayer> out = <NewPlayer>[];
    for (final Map<String, dynamic> row in rows) {
      final idResult = UserId.tryParse(row['id']?.toString());
      if (idResult is Err<UserId>) return Result.err(_corrupt('id'));
      final roleResult = PlatformRole.tryParse(row['role']?.toString());
      if (roleResult is Err<PlatformRole>) return Result.err(_corrupt('role'));
      final UserStatus status;
      switch (row['status']?.toString()) {
        case 'active':
          status = UserStatus.active;
        case 'suspended':
          status = UserStatus.suspended;
        default:
          return Result.err(_corrupt('status'));
      }
      final DateTime? joined = switch (row['created_at']) {
        final DateTime t => t.toUtc(),
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      };
      if (joined == null) return Result.err(_corrupt('created_at'));
      out.add(
        NewPlayer(
          user: User(
            id: (idResult as Ok<UserId>).value,
            email: row['email'] as String?,
            role: (roleResult as Ok<PlatformRole>).value,
            status: status,
            displayName: (row['display_name'] as String?) ?? '',
          ),
          joinedAt: joined,
          phoneAccounts: _int(row['phone_accounts']),
          predictions: _int(row['predictions']),
          nameHint: switch (row['name_hint']?.toString()) {
            'automatic' => NewPlayerNameHint.automatic,
            'digits' => NewPlayerNameHint.digits,
            'one_word' => NewPlayerNameHint.oneWord,
            'title' => NewPlayerNameHint.title,
            'latin' => NewPlayerNameHint.latin,
            _ => null,
          },
        ),
      );
    }
    return Result.ok(List<NewPlayer>.unmodifiable(out));
  }

  static int _int(Object? raw) => switch (raw) {
    final int n => n,
    final Object other => int.tryParse(other.toString()) ?? 0,
    null => 0,
  };

  static AppError _corrupt(String field) => AppError.transient(
    'identity.row_corrupt',
    'A new-player row has an invalid $field',
  );
}
