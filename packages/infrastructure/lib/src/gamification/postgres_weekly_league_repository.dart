import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [WeeklyLeagueRepository] over the tables of migration
/// 0061.
///
/// Placement runs inside one transaction and ends by RE-READING the seat, so
/// two concurrent first requests from the same player cannot produce two
/// seats: the second insert hits
/// `weekly_league_members_week_user_uniq`, does nothing, and the re-read
/// returns the seat the first one took. The same re-read covers the rarer
/// race where two players open the same new group at once -- one of the two
/// group inserts does nothing and its caller falls back to the open group
/// the other just created.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresWeeklyLeagueRepository implements WeeklyLeagueRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresWeeklyLeagueRepository(this._connection);

  final PostgresConnection _connection;

  static const String _seatSql = '''
SELECT m.league_id::text AS league_id,
       l.tier            AS tier,
       l.group_index     AS group_index,
       m.joined_at       AS joined_at
FROM gamification.weekly_league_members m
JOIN gamification.weekly_leagues l ON l.id = m.league_id
WHERE m.user_id = @user_id::uuid
  AND m.week_start = @week_start::date
''';

  static const String _openGroupSql = '''
SELECT l.id::text        AS league_id,
       l.tier            AS tier,
       l.group_index     AS group_index
FROM gamification.weekly_leagues l
LEFT JOIN gamification.weekly_league_members m ON m.league_id = l.id
WHERE l.week_start = @week_start::date
  AND l.tier = @tier::smallint
GROUP BY l.id, l.tier, l.group_index, l.capacity
HAVING count(m.user_id) < l.capacity
ORDER BY count(m.user_id) ASC, l.group_index ASC
LIMIT 1
''';

  static const String _openGroupInsertSql = '''
INSERT INTO gamification.weekly_leagues
  (id, week_start, tier, group_index, capacity)
SELECT @id::uuid,
       @week_start::date,
       @tier::smallint,
       (coalesce(max(group_index), -1) + 1)::smallint,
       @capacity::smallint
FROM gamification.weekly_leagues
WHERE week_start = @week_start::date
  AND tier = @tier::smallint
ON CONFLICT (week_start, tier, group_index) DO NOTHING
''';

  static const String _memberInsertSql = '''
INSERT INTO gamification.weekly_league_members
  (league_id, week_start, user_id)
VALUES (@league_id::uuid, @week_start::date, @user_id::uuid)
ON CONFLICT (week_start, user_id) DO NOTHING
''';

  static const String _lastFinishSql = '''
SELECT payload ->> 'tier'    AS tier,
       payload ->> 'outcome' AS outcome
FROM gamification.events
WHERE user_id = @user_id::uuid
  AND event_type = @event_type
ORDER BY occurred_at DESC
LIMIT 1
''';

  @override
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  }) async {
    final result = await _connection.query(
      _seatSql,
      parameters: {'user_id': userId.value, 'week_start': _isoDay(weekStart)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.ok(null)
            : _mapSeat(value.first, weekStart),
    };
  }

  @override
  Future<Result<WeeklyLeagueSeat>> place({
    required UserId userId,
    required DateTime weekStart,
    required WeeklyLeagueTier tier,
    required WeeklyLeagueId newLeagueId,
    required int capacity,
  }) async {
    final isoWeek = _isoDay(weekStart);

    return _connection.runInTransaction<WeeklyLeagueSeat>((tx) async {
      final openResult = await tx.query(
        _openGroupSql,
        parameters: {'week_start': isoWeek, 'tier': tier.level},
      );
      if (openResult is Err<List<Map<String, dynamic>>>) {
        return Result.err(openResult.error);
      }
      var open = (openResult as Ok<List<Map<String, dynamic>>>).value;

      if (open.isEmpty) {
        final created = await tx.query(
          _openGroupInsertSql,
          parameters: {
            'id': newLeagueId.value,
            'week_start': isoWeek,
            'tier': tier.level,
            'capacity': capacity,
          },
        );
        if (created is Err<List<Map<String, dynamic>>>) {
          return Result.err(created.error);
        }
        // Whether the insert landed or a concurrent one took the index, the
        // honest next step is the same: ask again which group is open.
        final reread = await tx.query(
          _openGroupSql,
          parameters: {'week_start': isoWeek, 'tier': tier.level},
        );
        if (reread is Err<List<Map<String, dynamic>>>) {
          return Result.err(reread.error);
        }
        open = (reread as Ok<List<Map<String, dynamic>>>).value;
        if (open.isEmpty) {
          return const Result.err(
            AppError.transient(
              'gamification.weekly_league_no_group',
              'No weekly league group could be opened',
            ),
          );
        }
      }

      final inserted = await tx.query(
        _memberInsertSql,
        parameters: {
          'league_id': open.first['league_id']?.toString(),
          'week_start': isoWeek,
          'user_id': userId.value,
        },
      );
      if (inserted is Err<List<Map<String, dynamic>>>) {
        return Result.err(inserted.error);
      }

      // The seat, as stored -- not as this call hoped to store it. A caller
      // that lost the race reads the winner's row here.
      final seatResult = await tx.query(
        _seatSql,
        parameters: {'user_id': userId.value, 'week_start': isoWeek},
      );
      if (seatResult is Err<List<Map<String, dynamic>>>) {
        return Result.err(seatResult.error);
      }
      final rows = (seatResult as Ok<List<Map<String, dynamic>>>).value;
      if (rows.isEmpty) {
        return const Result.err(
          AppError.transient(
            'gamification.weekly_league_not_seated',
            'The weekly league seat was not stored',
          ),
        );
      }
      return _mapSeat(rows.first, weekStart);
    });
  }

  @override
  Future<Result<WeeklyLeagueFinish?>> lastFinishOf({
    required UserId userId,
  }) async {
    final result = await _connection.query(
      _lastFinishSql,
      parameters: {
        'user_id': userId.value,
        'event_type': GamificationEventType.weeklyLeagueFinished.wireName,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapFinish(value.first),
    };
  }

  static Result<WeeklyLeagueSeat> _mapSeat(
    Map<String, dynamic> row,
    DateTime weekStart,
  ) {
    final idResult = WeeklyLeagueId.tryParse(row['league_id']?.toString());
    if (idResult is Err<WeeklyLeagueId>) {
      return Result.err(idResult.error);
    }
    final tier = WeeklyLeagueTier.ofLevel(_int(row['tier']));
    if (tier == null) {
      return const Result.err(
        AppError.transient(
          'gamification.weekly_league_tier_unknown',
          'Stored weekly league tier is not a known tier',
        ),
      );
    }
    final joinedAt = row['joined_at'];
    return Result.ok(
      WeeklyLeagueSeat(
        leagueId: (idResult as Ok<WeeklyLeagueId>).value,
        weekStart: weekStart,
        tier: tier,
        groupIndex: _int(row['group_index']),
        joinedAt: joinedAt is DateTime
            ? joinedAt.toUtc()
            : DateTime.tryParse(joinedAt?.toString() ?? '')?.toUtc() ??
                  weekStart,
      ),
    );
  }

  static Result<WeeklyLeagueFinish?> _mapFinish(Map<String, dynamic> row) {
    final tier = WeeklyLeagueTier.ofLevel(_int(row['tier']));
    if (tier == null) {
      // A row written by a future generation of the ladder: unreadable here,
      // and the honest answer is "no judged week I understand", which seats
      // the player in bronze rather than crashing their first request.
      return const Result.ok(null);
    }
    final raw = row['outcome']?.toString();
    for (final outcome in WeeklyLeagueOutcome.values) {
      if (outcome.wireName == raw) {
        return Result.ok(WeeklyLeagueFinish(tier: tier, outcome: outcome));
      }
    }
    return const Result.ok(null);
  }

  /// `smallint` may arrive as an int or, under a text-codec projection, as a
  /// string. A cast would throw, and this adapter is total.
  static int _int(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? -1;
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
