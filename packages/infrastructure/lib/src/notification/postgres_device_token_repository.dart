import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [DeviceTokenRepository] over `notification.device_tokens`
/// (migration `0039_device_tokens.sql`).
///
/// [upsert] is a single `INSERT … ON CONFLICT (token) DO UPDATE`: a token is
/// its own primary key, so re-registering an already-known token (app
/// reinstall, token refresh, a different user signing in on the same device)
/// reassigns it rather than creating a duplicate row. `updated_at` is
/// stamped from Postgres's own `now()` on both branches — this is Tier-3
/// bookkeeping, not domain-modeled state, so no [Clock] dependency is
/// threaded through the adapter for it.
///
/// One push per phone (batch 118): a player who has the app (`android` or
/// `ios`) keeps no `web` token. The browser on the same phone showed every
/// push a second time, with a grey letter in place of the mark. So a native
/// registration retires the player's web tokens, and a web registration
/// from a player who already has a native token is not kept (the row is
/// removed if the token was on file, so it never stays with someone else).
/// A player with only the web build (the iPhone players) is unaffected.
///
/// The adapter is *total* (Application ADR §2): it never throws. A driver
/// failure is [ErrorKind.transient]; the one integrity case that can fire —
/// the user vanishing between authentication and this write — maps off the
/// FK's constraint name to [ErrorKind.invariant]. All queries bind values
/// through `@named` parameters (Security ADR §2).
final class PostgresDeviceTokenRepository implements DeviceTokenRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresDeviceTokenRepository(this._connection);

  final PostgresConnection _connection;

  static const String _upsertSql = '''
WITH native AS (
  SELECT EXISTS (
    SELECT 1
    FROM notification.device_tokens
    WHERE user_id = @user_id::uuid
      AND platform <> 'web'
      AND token <> @token::text
  ) AS present
),
retired_web AS (
  DELETE FROM notification.device_tokens
  WHERE @platform::text <> 'web'
    AND user_id = @user_id::uuid
    AND platform = 'web'
    AND token <> @token::text
),
skipped_web AS (
  DELETE FROM notification.device_tokens
  WHERE @platform::text = 'web'
    AND token = @token::text
    AND (SELECT present FROM native)
)
INSERT INTO notification.device_tokens (token, user_id, platform, updated_at)
SELECT @token::text, @user_id::uuid, @platform::text, now()
WHERE @platform::text <> 'web' OR NOT (SELECT present FROM native)
ON CONFLICT (token) DO UPDATE
  SET user_id = excluded.user_id,
      platform = excluded.platform,
      updated_at = now()
''';

  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) async {
    final result = await _connection.query(
      _upsertSql,
      parameters: {
        'token': token,
        'user_id': userId.value,
        'platform': platform,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    if (cause.code != '23503') {
      return error;
    }
    if (cause.constraintName == 'device_tokens_user_id_fkey') {
      return const AppError.invariant(
        'notification.device_token_user_not_found',
        'User not found',
      );
    }
    return error;
  }
}
