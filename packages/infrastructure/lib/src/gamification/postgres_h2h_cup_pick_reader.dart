// NK311_01
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hCupPickReader] and [H2hCupOwnerPickReader]
/// (script 311). It reads; it writes nothing and scores nothing.
///
/// **A stage's fixtures.** A locked stage's are its frozen list
/// (`h2h_cup_stage_fixtures`, locked by `h2h_cup_stage_locks`); an unlocked
/// stage's are the visible, non-test fixtures of its Riyadh day, the list
/// `PostgresH2hCupStore` would freeze now. A fixture that left the stage's
/// day, was hidden, is a test fixture or had no result by the end of the
/// Riyadh day after the stage's comes back with `counted` false -- the very
/// condition `PostgresH2hCupStore` sums the stage with. All the stages come
/// from one statement.
///
/// **The picks.** One per player and fixture, over every participation the
/// player holds, as the stage sums them: the goals and the double of the
/// first submitted prediction, the stored points summed (null while every
/// score is still `pending` or none is stored), exact when any score says
/// so. A suspended or hidden account has none, as in the store. Only the
/// players of the stages' pairs are read, in one statement for all the
/// fixtures, and each stage keeps the picks of its own players.
///
/// **Secrecy.** [fixturesOf] selects another player's prediction only for a
/// fixture whose kickoff is at or before `@now` -- the server clock the
/// use-case passes, which then checks the same rule again. A fixture with no
/// kickoff, or one that has not kicked off, never brings that row out of the
/// database. The reader's own rows come always. [fixturesOfUnmasked] runs
/// the same statement without the mask, for the owners' gate alone: the two
/// pick statements differ in that one clause and nothing else.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hCupPickReader
    implements H2hCupPickReader, H2hCupOwnerPickReader {
  /// Creates the reader over [_connection].
  const PostgresH2hCupPickReader(this._connection);

  final PostgresConnection _connection;

  /// The fixtures of the stages in `@stage_ids` (comma separated), with the
  /// stage each belongs to, by kickoff.
  static const String fixturesSql = '''
WITH st AS (
  SELECT s.id, s.day, (k.stage_id IS NOT NULL) AS locked
  FROM gamification.h2h_cup_stages s
  LEFT JOIN gamification.h2h_cup_stage_locks k ON k.stage_id = s.id
  WHERE s.id = ANY(string_to_array(@stage_ids::text, ',')::uuid[])
),
list AS (
  SELECT st.id AS stage_id, st.day AS day, f.fixture_id AS fixture_id
  FROM st
  JOIN gamification.h2h_cup_stage_fixtures f ON f.stage_id = st.id
  WHERE st.locked
  UNION
  SELECT st.id, st.day, fs.fixture_id
  FROM st
  JOIN competition.fixture_schedules fs
    ON (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = st.day
  WHERE NOT st.locked
    AND fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND EXISTS (
      SELECT 1 FROM competition.season_fixtures sf
      WHERE sf.fixture_id = fs.fixture_id
    )
)
SELECT l.stage_id::text       AS stage_id,
       fs.fixture_id::text    AS fixture_id,
       fs.home_team           AS home_team,
       fs.away_team           AS away_team,
       fs.home_team_id::text  AS home_team_id,
       fs.away_team_id::text  AS away_team_id,
       fs.kickoff_at          AS kickoff_at,
       COALESCE(
         fs.hidden_at IS NULL
           AND NOT fs.is_test
           AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = l.day
           AND (res.created_at
                  < ((l.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
                OR now()
                  < ((l.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')),
         false)               AS counted,
       res.home_goals         AS home_goals,
       res.away_goals         AS away_goals
FROM list l
JOIN competition.fixture_schedules fs ON fs.fixture_id = l.fixture_id
LEFT JOIN scoring.fixture_results res ON res.fixture_id = l.fixture_id
ORDER BY l.stage_id, fs.kickoff_at NULLS LAST, fs.fixture_id
''';

  static const String _picksBase = '''
SELECT p.user_id::text            AS user_id,
       fp.fixture_id::text        AS fixture_id,
       fp.home_goals              AS home_goals,
       fp.away_goals              AS away_goals,
       fp.is_double               AS is_double,
       sc.points                  AS points,
       COALESCE(sc.exact, false)  AS exact
FROM competition.participants p
JOIN identity.users u ON u.id = p.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = sf.fixture_id AND fp.participant_id = p.id
LEFT JOIN LATERAL (
  SELECT (sum(s.points) FILTER (WHERE s.grade <> 'pending'))::integer AS points,
         bool_or(s.grade = 'exact_scoreline')                        AS exact
  FROM scoring.fixture_scores s
  WHERE s.fixture_id = fp.fixture_id
    AND s.participant_id = p.id
) sc ON true
WHERE sf.fixture_id = ANY(string_to_array(@fixture_ids::text, ',')::uuid[])
  AND p.user_id = ANY(string_to_array(@players::text, ',')::uuid[])
  AND u.status <> 'suspended'
  AND u.hidden_at IS NULL
''';

  static const String _picksMask = '''
  AND (p.user_id = @reader::uuid
       OR EXISTS (
         SELECT 1 FROM competition.fixture_schedules fs
         WHERE fs.fixture_id = fp.fixture_id
           AND fs.kickoff_at <= @now::timestamptz))
''';

  static const String _picksOrder = '''
ORDER BY p.user_id, fp.fixture_id, fp.submitted_at, p.id
''';

  /// The picks of the players of the stages, the reader's own and, for a
  /// fixture that has kicked off, everyone else's.
  static const String maskedPicksSql = '$_picksBase$_picksMask$_picksOrder';

  /// The picks of the players of the stages, all of them: for the owners'
  /// gate alone.
  static const String unmaskedPicksSql = '$_picksBase$_picksOrder';

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  }) => _read(
    stages: stages,
    picksSql: maskedPicksSql,
    extra: {'reader': reader.value, 'now': nowUtc.toUtc()},
  );

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>>
  fixturesOfUnmasked({required List<H2hCupStage> stages}) => _read(
    stages: stages,
    picksSql: unmaskedPicksSql,
    extra: const <String, Object?>{},
  );

  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> _read({
    required List<H2hCupStage> stages,
    required String picksSql,
    required Map<String, Object?> extra,
  }) async {
    if (stages.isEmpty) {
      return const Result.ok(<H2hCupStageId, List<H2hCupStageFixture>>{});
    }

    final fixturesResult = await _connection.query(
      fixturesSql,
      parameters: {'stage_ids': stages.map((s) => s.id.value).join(',')},
    );
    if (fixturesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(fixturesResult.error);
    }
    final rows = (fixturesResult as Ok<List<Map<String, dynamic>>>).value;

    final known = <String>{for (final s in stages) s.id.value};
    final stageOf = <String>[];
    final fixtureOf = <String>[];
    final fixtureIds = <String>{};
    for (final row in rows) {
      final stage = row['stage_id']?.toString();
      final id = row['fixture_id']?.toString();
      if (stage == null || !known.contains(stage) || id == null || id.isEmpty) {
        return Result.err(_corrupt('fixture'));
      }
      stageOf.add(stage);
      fixtureOf.add(id);
      fixtureIds.add(id);
    }

    final byStage = <H2hCupStageId, List<H2hCupStageFixture>>{
      for (final s in stages) s.id: <H2hCupStageFixture>[],
    };
    if (rows.isEmpty) {
      return Result.ok(byStage);
    }

    final players = <String>{};
    final playersOf = <String, Set<UserId>>{};
    for (final s in stages) {
      final own = playersOf.putIfAbsent(s.id.value, () => <UserId>{});
      for (final pair in s.pairs) {
        own
          ..add(pair.home)
          ..add(pair.away);
        players
          ..add(pair.home.value)
          ..add(pair.away.value);
      }
    }

    final picksResult = await _connection.query(
      picksSql,
      parameters: {
        'fixture_ids': fixtureIds.join(','),
        'players': players.join(','),
        ...extra,
      },
    );
    if (picksResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(picksResult.error);
    }
    final picks = <String, _Pick>{};
    for (final row in (picksResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final fixture = row['fixture_id']?.toString();
      final home = _int(row['home_goals']);
      final away = _int(row['away_goals']);
      if (user is Err<UserId> ||
          fixture == null ||
          home == null ||
          away == null) {
        return Result.err(_corrupt('prediction'));
      }
      final key = _key((user as Ok<UserId>).value, fixture);
      final points = _int(row['points']);
      final exact = row['exact'] == true;
      final seen = picks[key];
      if (seen == null) {
        picks[key] = _Pick(
          homeGoals: home,
          awayGoals: away,
          isDouble: row['is_double'] == true,
          points: points,
          exact: exact,
        );
      } else {
        seen
          ..points = _sum(seen.points, points)
          ..exact = seen.exact || exact;
      }
    }

    final stageById = <String, H2hCupStageId>{
      for (final s in stages) s.id.value: s.id,
    };
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final id = fixtureOf[i];
      final stage = stageOf[i];
      final mine = playersOf[stage] ?? const <UserId>{};
      final seen = <UserId, H2hFixturePick>{};
      for (final user in mine) {
        final pick = picks[_key(user, id)];
        if (pick != null) {
          seen[user] = pick.toPick();
        }
      }
      byStage[stageById[stage]!]!.add(
        H2hCupStageFixture(
          fixtureId: id,
          homeTeam: row['home_team']?.toString() ?? '',
          awayTeam: row['away_team']?.toString() ?? '',
          homeTeamId: row['home_team_id']?.toString(),
          awayTeamId: row['away_team_id']?.toString(),
          kickoffAt: _timestamp(row['kickoff_at']),
          counted: row['counted'] == true,
          homeGoals: _int(row['home_goals']),
          awayGoals: _int(row['away_goals']),
          picks: Map<UserId, H2hFixturePick>.unmodifiable(seen),
        ),
      );
    }
    return Result.ok(<H2hCupStageId, List<H2hCupStageFixture>>{
      for (final e in byStage.entries)
        e.key: List<H2hCupStageFixture>.unmodifiable(e.value),
    });
  }

  static String _key(UserId user, String fixture) => '${user.value}|$fixture';

  static int? _sum(int? a, int? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a + b;
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

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}

/// A pick while the participations of one player are folded into it.
final class _Pick {
  _Pick({
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    required this.points,
    required this.exact,
  });

  final int homeGoals;
  final int awayGoals;
  final bool isDouble;
  int? points;
  bool exact;

  H2hFixturePick toPick() => H2hFixturePick(
    homeGoals: homeGoals,
    awayGoals: awayGoals,
    isDouble: isDouble,
    points: points,
    exact: exact,
  );
}
