import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [ReferralRepository] (migration 0073).
///
/// Every rule is a database function: one inviter per invitee, no
/// self-invitation, the 24-hour claim window, the qualification test, the
/// holds, the admin decisions and the once-only payment (the unique
/// `dedupe_key` of `gamification.events`). This adapter binds values and
/// maps rows; it decides nothing. Raw network addresses and install ids go
/// to the functions only to be hashed there.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresReferralRepository implements ReferralRepository {
  /// Creates the repository over [_connection].
  const PostgresReferralRepository(this._connection);

  final PostgresConnection _connection;

  static const String _ensureCodeSql = '''
SELECT gamification.ensure_referral_code(@user_id::uuid) AS code
''';

  // The function returns void; wrapping it keeps a void column off the wire.
  static const String _markInstallSql = '''
SELECT count(*)::bigint AS marked
FROM (
  SELECT gamification.mark_referral_install(
    @user_id::uuid, @install_id::text, @now::timestamptz
  )
) AS mark
''';

  static const String _countsSql = '''
SELECT
  COALESCE((
    SELECT m.referral_points
    FROM gamification.referral_month_points m
    JOIN competition.seasons s
      ON s.id = m.season_id
    WHERE m.user_id = @user_id::uuid
      AND s.start_at <= @now::timestamptz
      AND s.end_at > @now::timestamptz
    ORDER BY s.start_at DESC
    LIMIT 1
  ), 0)::bigint AS month_points,
  COALESCE((
    SELECT sp.referral_points
    FROM gamification.referral_season_points sp
    WHERE sp.user_id = @user_id::uuid
      AND sp.season_start_year = @season_start_year::int
  ), 0)::bigint AS season_points,
  (
    SELECT count(*)
    FROM gamification.referrals r
    WHERE r.referrer_id = @user_id::uuid
  )::bigint AS invited_count,
  (
    SELECT count(*)
    FROM gamification.referrals r
    WHERE r.referrer_id = @user_id::uuid
      AND NOT EXISTS (
        SELECT 1
        FROM gamification.events e
        WHERE e.ref_id = r.invitee_id
          AND e.event_type IN ('referral_qualified', 'referral_rejected')
      )
  )::bigint AS pending_count
''';

  static const String _claimSql = '''
SELECT gamification.claim_referral(
  @invitee::uuid, @code::text, @ip::text, @install_id::text, @now::timestamptz
) AS outcome
''';

  static const String _qualifySql = '''
SELECT gamification.qualify_referrals(@now::timestamptz)::bigint AS written
''';

  static const String _heldSql = '''
SELECT r.invitee_id::text AS invitee_id,
       iu.display_name AS invitee_name,
       r.referrer_id::text AS referrer_id,
       ru.display_name AS referrer_name,
       r.claimed_at AS claimed_at,
       h.occurred_at AS held_at,
       COALESCE(array_to_string(ARRAY(
         SELECT jsonb_array_elements_text(
           COALESCE(h.payload -> 'reasons', '[]'::jsonb)
         )
       ), ','), '') AS reasons
FROM gamification.events h
JOIN gamification.referrals r
  ON r.invitee_id = h.ref_id
JOIN identity.users iu
  ON iu.id = r.invitee_id
JOIN identity.users ru
  ON ru.id = r.referrer_id
WHERE h.event_type = 'referral_held'
  AND NOT EXISTS (
    SELECT 1
    FROM gamification.events d
    WHERE d.ref_id = h.ref_id
      AND d.event_type IN ('referral_qualified', 'referral_rejected')
  )
ORDER BY h.occurred_at, r.invitee_id
LIMIT @limit::int
''';

  static const String _reviewSql = '''
SELECT gamification.review_referral(
  @invitee::uuid, @decision::text, @admin::uuid, @reason::text,
  @now::timestamptz
) AS outcome
''';

  @override
  Future<Result<String>> ensureCode(UserId userId) async {
    final result = await _connection.query(
      _ensureCodeSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isNotEmpty && value.first['code'] is String
            ? Result.ok(value.first['code'] as String)
            : Result.err(_corrupt('code', 'no code returned')),
    };
  }

  @override
  Future<Result<void>> markInstall({
    required UserId userId,
    required String installId,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _markInstallSql,
      parameters: {
        'user_id': userId.value,
        'install_id': installId,
        'now': now.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<ReferralCounts>> counts({
    required UserId userId,
    required DateTime now,
    required int seasonStartYear,
  }) async {
    final result = await _connection.query(
      _countsSql,
      parameters: {
        'user_id': userId.value,
        'now': now.toUtc(),
        'season_start_year': seasonStartYear,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return Result.err(_corrupt('counts', 'no row returned'));
    }
    final row = rows.first;
    final monthPoints = _readInt(row['month_points']);
    final seasonPoints = _readInt(row['season_points']);
    final invitedCount = _readInt(row['invited_count']);
    final pendingCount = _readInt(row['pending_count']);
    if (monthPoints == null ||
        seasonPoints == null ||
        invitedCount == null ||
        pendingCount == null) {
      return Result.err(_corrupt('counts', 'not an integer'));
    }
    return Result.ok(
      ReferralCounts(
        monthPoints: monthPoints,
        seasonPoints: seasonPoints,
        invitedCount: invitedCount,
        pendingCount: pendingCount,
      ),
    );
  }

  @override
  Future<Result<ReferralClaimOutcome>> claim({
    required UserId invitee,
    required String code,
    required String? ip,
    required String? installId,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _claimSql,
      parameters: {
        'invitee': invitee.value,
        'code': code,
        'ip': ip,
        'install_id': installId,
        'now': now.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _claimOutcome(value),
    };
  }

  @override
  Future<Result<int>> qualify({required DateTime now}) async {
    final result = await _connection.query(
      _qualifySql,
      parameters: {'now': now.toUtc()},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final written = rows.isEmpty ? null : _readInt(rows.first['written']);
    return written == null
        ? Result.err(_corrupt('written', 'not an integer'))
        : Result.ok(written);
  }

  @override
  Future<Result<List<HeldReferral>>> held({required int limit}) async {
    final result = await _connection.query(
      _heldSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final held = <HeldReferral>[];
    for (final row in rows) {
      final Object? claimedAt = row['claimed_at'];
      final Object? heldAt = row['held_at'];
      if (claimedAt is! DateTime || heldAt is! DateTime) {
        return Result.err(_corrupt('held', 'not a timestamp'));
      }
      final String reasons = (row['reasons'] as String?) ?? '';
      held.add(
        HeldReferral(
          inviteeId: (row['invitee_id'] as String?) ?? '',
          inviteeName: (row['invitee_name'] as String?) ?? '',
          referrerId: (row['referrer_id'] as String?) ?? '',
          referrerName: (row['referrer_name'] as String?) ?? '',
          claimedAt: claimedAt.toUtc(),
          heldAt: heldAt.toUtc(),
          reasons: [
            for (final String reason in reasons.split(','))
              if (reason.isNotEmpty) reason,
          ],
        ),
      );
    }
    return Result.ok(held);
  }

  @override
  Future<Result<ReferralReviewOutcome>> review({
    required UserId invitee,
    required ReferralDecision decision,
    required UserId admin,
    required String reason,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _reviewSql,
      parameters: {
        'invitee': invitee.value,
        'decision': decision.wireName,
        'admin': admin.value,
        'reason': reason,
        'now': now.toUtc(),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final ReferralReviewOutcome? outcome = rows.isEmpty
        ? null
        : ReferralReviewOutcome.fromWire(rows.first['outcome'] as String?);
    return outcome == null
        ? Result.err(_corrupt('outcome', 'unknown review outcome'))
        : Result.ok(outcome);
  }

  static Result<ReferralClaimOutcome> _claimOutcome(
    List<Map<String, dynamic>> rows,
  ) {
    final ReferralClaimOutcome? outcome = rows.isEmpty
        ? null
        : ReferralClaimOutcome.fromWire(rows.first['outcome'] as String?);
    return outcome == null
        ? Result.err(_corrupt('outcome', 'unknown claim outcome'))
        : Result.ok(outcome);
  }

  static int? _readInt(Object? raw) => switch (raw) {
    final int value => value,
    final BigInt value => value.toInt(),
    final num value => value.toInt(),
    _ => null,
  };

  static AppError _corrupt(String field, String detail) => AppError.invariant(
    'referral.row_corrupt',
    'Invitation row has a corrupt $field: $detail',
  );
}
