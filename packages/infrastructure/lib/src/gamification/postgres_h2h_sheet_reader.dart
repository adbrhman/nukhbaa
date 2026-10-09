import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hSheetReader] (migration 0100).
///
/// **A round's fixtures** are its frozen list (`h2h_round_fixtures`) less
/// every fixture that no longer belongs to the round's day, was hidden, or
/// is a test fixture: those are void for both sides. A locked round with no
/// fixture left is void altogether.
///
/// **A round's points** for a member are the stored scores of those
/// fixtures (the double included), over every participation the member
/// holds -- the reading the weekly league used. A round is SETTLED when each
/// of its fixtures has a result and no score of it is still pending.
///
/// Three statements, each one round trip; suspended members are left out,
/// so their seat plays the group average.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hSheetReader implements H2hSheetReader {
  /// Creates the reader over [_connection].
  const PostgresH2hSheetReader(this._connection);

  final PostgresConnection _connection;

  static const String membersSql = '''
SELECT m.user_id::text AS user_id,
       m.slot          AS slot,
       m.joined_at     AS joined_at
FROM gamification.h2h_league_members m
JOIN identity.users u ON u.id = m.user_id AND u.status <> 'suspended'
WHERE m.league_id = @league_id::uuid
ORDER BY m.slot
''';

  static const String scoresSql = '''
WITH members AS (
  SELECT m.user_id
  FROM gamification.h2h_league_members m
  JOIN identity.users u ON u.id = m.user_id AND u.status <> 'suspended'
  WHERE m.league_id = @league_id::uuid
),
rounds AS (
  SELECT r.id, r.round_no, r.day
  FROM gamification.h2h_leagues l
  JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE l.id = @league_id::uuid
),
valid AS (
  SELECT rd.round_no, rf.fixture_id
  FROM rounds rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
)
SELECT mb.user_id::text                                     AS user_id,
       v.round_no                                           AS round_no,
       COALESCE(sum(s.points), 0)::integer                  AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer        AS exact_count,
       count(fp.id)::integer                                AS predicted_count
FROM members mb
JOIN competition.participants p ON p.user_id = mb.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN valid v ON v.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = v.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = v.fixture_id AND s.participant_id = p.id
GROUP BY mb.user_id, v.round_no
HAVING count(fp.id) > 0
ORDER BY v.round_no, mb.user_id
''';

  static const String roundStatusSql = '''
WITH rounds AS (
  SELECT r.id, r.round_no, r.day
  FROM gamification.h2h_leagues l
  JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE l.id = @league_id::uuid
),
valid AS (
  SELECT rd.round_no, rf.fixture_id
  FROM rounds rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
)
SELECT rd.round_no                      AS round_no,
       count(v.fixture_id)::integer     AS fixtures,
       count(v.fixture_id) FILTER (
         WHERE res.fixture_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM scoring.fixture_scores sp
             WHERE sp.fixture_id = v.fixture_id
               AND sp.grade = 'pending'
           ))::integer                  AS settled
FROM rounds rd
LEFT JOIN valid v ON v.round_no = rd.round_no
LEFT JOIN scoring.fixture_results res ON res.fixture_id = v.fixture_id
GROUP BY rd.round_no
ORDER BY rd.round_no
''';

  static const String activeDaysSql = '''
WITH fx AS (
  SELECT DISTINCT sf.season_id, fs.fixture_id,
         (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date >= @month::date
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        < (@month::date + interval '1 month')::date
)
SELECT p.user_id::text           AS user_id,
       count(DISTINCT fx.d)::integer AS active_days
FROM competition.participants p
JOIN fx ON fx.season_id = p.season_id
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
GROUP BY p.user_id
''';

  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async {
    final parameters = <String, Object?>{'league_id': leagueId.value};

    final membersResult = await _connection.query(
      membersSql,
      parameters: parameters,
    );
    if (membersResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(membersResult.error);
    }
    final members = <H2hMember>[];
    for (final row in (membersResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final slot = _int(row['slot']);
      final joinedAt = _timestamp(row['joined_at']);
      if (user is Err<UserId> || slot == null || joinedAt == null) {
        return Result.err(_corrupt('member'));
      }
      members.add(
        H2hMember(
          userId: (user as Ok<UserId>).value,
          slot: slot,
          joinedAt: joinedAt,
        ),
      );
    }

    final scoresResult = await _connection.query(
      scoresSql,
      parameters: parameters,
    );
    if (scoresResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(scoresResult.error);
    }
    final scores = <H2hRoundScore>[];
    for (final row in (scoresResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final round = _int(row['round_no']);
      final points = _int(row['points']);
      final exact = _int(row['exact_count']);
      final predicted = _int(row['predicted_count']);
      if (user is Err<UserId> ||
          round == null ||
          points == null ||
          exact == null ||
          predicted == null) {
        return Result.err(_corrupt('score'));
      }
      scores.add(
        H2hRoundScore(
          userId: (user as Ok<UserId>).value,
          round: round,
          points: points,
          exactCount: exact,
          predictedCount: predicted,
        ),
      );
    }

    final statusResult = await _connection.query(
      roundStatusSql,
      parameters: parameters,
    );
    if (statusResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(statusResult.error);
    }
    final settled = <int>{};
    final voided = <int>{};
    for (final row in (statusResult as Ok<List<Map<String, dynamic>>>).value) {
      final round = _int(row['round_no']);
      final fixtures = _int(row['fixtures']);
      final done = _int(row['settled']);
      if (round == null || fixtures == null || done == null) {
        return Result.err(_corrupt('round'));
      }
      if (fixtures == 0) {
        voided.add(round);
      } else if (done == fixtures) {
        settled.add(round);
      }
    }

    return Result.ok(
      H2hGroupSheet(
        members: List<H2hMember>.unmodifiable(members),
        scores: List<H2hRoundScore>.unmodifiable(scores),
        settledRounds: Set<int>.unmodifiable(settled),
        voidRounds: Set<int>.unmodifiable(voided),
      ),
    );
  }

  @override
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart) async {
    final result = await _connection.query(
      activeDaysSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final days = <UserId, int>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final count = _int(row['active_days']);
      if (user is Err<UserId> || count == null) {
        return Result.err(_corrupt('activity'));
      }
      days[(user as Ok<UserId>).value] = count;
    }
    return Result.ok(Map<UserId, int>.unmodifiable(days));
  }

  static int? _int(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
  }

  static String _isoDay(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}
