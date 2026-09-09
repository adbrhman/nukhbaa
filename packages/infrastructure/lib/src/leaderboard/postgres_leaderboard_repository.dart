import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [LeaderboardRepository] over two projection VIEWs:
/// `leaderboard.season_standings` (migration `0006_leaderboard.sql`, one row
/// per season participant) and `leaderboard.hall_of_fame_standings`
/// (migration `0011_hall_of_fame.sql`, one row per user aggregated across
/// every season — the Hall of Fame).
///
/// A leaderboard is a **read-side projection** over the ratified append-only
/// ledger (Axiom 5; Leaderboards architecture decision in project-context §2) —
/// NEVER a second source of truth for points. This adapter therefore issues a
/// single read: a `SELECT` over the VIEW, which is itself a
/// `SUM(amount) … GROUP BY participant` over a season-scoped join of
/// `ledger.point_entries` → `competition.rounds` (to bound the sum to the
/// season) LEFT-joined from `competition.participants` (so an enrolled-but-
/// never-credited participant still appears with a zero total). The adapter
/// carries no ranking logic: it returns **unranked** entries; the total order
/// (points desc, joinedAt asc, participant-id asc) and standard-competition
/// ("1224") ranks are applied by the pure domain [SeasonLeaderboard.rank] in
/// the use-case, so the ranking rule is framework-free and identical whoever
/// runs the query.
///
/// The adapter is *total* (Application ADR §2): it never throws. It speaks only
/// in the domain [LeaderboardEntry] and typed ids; SQL and rows never leak. A
/// driver failure is surfaced as [ErrorKind.transient]; a malformed row is
/// mapped to a transient `leaderboard.row_corrupt`. All queries bind values
/// through `@named` parameters (Security ADR §2).
final class PostgresLeaderboardRepository implements LeaderboardRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresLeaderboardRepository(this._connection);

  final PostgresConnection _connection;

  // Read the season's standings from the projection VIEW. The VIEW already
  // scopes the SUM to the season (via the round→season join inside it) and
  // LEFT-joins from participants, so every ACTIVE/WITHDRAWN participant of the
  // season appears exactly once — a never-credited one with total 0, count 0.
  // The order here is unspecified on purpose (the domain sorts + ranks); we do
  // not ORDER BY in SQL so the ranking rule lives in exactly one place.
  //
  // The read is against `leaderboard.season_standings_with_movement`
  // (migration `0030`), a superset of `season_standings`: the same columns
  // plus `previous_rank`, the participant's rank at the most recent daily
  // pg_cron snapshot. The view's own `current_rank`/`movement` columns are
  // deliberately NOT selected — the current rank is the domain's to assign,
  // and reading a second, SQL-computed rank alongside it would let the arrow
  // and the place disagree. The domain subtracts instead.
  static const String _selectSeasonStandingsSql = '''
SELECT participant_id, display_name, total_points, entry_count, joined_at,
       previous_rank, exact_count, settled_count
FROM leaderboard.season_standings_with_movement
WHERE season_id = @season_id
''';

  // Read the all-time standings from the projection VIEW, capped by an
  // already-clamped LIMIT (the use-case clamps an untrusted caller value; this
  // adapter trusts it, mirroring every other capped Tier-read adapter in the
  // codebase). No ORDER BY here either — the domain ranks (`HallOfFame.rank`).
  static const String _selectAllTimeStandingsSql = '''
SELECT user_id, display_name, total_points, seasons_played
FROM leaderboard.hall_of_fame_standings
LIMIT @limit
''';

  // The personal record. `current_rank` IS selected here, unlike the
  // season-standings read above -- and for the opposite reason. There the
  // whole board is in hand and the domain ranks it, so reading a second
  // SQL-computed rank would let two ranks disagree. Here exactly one row per
  // season is fetched, so there is no board for the domain to rank; the
  // view's rank is the only rank available, and it is computed by the same
  // rule (`rank() over (partition by season_id order by total_points desc)`).
  //
  // Ordered newest season first, by the season's own calendar window rather
  // than by label: labels are display strings and sort alphabetically, which
  // would put April above March in any year.
  static const String _selectUserSeasonRecordsSql = '''
SELECT c.id AS competition_id, c.name AS competition_name,
       s.id AS season_id, s.label AS season_label,
       s.start_at, s.end_at,
       v.current_rank, v.total_points, v.entry_count,
       v.exact_count, v.settled_count
FROM leaderboard.season_standings_with_movement v
JOIN competition.participants p ON p.id = v.participant_id
JOIN competition.seasons s ON s.id = v.season_id
JOIN competition.competitions c ON c.id = s.competition_id
WHERE p.user_id = @user_id
  -- A season that never held a fixture was never a contest, so a row in it is
  -- not a record of anything. This project carries seven such seasons: the
  -- league editions seeded alongside the monthly contest, open by date and
  -- permanently empty. Automatic enrolment (which predates the
  -- fixture requirement in `listOpenSeasonsWithFixtures`) put every user in
  -- all of them, which is why the trophy history opened on six identical
  -- "2026/27" rows at rank #1 with zero points and nothing behind them.
  AND EXISTS (
        SELECT 1 FROM competition.season_fixtures sf
        WHERE sf.season_id = s.id
      )
ORDER BY s.start_at DESC, s.id DESC
''';

  @override
  Future<Result<List<ParticipantSeasonRecord>>> userSeasonRecords({
    required UserId userId,
  }) async {
    final result = await _connection.query(
      _selectUserSeasonRecordsSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapSeasonRecords(value),
    };
  }

  static Result<List<ParticipantSeasonRecord>> _mapSeasonRecords(
    List<Map<String, dynamic>> rows,
  ) {
    final records = <ParticipantSeasonRecord>[];
    for (final row in rows) {
      final mapped = _mapSeasonRecord(row);
      if (mapped is Err<ParticipantSeasonRecord>) {
        return Result.err(mapped.error);
      }
      records.add((mapped as Ok<ParticipantSeasonRecord>).value);
    }
    return Result.ok(records);
  }

  static Result<ParticipantSeasonRecord> _mapSeasonRecord(
    Map<String, dynamic> row,
  ) {
    const String view = 'season_standings_with_movement';
    final competitionId = CompetitionId.tryParse(
      row['competition_id']?.toString(),
    );
    final seasonId = SeasonId.tryParse(row['season_id']?.toString());
    final competitionName = row['competition_name'];
    final seasonLabel = row['season_label'];
    final startAt = _readUtcTimestamp(row['start_at']);
    final endAt = _readUtcTimestamp(row['end_at']);
    final rank = row['current_rank'];
    final totalPoints = row['total_points'];
    final entryCount = row['entry_count'];
    final exactCount = row['exact_count'];
    final settledCount = row['settled_count'];

    if (competitionId is Err<CompetitionId>) {
      return Result.err(
        _corrupt(view, 'competition_id', competitionId.error.message),
      );
    }
    if (seasonId is Err<SeasonId>) {
      return Result.err(_corrupt(view, 'season_id', seasonId.error.message));
    }
    if (competitionName is! String || competitionName.isEmpty) {
      return Result.err(_corrupt(view, 'competition_name', 'null or empty'));
    }
    if (seasonLabel is! String || seasonLabel.isEmpty) {
      return Result.err(_corrupt(view, 'season_label', 'null or empty'));
    }
    if (startAt == null) {
      return Result.err(_corrupt(view, 'start_at', 'not a timestamp'));
    }
    if (endAt == null) {
      return Result.err(_corrupt(view, 'end_at', 'not a timestamp'));
    }
    if (rank is! int) {
      return Result.err(_corrupt(view, 'current_rank', 'not an integer'));
    }
    if (totalPoints is! int) {
      return Result.err(_corrupt(view, 'total_points', 'not an integer'));
    }
    if (entryCount is! int) {
      return Result.err(_corrupt(view, 'entry_count', 'not an integer'));
    }
    if (exactCount is! int) {
      return Result.err(_corrupt(view, 'exact_count', 'not an integer'));
    }
    if (settledCount is! int) {
      return Result.err(_corrupt(view, 'settled_count', 'not an integer'));
    }

    return Result.ok(
      ParticipantSeasonRecord(
        competitionId: (competitionId as Ok<CompetitionId>).value,
        competitionName: competitionName,
        seasonId: (seasonId as Ok<SeasonId>).value,
        seasonLabel: seasonLabel,
        startAt: startAt,
        endAt: endAt,
        rank: rank,
        totalPoints: totalPoints,
        entryCount: entryCount,
        exactCount: exactCount,
        settledCount: settledCount,
      ),
    );
  }

  @override
  Future<Result<List<LeaderboardEntry>>> seasonStandings(
    SeasonId seasonId,
  ) async {
    final result = await _connection.query(
      _selectSeasonStandingsSql,
      parameters: {'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapEntries(value),
    };
  }

  @override
  Future<Result<List<HallOfFameEntry>>> allTimeStandings({
    required int limit,
  }) async {
    final result = await _connection.query(
      _selectAllTimeStandingsSql,
      parameters: {'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapHallOfFameEntries(
        value,
      ),
    };
  }

  // --------------------------------------------------------------------------
  // Row mapping
  // --------------------------------------------------------------------------

  Result<List<LeaderboardEntry>> _mapEntries(List<Map<String, dynamic>> rows) {
    final entries = <LeaderboardEntry>[];
    for (final row in rows) {
      final mapped = _mapEntry(row);
      if (mapped is Err<LeaderboardEntry>) {
        return Result.err(mapped.error);
      }
      entries.add((mapped as Ok<LeaderboardEntry>).value);
    }
    return Result.ok(List<LeaderboardEntry>.unmodifiable(entries));
  }

  Result<LeaderboardEntry> _mapEntry(Map<String, dynamic> row) {
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final displayName = row['display_name']?.toString();
    final totalPoints = _readInt(row['total_points']);
    final entryCount = _readInt(row['entry_count']);
    final joinedAt = _readUtcTimestamp(row['joined_at']);
    // Nullable by design: no snapshot yet, or a participant who joined after
    // the last capture. Absent (not corrupt) — mapped straight to null.
    final previousRank = row['previous_rank'] == null
        ? null
        : _readInt(row['previous_rank']);
    // COALESCEd to 0 in the view, so a participant with no graded fixture
    // reads as 0/0 -- "no accuracy yet", never a corrupt row.
    final exactCount = _readInt(row['exact_count']) ?? 0;
    final settledCount = _readInt(row['settled_count']) ?? 0;

    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'season_standings',
          'participant_id',
          participantIdResult.error.message,
        ),
      );
    }
    if (displayName == null || displayName.isEmpty) {
      return Result.err(
        _corrupt('season_standings', 'display_name', 'null or empty'),
      );
    }
    if (totalPoints == null) {
      return Result.err(
        _corrupt('season_standings', 'total_points', 'not an integer'),
      );
    }
    if (entryCount == null) {
      return Result.err(
        _corrupt('season_standings', 'entry_count', 'not an integer'),
      );
    }
    if (joinedAt == null) {
      return Result.err(
        _corrupt('season_standings', 'joined_at', 'not a timestamp'),
      );
    }

    // The domain enforces the residual invariants (entryCount >= 0, joinedAt
    // UTC). A projected() Err means the stored projection is inconsistent with
    // the domain rule, so reclassify it as a corrupt-row transient rather than
    // leak a raw invariant/validation out of a read path.
    final projected = LeaderboardEntry.projected(
      participantId: (participantIdResult as Ok<ParticipantId>).value,
      displayName: displayName,
      totalPoints: totalPoints,
      entryCount: entryCount,
      joinedAt: joinedAt,
      previousRank: previousRank,
      exactCount: exactCount,
      settledCount: settledCount,
    );
    if (projected is Err<LeaderboardEntry>) {
      return Result.err(
        _corrupt('season_standings', 'row', projected.error.message),
      );
    }
    return projected;
  }

  Result<List<HallOfFameEntry>> _mapHallOfFameEntries(
    List<Map<String, dynamic>> rows,
  ) {
    final entries = <HallOfFameEntry>[];
    for (final row in rows) {
      final mapped = _mapHallOfFameEntry(row);
      if (mapped is Err<HallOfFameEntry>) {
        return Result.err(mapped.error);
      }
      entries.add((mapped as Ok<HallOfFameEntry>).value);
    }
    return Result.ok(List<HallOfFameEntry>.unmodifiable(entries));
  }

  Result<HallOfFameEntry> _mapHallOfFameEntry(Map<String, dynamic> row) {
    final userIdResult = UserId.tryParse(row['user_id']?.toString());
    final displayName = row['display_name']?.toString();
    final totalPoints = _readInt(row['total_points']);
    final seasonsPlayed = _readInt(row['seasons_played']);

    if (userIdResult is Err<UserId>) {
      return Result.err(
        _corrupt(
          'hall_of_fame_standings',
          'user_id',
          userIdResult.error.message,
        ),
      );
    }
    if (displayName == null || displayName.isEmpty) {
      return Result.err(
        _corrupt('hall_of_fame_standings', 'display_name', 'null or empty'),
      );
    }
    if (totalPoints == null) {
      return Result.err(
        _corrupt('hall_of_fame_standings', 'total_points', 'not an integer'),
      );
    }
    if (seasonsPlayed == null) {
      return Result.err(
        _corrupt('hall_of_fame_standings', 'seasons_played', 'not an integer'),
      );
    }

    final projected = HallOfFameEntry.projected(
      userId: (userIdResult as Ok<UserId>).value,
      displayName: displayName,
      totalPoints: totalPoints,
      seasonsPlayed: seasonsPlayed,
    );
    if (projected is Err<HallOfFameEntry>) {
      return Result.err(
        _corrupt('hall_of_fame_standings', 'row', projected.error.message),
      );
    }
    return projected;
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror the ledger/scoring/competition adapters)
  // --------------------------------------------------------------------------

  static int? _readInt(Object? raw) {
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

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String view, String field, String detail) =>
      AppError.transient(
        'leaderboard.row_corrupt',
        'Stored $view row has invalid $field: $detail',
      );
}
