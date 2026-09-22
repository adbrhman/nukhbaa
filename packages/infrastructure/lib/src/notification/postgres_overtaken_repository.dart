import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [OvertakenRepository] (migrations 0039, 0055, 0061,
/// 0063, 0066, 0067).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in application types.
final class PostgresOvertakenRepository implements OvertakenRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresOvertakenRepository(this._connection);

  final PostgresConnection _connection;

  static const String _leaguesSql = '''
SELECT wl.id::text AS id
FROM gamification.weekly_leagues wl
WHERE wl.week_start = @week_start::date
ORDER BY wl.tier, wl.group_index
''';

  static const String _marksSql = '''
SELECT m.user_id::text AS user_id, m.rank AS rank
FROM gamification.weekly_league_rank_marks m
WHERE m.league_id = @league_id
''';

  static const String _saveMarkSql = '''
INSERT INTO gamification.weekly_league_rank_marks
  (league_id, user_id, rank, marked_at)
VALUES (@league_id, @user_id, @rank, @marked_at)
ON CONFLICT (league_id, user_id) DO UPDATE
  SET rank = EXCLUDED.rank,
      marked_at = EXCLUDED.marked_at
''';

  static const String _recipientsSql = '''
SELECT u.id::text AS user_id,
       dt.token AS token,
       u.utc_offset_minutes AS utc_offset_minutes,
       COALESCE(np.overtaken, true) AS overtaken,
       EXISTS (
         SELECT 1
         FROM notification.proactive_sends ps
         WHERE ps.user_id = u.id
           AND ps.kind = 'overtaken'
           AND ps.ref_id = @league_id
       ) AS already_sent
FROM identity.users u
JOIN notification.device_tokens dt ON dt.user_id = u.id
LEFT JOIN notification.notification_preferences np ON np.user_id = u.id
WHERE u.id::text = ANY(string_to_array(@user_ids, ','))
ORDER BY u.id
''';

  static const String _markSentSql = '''
INSERT INTO notification.proactive_sends
  (user_id, kind, ref_id, send_date, sent_at)
VALUES (@user_id, 'overtaken', @league_id, @send_date::date, @sent_at)
ON CONFLICT ON CONSTRAINT proactive_sends_pkey DO NOTHING
''';

  static const String _forgetTokenSql = '''
DELETE FROM notification.device_tokens
WHERE token = @token
''';

  static const AppError _corrupt = AppError.transient(
    'overtaken.row_corrupt',
    'an overtaken row had unexpected column types',
  );

  @override
  Future<Result<List<WeeklyLeagueId>>> openLeagues({
    required DateTime weekStart,
  }) async {
    final day = weekStart.toUtc();
    final result = await _connection.query(
      _leaguesSql,
      parameters: {
        'week_start':
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final ids = <WeeklyLeagueId>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final raw = row['id'];
      final parsed = WeeklyLeagueId.tryParse(raw is String ? raw : null);
      if (parsed is Err<WeeklyLeagueId>) {
        return const Result.err(_corrupt);
      }
      ids.add((parsed as Ok<WeeklyLeagueId>).value);
    }
    return Result.ok(ids);
  }

  @override
  Future<Result<Map<UserId, int>>> rankMarks(WeeklyLeagueId leagueId) async {
    final result = await _connection.query(
      _marksSql,
      parameters: {'league_id': leagueId.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final marks = <UserId, int>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final raw = row['user_id'];
      final rank = row['rank'];
      final user = UserId.tryParse(raw is String ? raw : null);
      if (user is Err<UserId> || rank is! int) {
        return const Result.err(_corrupt);
      }
      marks[(user as Ok<UserId>).value] = rank;
    }
    return Result.ok(marks);
  }

  @override
  Future<Result<void>> saveRankMarks({
    required WeeklyLeagueId leagueId,
    required Map<UserId, int> ranks,
    required DateTime now,
  }) {
    return _connection.runInTransaction<void>((tx) async {
      for (final entry in ranks.entries) {
        final result = await tx.query(
          _saveMarkSql,
          parameters: {
            'league_id': leagueId.value,
            'user_id': entry.key.value,
            'rank': entry.value,
            'marked_at': now.toUtc(),
          },
        );
        if (result is Err<List<Map<String, dynamic>>>) {
          return Result<void>.err(result.error);
        }
      }
      return const Result<void>.ok(null);
    });
  }

  @override
  Future<Result<Map<UserId, OvertakenRecipient>>> recipients({
    required WeeklyLeagueId leagueId,
    required List<UserId> userIds,
  }) async {
    if (userIds.isEmpty) {
      return const Result.ok(<UserId, OvertakenRecipient>{});
    }
    final result = await _connection.query(
      _recipientsSql,
      parameters: {
        'league_id': leagueId.value,
        'user_ids': [for (final user in userIds) user.value].join(','),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final order = <String>[];
    final tokens = <String, List<String>>{};
    final first = <String, Map<String, dynamic>>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final userId = row['user_id'];
      final token = row['token'];
      final optedIn = row['overtaken'];
      final alreadySent = row['already_sent'];
      final offset = row['utc_offset_minutes'];
      if (userId is! String ||
          token is! String ||
          optedIn is! bool ||
          alreadySent is! bool ||
          (offset != null && offset is! int)) {
        return const Result.err(_corrupt);
      }
      if (!first.containsKey(userId)) {
        order.add(userId);
        first[userId] = row;
      }
      tokens.putIfAbsent(userId, () => <String>[]).add(token);
    }
    final recipients = <UserId, OvertakenRecipient>{};
    for (final key in order) {
      final user = UserId.tryParse(key);
      if (user is Err<UserId>) {
        return const Result.err(_corrupt);
      }
      final row = first[key]!;
      final offset = row['utc_offset_minutes'];
      recipients[(user as Ok<UserId>).value] = OvertakenRecipient(
        tokens: List<String>.unmodifiable(tokens[key]!),
        optedIn: row['overtaken'] as bool,
        alreadySent: row['already_sent'] as bool,
        utcOffsetMinutes: offset is int ? offset : null,
      );
    }
    return Result.ok(recipients);
  }

  @override
  Future<Result<void>> markSent({
    required UserId userId,
    required WeeklyLeagueId leagueId,
    required String sendDate,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _markSentSql,
      parameters: {
        'user_id': userId.value,
        'league_id': leagueId.value,
        'send_date': sendDate,
        'sent_at': now.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async {
    for (final token in tokens) {
      final result = await _connection.query(
        _forgetTokenSql,
        parameters: {'token': token},
      );
      if (result is Err<List<Map<String, dynamic>>>) {
        return Result.err(result.error);
      }
    }
    return const Result.ok(null);
  }
}
