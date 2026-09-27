import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [ReferralAdminRepository] (migration 0075).
///
/// Reads `gamification.referral_invitations` (one row per invitation with
/// its state) and the `referrals` row of `gamification.feature_flags`.
/// Decides nothing: the states come from the append-only events.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresReferralAdminRepository implements ReferralAdminRepository {
  /// Creates the repository over [_connection].
  const PostgresReferralAdminRepository(this._connection);

  final PostgresConnection _connection;

  static const String _enabledSql = '''
SELECT COALESCE((
  SELECT f.enabled
  FROM gamification.feature_flags f
  WHERE f.flag_key = 'referrals'
), false) AS enabled
''';

  static const String _countsSql = '''
SELECT i.state AS state, count(*)::bigint AS n
FROM gamification.referral_invitations i
GROUP BY i.state
''';

  static const String _referrersSql = '''
SELECT i.referrer_id::text AS referrer_id,
       max(i.referrer_name) AS referrer_name,
       count(*)::bigint AS invited,
       count(*) FILTER (WHERE i.state = 'paid')::bigint AS paid,
       count(*) FILTER (WHERE i.state = 'pending')::bigint AS pending,
       count(*) FILTER (WHERE i.state = 'held')::bigint AS held,
       count(*) FILTER (
         WHERE i.state IN ('revoked', 'rejected')
       )::bigint AS refused,
       COALESCE((
         SELECT m.referral_points
         FROM gamification.referral_month_points m
         JOIN competition.seasons s
           ON s.id = m.season_id
         WHERE m.user_id = i.referrer_id
           AND s.start_at <= @now::timestamptz
           AND s.end_at > @now::timestamptz
         ORDER BY s.start_at DESC
         LIMIT 1
       ), 0)::bigint AS month_points
FROM gamification.referral_invitations i
GROUP BY i.referrer_id
ORDER BY invited DESC, i.referrer_id
LIMIT @limit::int
''';

  static const String _invitationsSql = '''
SELECT i.invitee_id::text AS invitee_id,
       i.invitee_name AS invitee_name,
       i.invitee_status AS invitee_status,
       i.referrer_id::text AS referrer_id,
       i.referrer_name AS referrer_name,
       i.claimed_at AS claimed_at,
       i.state AS state,
       i.paid_at AS paid_at,
       i.held_at AS held_at,
       i.revoked_at AS revoked_at,
       i.hold_reasons AS hold_reasons,
       i.revoke_reason AS revoke_reason,
       i.last_prediction_at AS last_prediction_at
FROM gamification.referral_invitations i
ORDER BY i.claimed_at DESC, i.invitee_id
LIMIT @limit::int
''';

  static const String _setEnabledSql = '''
UPDATE gamification.feature_flags
SET enabled = @enabled::boolean
WHERE flag_key = 'referrals'
RETURNING enabled
''';

  @override
  Future<Result<ReferralOverview>> overview({
    required DateTime now,
    required int referrerLimit,
    required int invitationLimit,
  }) async {
    final enabledResult = await _connection.query(_enabledSql);
    if (enabledResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(enabledResult.error);
    }
    final countsResult = await _connection.query(_countsSql);
    if (countsResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(countsResult.error);
    }
    final referrersResult = await _connection.query(
      _referrersSql,
      parameters: {'now': now.toUtc(), 'limit': referrerLimit},
    );
    if (referrersResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(referrersResult.error);
    }
    final invitationsResult = await _connection.query(
      _invitationsSql,
      parameters: {'limit': invitationLimit},
    );
    if (invitationsResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(invitationsResult.error);
    }

    final enabledRows = (enabledResult as Ok<List<Map<String, dynamic>>>).value;
    final bool enabled =
        enabledRows.isNotEmpty && enabledRows.first['enabled'] == true;

    final Map<String, int> counts = <String, int>{};
    for (final row in (countsResult as Ok<List<Map<String, dynamic>>>).value) {
      final String? state = row['state'] as String?;
      final int? n = _readInt(row['n']);
      if (state != null && n != null) {
        counts[state] = n;
      }
    }

    final referrers = <ReferrerTotals>[
      for (final row
          in (referrersResult as Ok<List<Map<String, dynamic>>>).value)
        ReferrerTotals(
          referrerId: (row['referrer_id'] as String?) ?? '',
          referrerName: (row['referrer_name'] as String?) ?? '',
          invited: _readInt(row['invited']) ?? 0,
          paid: _readInt(row['paid']) ?? 0,
          pending: _readInt(row['pending']) ?? 0,
          held: _readInt(row['held']) ?? 0,
          refused: _readInt(row['refused']) ?? 0,
          monthPoints: _readInt(row['month_points']) ?? 0,
        ),
    ];

    final invitations = <ReferralInvitation>[];
    for (final row
        in (invitationsResult as Ok<List<Map<String, dynamic>>>).value) {
      final Object? claimedAt = row['claimed_at'];
      if (claimedAt is! DateTime) {
        return const Result.err(
          AppError.invariant(
            'referral.row_corrupt',
            'Invitation row has no claim time',
          ),
        );
      }
      final String reasons = (row['hold_reasons'] as String?) ?? '';
      invitations.add(
        ReferralInvitation(
          inviteeId: (row['invitee_id'] as String?) ?? '',
          inviteeName: (row['invitee_name'] as String?) ?? '',
          inviteeStatus: (row['invitee_status'] as String?) ?? '',
          referrerId: (row['referrer_id'] as String?) ?? '',
          referrerName: (row['referrer_name'] as String?) ?? '',
          claimedAt: claimedAt.toUtc(),
          state: (row['state'] as String?) ?? '',
          holdReasons: [
            for (final String reason in reasons.split(','))
              if (reason.isNotEmpty) reason,
          ],
          paidAt: _readTime(row['paid_at']),
          heldAt: _readTime(row['held_at']),
          revokedAt: _readTime(row['revoked_at']),
          revokeReason: row['revoke_reason'] as String?,
          lastPredictionAt: _readTime(row['last_prediction_at']),
        ),
      );
    }

    return Result.ok(
      ReferralOverview(
        enabled: enabled,
        stateCounts: counts,
        referrers: referrers,
        invitations: invitations,
      ),
    );
  }

  @override
  Future<Result<bool>> setEnabled({required bool enabled}) async {
    final result = await _connection.query(
      _setEnabledSql,
      parameters: {'enabled': enabled},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty || rows.first['enabled'] is! bool) {
      return const Result.err(
        AppError.invariant(
          'referral.switch_missing',
          'The referrals switch row is missing (migration 0073)',
        ),
      );
    }
    return Result.ok(rows.first['enabled'] as bool);
  }

  static int? _readInt(Object? raw) => switch (raw) {
    final int value => value,
    final BigInt value => value.toInt(),
    final num value => value.toInt(),
    _ => null,
  };

  static DateTime? _readTime(Object? raw) =>
      raw is DateTime ? raw.toUtc() : null;
}
