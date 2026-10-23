import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres [FixtureMerger] (migration 0176, script 95).
///
/// [merge] is one call of `competition.merge_fixture_copies`, so the moves,
/// the hiding, the provider link and the audit row share one transaction;
/// its refusals (`fixture_merge_*`) come back in Arabic. [onChanged] runs
/// after a merge that was applied, so the schedule cache drops the copy it
/// held as shown (the composition root passes the schedule cache's
/// `forget`). [copiesOf] is tested in
/// supabase/tests/fixture_copies_query_test.sql.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresFixtureMerger implements FixtureMerger {
  /// Creates the merger over [_connection].
  const PostgresFixtureMerger(this._connection, {this.onChanged});

  final PostgresConnection _connection;

  /// Called after a merge that was applied.
  final void Function()? onChanged;

  static const String _mergeSql = '''
SELECT moved, doubles_moved, doubles_dropped, both_predicted, late,
       not_participant, link_moved, kept_has_result
FROM competition.merge_fixture_copies(
  @duplicate::uuid, @kept::uuid, @actor::uuid, @apply::boolean)
''';

  // The fixture, then every non-test fixture less than 12 hours from it
  // with one of its clubs (0110 name key or the same catalog team, 0175),
  // or the same match put back up to 7 days later with the same two
  // catalog teams in one of its seasons (0182), not merged yet (0176).
  static const String _copiesSql = '''
WITH me AS (
  SELECT s.*,
         competition.team_name_key(s.home_team) AS h,
         competition.team_name_key(s.away_team) AS a
  FROM competition.fixture_schedules s
  WHERE s.fixture_id = @fixture_id::uuid
)
SELECT s.fixture_id::text AS fixture_id,
       s.home_team,
       s.away_team,
       s.kickoff_at,
       s.hidden_at IS NOT NULL AS hidden,
       (SELECT count(*) FROM prediction.fixture_predictions fp
         WHERE fp.fixture_id = s.fixture_id)::int AS predictions,
       (SELECT count(*) FROM prediction.fixture_predictions fp
         WHERE fp.fixture_id = s.fixture_id AND fp.is_double)::int AS doubles,
       EXISTS (SELECT 1 FROM scoring.fixture_results r
                WHERE r.fixture_id = s.fixture_id) AS has_result,
       EXISTS (SELECT 1 FROM football_data.external_identity_map m
                WHERE m.canonical_table = 'fixture'
                  AND m.canonical_id = s.fixture_id) AS linked,
       s.fixture_id = me.fixture_id AS is_self
FROM me
JOIN competition.fixture_schedules s
  ON s.fixture_id = me.fixture_id
  OR (NOT me.is_test
      AND NOT s.is_test
      AND s.kickoff_at > me.kickoff_at - interval '12 hours'
      AND s.kickoff_at < me.kickoff_at + interval '12 hours'
      AND NOT EXISTS (SELECT 1 FROM competition.fixture_merges fm
                       WHERE fm.duplicate_fixture_id = s.fixture_id)
      AND COALESCE(
            (s.home_team_id IS NOT NULL
               AND s.home_team_id IN (me.home_team_id, me.away_team_id))
            OR (s.away_team_id IS NOT NULL
               AND s.away_team_id IN (me.home_team_id, me.away_team_id))
            OR competition.team_name_key(s.home_team) IN (me.h, me.a)
            OR competition.team_name_key(s.away_team) IN (me.h, me.a),
            false))
  OR (NOT me.is_test
      AND NOT s.is_test
      AND NOT EXISTS (SELECT 1 FROM competition.fixture_merges fm
                       WHERE fm.duplicate_fixture_id = s.fixture_id)
      AND s.home_team_id = me.home_team_id
      AND s.away_team_id = me.away_team_id
      AND s.kickoff_at > me.kickoff_at
      AND s.kickoff_at <= me.kickoff_at + interval '7 days'
      AND EXISTS (SELECT 1
                    FROM competition.season_fixtures a
                    JOIN competition.season_fixtures b
                      ON b.season_id = a.season_id
                   WHERE a.fixture_id = me.fixture_id
                     AND b.fixture_id = s.fixture_id))
ORDER BY s.fixture_id = me.fixture_id DESC, s.kickoff_at, s.fixture_id
LIMIT 20
''';

  /// The Arabic refusal of each `fixture_merge_*` constraint.
  static const Map<String, String> _refusals = <String, String>{
    'fixture_merge_same': 'اختر نسخة أخرى غير هذه لتبقى.',
    'fixture_merge_not_found': 'إحدى المباراتين غير موجودة.',
    'fixture_merge_test': 'المباراة التجريبية لا تُدمج.',
    'fixture_merge_kept_hidden':
        'النسخة التي تبقى مخفية: أظهرها أولًا، أو ادمج هذه فيها من صفها.',
    'fixture_merge_already_merged': 'دُمجت هذه النسخة من قبل.',
    'fixture_merge_not_copies':
        'ليستا نسختين من مباراة واحدة: لا فريق مشترك بينهما خلال 12 ساعة، '
        'ولا هي المباراة نفسها مؤجّلة خلال 7 أيام في المسابقة نفسها.',
  };

  /// The stable code of every refusal of a merge.
  static const String refusedCode = 'competition.fixture_merge_refused';

  @override
  Future<Result<FixtureMergeReport>> merge({
    required FixtureRef duplicate,
    required FixtureRef kept,
    required UserId actor,
    required bool apply,
  }) async {
    final result = await _connection.query(
      _mergeSql,
      parameters: {
        'duplicate': duplicate.value,
        'kept': kept.value,
        'actor': actor.value,
        'apply': apply,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      final cause = result.error.cause;
      final String? refusal = cause is ServerException
          ? _refusals[cause.constraintName]
          : null;
      if (refusal != null) {
        return Result.err(AppError.invariant(refusedCode, refusal));
      }
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.length != 1) {
      return const Result.err(_corrupt);
    }
    final row = rows.single;
    final ints = <int>[
      for (final key in const <String>[
        'moved',
        'doubles_moved',
        'doubles_dropped',
        'both_predicted',
        'late',
        'not_participant',
      ])
        if (row[key] case final int n) n,
    ];
    final linkMoved = row['link_moved'];
    final keptHasResult = row['kept_has_result'];
    if (ints.length != 6 || linkMoved is! bool || keptHasResult is! bool) {
      return const Result.err(_corrupt);
    }
    if (apply) {
      onChanged?.call();
    }
    return Result.ok(
      FixtureMergeReport(
        moved: ints[0],
        doublesMoved: ints[1],
        doublesDropped: ints[2],
        bothPredicted: ints[3],
        late: ints[4],
        notParticipant: ints[5],
        linkMoved: linkMoved,
        keptHasResult: keptHasResult,
        applied: apply,
      ),
    );
  }

  @override
  Future<Result<List<FixtureCopy>>> copiesOf(FixtureRef fixture) async {
    final result = await _connection.query(
      _copiesSql,
      parameters: {'fixture_id': fixture.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final copies = <FixtureCopy>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final parsed = FixtureRef.tryParse(row['fixture_id']?.toString());
      final home = row['home_team'];
      final away = row['away_team'];
      final kickoffAt = row['kickoff_at'];
      final predictions = row['predictions'];
      final doubles = row['doubles'];
      if (parsed is Err<FixtureRef> ||
          home is! String ||
          away is! String ||
          kickoffAt is! DateTime ||
          predictions is! int ||
          doubles is! int) {
        return const Result.err(_corrupt);
      }
      copies.add(
        FixtureCopy(
          fixture: (parsed as Ok<FixtureRef>).value,
          homeTeam: home,
          awayTeam: away,
          kickoffAt: kickoffAt.toUtc(),
          hidden: row['hidden'] == true,
          predictions: predictions,
          doubles: doubles,
          hasResult: row['has_result'] == true,
          linked: row['linked'] == true,
          isSelf: row['is_self'] == true,
        ),
      );
    }
    return Result.ok(List<FixtureCopy>.unmodifiable(copies));
  }

  static const AppError _corrupt = AppError.transient(
    'competition.fixture_merge_corrupt',
    'A fixture merge or copies row is malformed',
  );
}
