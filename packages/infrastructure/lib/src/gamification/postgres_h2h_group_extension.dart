import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hGroupExtension] (2026-10-11): who is waiting
/// for a seat in a drawn month, and the groups added to it.
///
/// The new groups are ordinary rows of `h2h_leagues` and
/// `h2h_league_members` (0100), written in one transaction; 0100's own
/// constraints refuse a place or a player taken twice. The month row and
/// its `seated_count` (the seats of the draw itself) are not touched.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hGroupExtension implements H2hGroupExtension {
  /// Creates the adapter over an open [PostgresConnection].
  const PostgresH2hGroupExtension(this._connection);

  final PostgresConnection _connection;

  /// The players without a seat in the month who predicted on enough of
  /// its Riyadh days: the same reading of a month as the draw's
  /// `activeOrderSql`, ordered by days first.
  static const String waitingSql = '''
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
),
per AS (
  SELECT p.user_id,
         count(DISTINCT fx.d) FILTER (WHERE fp.id IS NOT NULL) AS active_days,
         COALESCE(sum(s.points), 0)                           AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')  AS exact
  FROM competition.participants p
  JOIN identity.users u ON u.id = p.user_id AND u.status <> 'suspended'
  JOIN fx ON fx.season_id = p.season_id
  LEFT JOIN prediction.fixture_predictions fp
    ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
  LEFT JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  WHERE NOT EXISTS (
    SELECT 1
    FROM gamification.h2h_league_members m
    WHERE m.month_start = @month::date
      AND m.user_id = p.user_id
  )
  GROUP BY p.user_id
)
SELECT user_id::text AS user_id
FROM per
WHERE active_days >= @min_days::integer
ORDER BY active_days DESC, points DESC, exact DESC, user_id
''';

  /// One new group of a drawn month.
  static const String insertGroupSql = '''
INSERT INTO gamification.h2h_leagues
  (id, month_start, division, group_index, capacity)
VALUES (@id::uuid, @month::date, @division::smallint,
        @group_index::smallint, @capacity::smallint)
''';

  /// One seat of a new group.
  static const String insertSeatSql = '''
INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES (@league_id::uuid, @month::date, @user_id::uuid, @slot::smallint)
''';

  @override
  Future<Result<List<UserId>>> waitingByParticipation({
    required DateTime monthStart,
    required int minActiveDays,
  }) async {
    final result = await _connection.query(
      waitingSql,
      parameters: {'month': _isoDay(monthStart), 'min_days': minActiveDays},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final users = <UserId>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final parsed = UserId.tryParse(row['user_id']?.toString());
      if (parsed is Err<UserId>) {
        return const Result.err(
          AppError.transient(
            'gamification.h2h_row_corrupt',
            'A stored head-to-head player is not a user id',
          ),
        );
      }
      users.add((parsed as Ok<UserId>).value);
    }
    return Result.ok(List<UserId>.unmodifiable(users));
  }

  @override
  Future<Result<int>> addGroups({
    required DateTime monthStart,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) {
    final month = _isoDay(monthStart);
    return _connection.runInTransaction<int>((tx) async {
      var seats = 0;
      for (final drawn in groups) {
        final group = await tx.query(
          insertGroupSql,
          parameters: {
            'id': drawn.leagueId.value,
            'month': month,
            'division': drawn.group.division.level,
            'group_index': drawn.group.groupIndex,
            'capacity': capacity,
          },
        );
        if (group is Err<List<Map<String, dynamic>>>) {
          return Result.err(_reclassify(group.error));
        }
        for (final seat in drawn.group.seats) {
          final row = await tx.query(
            insertSeatSql,
            parameters: {
              'league_id': drawn.leagueId.value,
              'month': month,
              'user_id': seat.userId.value,
              'slot': seat.slot,
            },
          );
          if (row is Err<List<Map<String, dynamic>>>) {
            return Result.err(_reclassify(row.error));
          }
          seats++;
        }
      }
      return Result.ok(seats);
    });
  }

  /// A database refusal, in the league's own words.
  static AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    return switch (cause.constraintName) {
      'h2h_leagues_month_division_index_uniq' => const AppError.invariant(
        'h2h.group_taken',
        'That group of the month was opened meanwhile; try again',
      ),
      'h2h_leagues_month_fkey' => const AppError.invariant(
        'h2h.month_not_drawn',
        'The month was not drawn',
      ),
      'h2h_league_members_month_user_uniq' ||
      'h2h_league_members_pkey' => const AppError.invariant(
        'h2h.player_seated',
        'A player already holds a seat this month',
      ),
      'h2h_league_members_user_id_fkey' => const AppError.invariant(
        'h2h.player_unknown',
        'No such player',
      ),
      _ => error,
    };
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
