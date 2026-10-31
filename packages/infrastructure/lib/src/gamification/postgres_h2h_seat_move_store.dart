import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hSeatMoveStore] (migration 0189).
///
/// **Attendance** reads a locked round's frozen fixtures that are still on
/// its day, visible and real -- the round's own list -- and who holds a
/// prediction for at least one of them, over every participation. Results
/// are not read: a prediction is a presence whatever happens to the match,
/// and a late or missing result never makes an absence.
///
/// **Candidate facts** read the window the way the draw reads a month
/// (`PostgresH2hDrawSource.activeOrderSql`): the visible, non-test fixtures
/// of the player's seasons in the window, the ones he predicted, the days he
/// predicted on, his stored points and exact scorelines.
///
/// **A swap** is written with its admin-log row in one transaction; the
/// 0189 backstops (a player relegated or promoted twice, a seat changed
/// twice for a round, a round already started, a relegated player coming
/// back) arrive as constraint violations and are returned as the invariant
/// `h2h.move_refused`.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hSeatMoveStore implements H2hSeatMoveStore {
  /// Creates the store over [_connection].
  const PostgresH2hSeatMoveStore(this._connection);

  final PostgresConnection _connection;

  static const String movesSql = '''
SELECT id::text                              AS id,
       to_char(month_start, 'YYYY-MM-DD')    AS month,
       from_round                            AS from_round,
       kind                                  AS kind,
       out_user::text                        AS out_user,
       in_user::text                         AS in_user,
       elite_league_id::text                 AS elite_league_id,
       elite_slot                            AS elite_slot,
       extra_league_id::text                 AS extra_league_id,
       extra_slot                            AS extra_slot,
       absent_rounds::text                   AS absent_rounds,
       candidate::text                       AS candidate,
       reason                                AS reason,
       decided_by::text                      AS decided_by,
       created_at                            AS created_at
FROM gamification.h2h_seat_moves
WHERE month_start = @month::date
ORDER BY from_round, created_at, id
''';

  static const String attendanceSql = '''
WITH rd AS (
  SELECT r.id, r.day
  FROM gamification.h2h_rounds r
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE r.id = ANY(string_to_array(@round_ids, ',')::uuid[])
),
fx AS (
  SELECT rd.id AS round_id, rf.fixture_id, fs.kickoff_at
  FROM rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
)
SELECT rd.id::text AS round_id,
       (SELECT count(*) FROM fx WHERE fx.round_id = rd.id)::integer
                                                           AS fixtures,
       (SELECT max(fx.kickoff_at) FROM fx WHERE fx.round_id = rd.id)
                                                           AS last_kickoff,
       COALESCE((
         SELECT string_agg(DISTINCT p.user_id::text, ',')
         FROM fx
         JOIN prediction.fixture_predictions fp
           ON fp.fixture_id = fx.fixture_id
         JOIN competition.participants p ON p.id = fp.participant_id
         WHERE fx.round_id = rd.id
       ), '')                                              AS present
FROM rd
ORDER BY rd.day
''';

  static const String excusalsSql = '''
SELECT e.round_id::text  AS round_id,
       e.reason          AS reason,
       e.excused_by::text AS excused_by,
       e.created_at      AS created_at
FROM gamification.h2h_round_excusals e
WHERE e.round_id = ANY(string_to_array(@round_ids, ',')::uuid[])
''';

  static const String candidateFactsSql = '''
WITH fx AS (
  SELECT DISTINCT sf.season_id, fs.fixture_id,
         (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        > (@last_day::date - @days::integer)
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date <= @last_day::date
),
who AS (
  SELECT unnest(string_to_array(@user_ids, ',')::uuid[]) AS user_id
)
SELECT w.user_id::text                                            AS user_id,
       (count(DISTINCT fx.fixture_id)
          - count(DISTINCT fx.fixture_id) FILTER (WHERE fp.id IS NOT NULL)
       )::integer                                                 AS missed,
       COALESCE(sum(s.points), 0)::integer                        AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer              AS exact,
       count(DISTINCT fx.d) FILTER (WHERE fp.id IS NOT NULL)::integer
                                                                  AS active_days
FROM who w
LEFT JOIN competition.participants p ON p.user_id = w.user_id
LEFT JOIN fx ON fx.season_id = p.season_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
GROUP BY w.user_id
''';

  static const String insertMoveSql = '''
INSERT INTO gamification.h2h_seat_moves
  (id, month_start, from_round, kind, out_user, in_user,
   elite_league_id, elite_slot, extra_league_id, extra_slot,
   absent_rounds, candidate, reason, decided_by)
VALUES (@id::uuid, @month::date, @from_round::smallint, @kind::text,
        @out_user::uuid, @in_user::uuid,
        @elite_league_id::uuid, @elite_slot::smallint,
        @extra_league_id::uuid, @extra_slot::smallint,
        @absent_rounds::jsonb, @candidate::jsonb, @reason::text,
        @decided_by::uuid)
''';

  static const String logSql = '''
INSERT INTO gamification.h2h_admin_actions (id, action, actor, detail)
VALUES (@id::uuid, @action::text, @actor::uuid, @detail::jsonb)
''';

  static const String excuseSql = '''
INSERT INTO gamification.h2h_round_excusals (round_id, reason, excused_by)
VALUES (@round_id::uuid, @reason::text, @by::uuid)
ON CONFLICT (round_id) DO NOTHING
RETURNING 1 AS excused
''';

  static const String warningSql = '''
INSERT INTO gamification.h2h_absence_warnings (round_id, user_id)
VALUES (@round_id::uuid, @user_id::uuid)
ON CONFLICT (round_id, user_id) DO NOTHING
RETURNING 1 AS warned
''';

  static const String warningsSql = '''
SELECT w.round_id::text AS round_id,
       w.user_id::text  AS user_id,
       w.created_at     AS created_at
FROM gamification.h2h_absence_warnings w
WHERE w.round_id = ANY(string_to_array(@round_ids, ',')::uuid[])
ORDER BY w.created_at
''';

  static const String tokensSql = '''
SELECT dt.token AS token
FROM notification.device_tokens dt
JOIN identity.users u ON u.id = dt.user_id
WHERE dt.user_id = @user_id::uuid
  AND u.status = 'active'
ORDER BY dt.token
''';

  @override
  Future<Result<List<H2hSeatMove>>> movesOf(DateTime monthStart) async {
    final result = await _connection.query(
      movesSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final moves = <H2hSeatMove>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final move = _mapMove(row);
      if (move == null) {
        return Result.err(_corrupt('seat move'));
      }
      moves.add(move);
    }
    return Result.ok(List<H2hSeatMove>.unmodifiable(moves));
  }

  @override
  Future<Result<List<H2hRoundAttendance>>> attendance(
    List<H2hRound> rounds,
  ) async {
    if (rounds.isEmpty) {
      return const Result.ok(<H2hRoundAttendance>[]);
    }
    final result = await _connection.query(
      attendanceSql,
      parameters: {'round_ids': _ids(rounds)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <H2hRoundAttendance>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hRoundId.tryParse(row['round_id']?.toString());
      final fixtures = _int(row['fixtures']);
      final present = _users(row['present']?.toString());
      if (id is Err<H2hRoundId> || fixtures == null || present == null) {
        return Result.err(_corrupt('round attendance'));
      }
      out.add(
        H2hRoundAttendance(
          roundId: (id as Ok<H2hRoundId>).value,
          fixtures: fixtures,
          lastKickoff: _timestamp(row['last_kickoff']),
          present: present,
        ),
      );
    }
    return Result.ok(List<H2hRoundAttendance>.unmodifiable(out));
  }

  @override
  Future<Result<Map<H2hRoundId, H2hRoundExcusal>>> excusals(
    List<H2hRound> rounds,
  ) async {
    if (rounds.isEmpty) {
      return const Result.ok(<H2hRoundId, H2hRoundExcusal>{});
    }
    final result = await _connection.query(
      excusalsSql,
      parameters: {'round_ids': _ids(rounds)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <H2hRoundId, H2hRoundExcusal>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hRoundId.tryParse(row['round_id']?.toString());
      final by = UserId.tryParse(row['excused_by']?.toString());
      final at = _timestamp(row['created_at']);
      if (id is Err<H2hRoundId> || by is Err<UserId> || at == null) {
        return Result.err(_corrupt('round excusal'));
      }
      final roundId = (id as Ok<H2hRoundId>).value;
      out[roundId] = H2hRoundExcusal(
        roundId: roundId,
        reason: row['reason']?.toString() ?? '',
        by: (by as Ok<UserId>).value,
        at: at,
      );
    }
    return Result.ok(Map<H2hRoundId, H2hRoundExcusal>.unmodifiable(out));
  }

  @override
  Future<Result<List<H2hCandidateFacts>>> candidateFacts({
    required DateTime lastDay,
    required List<UserId> users,
  }) async {
    if (users.isEmpty) {
      return const Result.ok(<H2hCandidateFacts>[]);
    }
    final result = await _connection.query(
      candidateFactsSql,
      parameters: {
        'last_day': _isoDay(lastDay),
        'days': H2hAbsencePolicy.windowDays,
        'user_ids': [for (final u in users) u.value].join(','),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <H2hCandidateFacts>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final missed = _int(row['missed']);
      final points = _int(row['points']);
      final exact = _int(row['exact']);
      final days = _int(row['active_days']);
      if (user is Err<UserId> ||
          missed == null ||
          points == null ||
          exact == null ||
          days == null) {
        return Result.err(_corrupt('candidate facts'));
      }
      out.add(
        H2hCandidateFacts(
          userId: (user as Ok<UserId>).value,
          missed: missed,
          points: points,
          exact: exact,
          activeDays: days,
        ),
      );
    }
    return Result.ok(List<H2hCandidateFacts>.unmodifiable(out));
  }

  @override
  Future<Result<void>> recordMove({
    required H2hSeatMove move,
    required String logId,
  }) async {
    final facts = move.facts;
    final candidate = facts == null
        ? const <String, Object?>{}
        : <String, Object?>{
            'user_id': facts.userId.value,
            'missed': facts.missed,
            'points': facts.points,
            'exact': facts.exact,
            'active_days': facts.activeDays,
            'window_days': H2hAbsencePolicy.windowDays,
          };
    final absent = [
      for (final r in move.absentRounds)
        {'month': _isoDay(r.month), 'round': r.round},
    ];
    final result = await _connection.runInTransaction<void>((tx) async {
      final inserted = await tx.query(
        insertMoveSql,
        parameters: {
          'id': move.id,
          'month': _isoDay(move.monthStart),
          'from_round': move.fromRound,
          'kind': move.kind.wireName,
          'out_user': move.outUser.value,
          'in_user': move.inUser.value,
          'elite_league_id': move.eliteLeagueId.value,
          'elite_slot': move.eliteSlot,
          'extra_league_id': move.extraLeagueId.value,
          'extra_slot': move.extraSlot,
          'absent_rounds': jsonEncode(absent),
          'candidate': jsonEncode(candidate),
          'reason': move.reason,
          'decided_by': move.decidedBy?.value,
        },
      );
      if (inserted is Err<List<Map<String, dynamic>>>) {
        return Result.err(inserted.error);
      }
      final logged = await tx.query(
        logSql,
        parameters: {
          'id': logId,
          'action': H2hAdminActionKind.seatMoved.wireName,
          'actor': move.decidedBy?.value,
          'detail': jsonEncode({
            'move_id': move.id,
            'kind': move.kind.wireName,
            'from_round': move.fromRound,
            'out_user': move.outUser.value,
            'in_user': move.inUser.value,
            'absent_rounds': absent,
            'candidate': candidate,
            'reason': move.reason,
          }),
        },
      );
      if (logged is Err<List<Map<String, dynamic>>>) {
        return Result.err(logged.error);
      }
      return const Result.ok(null);
    });
    return switch (result) {
      Err<void>(:final error) => Result.err(_refusal(error)),
      Ok<void>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<bool>> excuse({
    required H2hRoundId roundId,
    required String reason,
    required UserId by,
    required String logId,
  }) async {
    return _connection.runInTransaction<bool>((tx) async {
      final inserted = await tx.query(
        excuseSql,
        parameters: {
          'round_id': roundId.value,
          'reason': reason,
          'by': by.value,
        },
      );
      if (inserted is Err<List<Map<String, dynamic>>>) {
        return Result.err(inserted.error);
      }
      if ((inserted as Ok<List<Map<String, dynamic>>>).value.isEmpty) {
        return const Result.ok(false);
      }
      final logged = await tx.query(
        logSql,
        parameters: {
          'id': logId,
          'action': H2hAdminActionKind.roundExcused.wireName,
          'actor': by.value,
          'detail': jsonEncode({'round_id': roundId.value, 'reason': reason}),
        },
      );
      if (logged is Err<List<Map<String, dynamic>>>) {
        return Result.err(logged.error);
      }
      return const Result.ok(true);
    });
  }

  @override
  Future<Result<bool>> recordWarning({
    required H2hRoundId roundId,
    required UserId userId,
  }) async {
    final result = await _connection.query(
      warningSql,
      parameters: {'round_id': roundId.value, 'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<List<({H2hRoundId roundId, UserId userId, DateTime at})>>>
  warningsOf(List<H2hRound> rounds) async {
    if (rounds.isEmpty) {
      return const Result.ok(
        <({H2hRoundId roundId, UserId userId, DateTime at})>[],
      );
    }
    final result = await _connection.query(
      warningsSql,
      parameters: {'round_ids': _ids(rounds)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <({H2hRoundId roundId, UserId userId, DateTime at})>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hRoundId.tryParse(row['round_id']?.toString());
      final user = UserId.tryParse(row['user_id']?.toString());
      final at = _timestamp(row['created_at']);
      if (id is Err<H2hRoundId> || user is Err<UserId> || at == null) {
        return Result.err(_corrupt('absence warning'));
      }
      out.add((
        roundId: (id as Ok<H2hRoundId>).value,
        userId: (user as Ok<UserId>).value,
        at: at,
      ));
    }
    return Result.ok(List.unmodifiable(out));
  }

  @override
  Future<Result<List<String>>> pushTokensOf(UserId userId) async {
    final result = await _connection.query(
      tokensSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          if (row['token'] is String && (row['token'] as String).isNotEmpty)
            row['token'] as String,
      ]),
    };
  }

  static H2hSeatMove? _mapMove(Map<String, dynamic> row) {
    final month = DateTime.tryParse(row['month']?.toString() ?? '');
    final fromRound = _int(row['from_round']);
    final kind = H2hSeatMoveKind.ofWire(row['kind']?.toString());
    final out = UserId.tryParse(row['out_user']?.toString());
    final inUser = UserId.tryParse(row['in_user']?.toString());
    final elite = H2hLeagueId.tryParse(row['elite_league_id']?.toString());
    final extra = H2hLeagueId.tryParse(row['extra_league_id']?.toString());
    final eliteSlot = _int(row['elite_slot']);
    final extraSlot = _int(row['extra_slot']);
    final createdAt = _timestamp(row['created_at']);
    final id = row['id']?.toString();
    if (month == null ||
        fromRound == null ||
        kind == null ||
        out is Err<UserId> ||
        inUser is Err<UserId> ||
        elite is Err<H2hLeagueId> ||
        extra is Err<H2hLeagueId> ||
        eliteSlot == null ||
        extraSlot == null ||
        createdAt == null ||
        id == null) {
      return null;
    }
    final decidedRaw = row['decided_by']?.toString();
    final decided = decidedRaw == null ? null : UserId.tryParse(decidedRaw);
    if (decided is Err<UserId>) {
      return null;
    }
    final outUser = (out as Ok<UserId>).value;
    return H2hSeatMove(
      id: id,
      monthStart: DateTime.utc(month.year, month.month, month.day),
      fromRound: fromRound,
      kind: kind,
      outUser: outUser,
      inUser: (inUser as Ok<UserId>).value,
      eliteLeagueId: (elite as Ok<H2hLeagueId>).value,
      eliteSlot: eliteSlot,
      extraLeagueId: (extra as Ok<H2hLeagueId>).value,
      extraSlot: extraSlot,
      absentRounds: _absent(row['absent_rounds']?.toString()),
      facts: _facts(row['candidate']?.toString()),
      reason: row['reason']?.toString(),
      decidedBy: decided == null ? null : (decided as Ok<UserId>).value,
      createdAt: createdAt,
    );
  }

  static List<({DateTime month, int round})> _absent(String? raw) {
    final decoded = _decode(raw);
    if (decoded is! List) {
      return const [];
    }
    final out = <({DateTime month, int round})>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final month = DateTime.tryParse(item['month']?.toString() ?? '');
      final round = _int(item['round']);
      if (month != null && round != null) {
        out.add((
          month: DateTime.utc(month.year, month.month, month.day),
          round: round,
        ));
      }
    }
    return List.unmodifiable(out);
  }

  static H2hCandidateFacts? _facts(String? raw) {
    final decoded = _decode(raw);
    if (decoded is! Map) {
      return null;
    }
    final user = UserId.tryParse(decoded['user_id']?.toString());
    final missed = _int(decoded['missed']);
    final points = _int(decoded['points']);
    final exact = _int(decoded['exact']);
    final days = _int(decoded['active_days']);
    if (user is Err<UserId> ||
        missed == null ||
        points == null ||
        exact == null ||
        days == null) {
      return null;
    }
    return H2hCandidateFacts(
      userId: (user as Ok<UserId>).value,
      missed: missed,
      points: points,
      exact: exact,
      activeDays: days,
    );
  }

  static Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  static Set<UserId>? _users(String? csv) {
    if (csv == null) {
      return null;
    }
    final out = <UserId>{};
    for (final part in csv.split(',')) {
      if (part.isEmpty) {
        continue;
      }
      final parsed = UserId.tryParse(part);
      if (parsed is Err<UserId>) {
        return null;
      }
      out.add((parsed as Ok<UserId>).value);
    }
    return out;
  }

  static String _ids(List<H2hRound> rounds) =>
      [for (final r in rounds) r.id.value].join(',');

  /// The 0189 refusals: one invariant code for the job and the desk.
  static AppError _refusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final name = cause.constraintName ?? '';
    if (name.startsWith('h2h_seat_moves_')) {
      return AppError.invariant(
        'h2h.move_refused',
        'The swap was refused: $name',
      );
    }
    return error;
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
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
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
