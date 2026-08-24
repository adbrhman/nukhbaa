import pathlib

lib_path = pathlib.Path("packages/infrastructure/lib/src/scoring/postgres_score_repository.dart")
test_path = pathlib.Path("packages/infrastructure/test/scoring/postgres_scoring_repositories_test.dart")

lib_old = '''  // ON CONFLICT (round_id, participant_id) refreshes the derived total and the
  // ruleset version in place — the idempotent-replay backstop for re-scoring
  // (Axiom 4). `scored_at` is refreshed to the write instant.
  static const String _upsertRoundScoreSql = \'\'\'
INSERT INTO scoring.round_scores
  (round_id, participant_id, ruleset_version, total_points, scored_at)
VALUES (@round_id, @participant_id, @ruleset_version, @total_points, now())
ON CONFLICT (round_id, participant_id) DO UPDATE SET
  ruleset_version = EXCLUDED.ruleset_version,
  total_points    = EXCLUDED.total_points,
  scored_at       = EXCLUDED.scored_at
\'\'\';

  static const String _deleteFixturesSql = \'\'\'
DELETE FROM scoring.round_score_fixtures
WHERE round_id = @round_id AND participant_id = @participant_id
\'\'\';

  static const String _insertFixtureSql = \'\'\'
INSERT INTO scoring.round_score_fixtures
  (round_id, participant_id, fixture_id, grade, points, display_order)
VALUES (@round_id, @participant_id, @fixture_id, @grade, @points, @display_order)
\'\'\';

  @override
  Future<Result<void>> saveRoundScores(List<RoundScore> scores) {
    if (scores.isEmpty) {
      // Nothing to persist (a round with no predictions is still validly
      // "scored"); avoid opening a transaction for a no-op.
      return Future.value(const Result.ok(null));
    }
    // Every parent + every child, in ONE transaction: a failure on any statement
    // rolls the whole round's scoring back, so the competitive record is never
    // left half-written (Axiom 5).
    return _connection.runInTransaction((tx) async {
      for (final score in scores) {
        final parent = await tx.query(
          _upsertRoundScoreSql,
          parameters: {
            \'round_id\': score.roundId.value,
            \'participant_id\': score.participantId.value,
            \'ruleset_version\': score.rulesetVersion,
            \'total_points\': score.totalPoints,
          },
        );
        final parentResult = _asVoid(parent);
        if (parentResult is Err<void>) {
          return parentResult;
        }

        // Replace the child breakdown in place (idempotent re-score): drop the
        // old rows, reinsert in the prediction\'s fixture order.
        final deleted = await tx.query(
          _deleteFixturesSql,
          parameters: {
            \'round_id\': score.roundId.value,
            \'participant_id\': score.participantId.value,
          },
        );
        final deleteResult = _asVoid(deleted);
        if (deleteResult is Err<void>) {
          return deleteResult;
        }

        for (var order = 0; order < score.fixtureResults.length; order++) {
          final fixtureResult = score.fixtureResults[order];
          final inserted = await tx.query(
            _insertFixtureSql,
            parameters: {
              \'round_id\': score.roundId.value,
              \'participant_id\': score.participantId.value,
              \'fixture_id\': fixtureResult.fixture.value,
              \'grade\': fixtureResult.grade.wireValue,
              \'points\': fixtureResult.points,
              \'display_order\': order,
            },
          );
          final childResult = _asVoid(inserted);
          if (childResult is Err<void>) {
            return childResult;
          }
        }
      }
      return const Result.ok(null);
    });
  }'''

lib_new = '''  // Batched via `unnest` (one round-trip for all parents, one for all child
  // deletes, one for all child inserts — instead of the previous per-score,
  // per-fixture sequential loop). ON CONFLICT (round_id, participant_id)
  // refreshes the derived total and the ruleset version in place — the
  // idempotent-replay backstop for re-scoring (Axiom 4). `scored_at` is
  // refreshed to the write instant.
  static const String _upsertRoundScoresSql = \'\'\'
INSERT INTO scoring.round_scores
  (round_id, participant_id, ruleset_version, total_points, scored_at)
SELECT round_id, participant_id, ruleset_version, total_points, now()
FROM unnest(
  @round_ids::uuid[],
  @participant_ids::uuid[],
  @ruleset_versions::int[],
  @total_points::int[]
) AS t(round_id, participant_id, ruleset_version, total_points)
ON CONFLICT (round_id, participant_id) DO UPDATE SET
  ruleset_version = EXCLUDED.ruleset_version,
  total_points    = EXCLUDED.total_points,
  scored_at       = EXCLUDED.scored_at
\'\'\';

  // One delete for every (round, participant) pair being re-scored this call,
  // instead of one DELETE per score.
  static const String _deleteFixturesSql = \'\'\'
DELETE FROM scoring.round_score_fixtures
WHERE (round_id, participant_id) IN (
  SELECT round_id, participant_id
  FROM unnest(@round_ids::uuid[], @participant_ids::uuid[])
    AS t(round_id, participant_id)
)
\'\'\';

  // One insert for every fixture row across every score being persisted,
  // instead of one INSERT per (score, fixture) pair.
  static const String _insertFixturesSql = \'\'\'
INSERT INTO scoring.round_score_fixtures
  (round_id, participant_id, fixture_id, grade, points, display_order)
SELECT round_id, participant_id, fixture_id, grade, points, display_order
FROM unnest(
  @round_ids::uuid[],
  @participant_ids::uuid[],
  @fixture_ids::uuid[],
  @grades::text[],
  @points::int[],
  @display_orders::int[]
) AS t(round_id, participant_id, fixture_id, grade, points, display_order)
\'\'\';

  @override
  Future<Result<void>> saveRoundScores(List<RoundScore> scores) {
    if (scores.isEmpty) {
      // Nothing to persist (a round with no predictions is still validly
      // "scored"); avoid opening a transaction for a no-op.
      return Future.value(const Result.ok(null));
    }

    // Flatten every score\'s parent row into parallel arrays for one batched
    // upsert.
    final parentRoundIds = <String>[];
    final parentParticipantIds = <String>[];
    final rulesetVersions = <int>[];
    final totalPoints = <int>[];

    // Flatten every score\'s fixture breakdown into parallel arrays for one
    // batched delete (round/participant pairs) and one batched insert.
    final childRoundIds = <String>[];
    final childParticipantIds = <String>[];
    final fixtureIds = <String>[];
    final grades = <String>[];
    final fixturePoints = <int>[];
    final displayOrders = <int>[];

    for (final score in scores) {
      parentRoundIds.add(score.roundId.value);
      parentParticipantIds.add(score.participantId.value);
      rulesetVersions.add(score.rulesetVersion);
      totalPoints.add(score.totalPoints);

      for (var order = 0; order < score.fixtureResults.length; order++) {
        final fixtureResult = score.fixtureResults[order];
        childRoundIds.add(score.roundId.value);
        childParticipantIds.add(score.participantId.value);
        fixtureIds.add(fixtureResult.fixture.value);
        grades.add(fixtureResult.grade.wireValue);
        fixturePoints.add(fixtureResult.points);
        displayOrders.add(order);
      }
    }

    // All three batched statements in ONE transaction: a failure on any
    // statement rolls the whole round\'s scoring back, so the competitive
    // record is never left half-written (Axiom 5).
    return _connection.runInTransaction((tx) async {
      final parent = await tx.query(
        _upsertRoundScoresSql,
        parameters: {
          \'round_ids\': parentRoundIds,
          \'participant_ids\': parentParticipantIds,
          \'ruleset_versions\': rulesetVersions,
          \'total_points\': totalPoints,
        },
      );
      final parentResult = _asVoid(parent);
      if (parentResult is Err<void>) {
        return parentResult;
      }

      // Replace every score\'s child breakdown in place (idempotent
      // re-score): drop the old rows for every (round, participant) pair
      // being written this call, then bulk-reinsert in the prediction\'s
      // fixture order.
      final deleted = await tx.query(
        _deleteFixturesSql,
        parameters: {
          \'round_ids\': parentRoundIds,
          \'participant_ids\': parentParticipantIds,
        },
      );
      final deleteResult = _asVoid(deleted);
      if (deleteResult is Err<void>) {
        return deleteResult;
      }

      final inserted = await tx.query(
        _insertFixturesSql,
        parameters: {
          \'round_ids\': childRoundIds,
          \'participant_ids\': childParticipantIds,
          \'fixture_ids\': fixtureIds,
          \'grades\': grades,
          \'points\': fixturePoints,
          \'display_orders\': displayOrders,
        },
      );
      final childResult = _asVoid(inserted);
      if (childResult is Err<void>) {
        return childResult;
      }

      return const Result.ok(null);
    });
  }'''

test_old = '''    test(
      \'saveRoundScores writes parent upsert + child delete + ordered inserts\',
      () async {
        // One participant, two fixtures: expect 1 upsert + 1 delete + 2 inserts.
        final conn = _script(const [
          Result.ok(<Map<String, dynamic>>[]), // upsert parent
          Result.ok(<Map<String, dynamic>>[]), // delete children
          Result.ok(<Map<String, dynamic>>[]), // insert fixture A
          Result.ok(<Map<String, dynamic>>[]), // insert fixture B
        ]);
        final repo = PostgresScoreRepository(conn);

        final result = await repo.saveRoundScores([
          _roundScore(
            fixtures: [
              _graded(_fixtureA, FixtureScoreGrade.exactScoreline, 5),
              _graded(_fixtureB, FixtureScoreGrade.correctOutcome, 2),
            ],
          ),
        ]);

        expect(result, isA<Ok<void>>());
        expect(conn.sqls.length, 4);
        expect(conn.sqls[0], contains(\'INSERT INTO scoring.round_scores\'));
        expect(
          conn.sqls[0],
          contains(\'ON CONFLICT (round_id, participant_id)\'),
        );
        expect(
          conn.sqls[1],
          contains(\'DELETE FROM scoring.round_score_fixtures\'),
        );
        expect(
          conn.sqls[2],
          contains(\'INSERT INTO scoring.round_score_fixtures\'),
        );
        // Parent carries the derived total (5 + 2).
        expect(conn.parameters[0][\'total_points\'], 7);
        expect(conn.parameters[0][\'ruleset_version\'], 1);
        // Children inserted in list (prediction) order with display_order 0,1.
        expect(conn.parameters[2][\'fixture_id\'], _fixtureA);
        expect(conn.parameters[2][\'grade\'], \'exact_scoreline\');
        expect(conn.parameters[2][\'points\'], 5);
        expect(conn.parameters[2][\'display_order\'], 0);
        expect(conn.parameters[3][\'fixture_id\'], _fixtureB);
        expect(conn.parameters[3][\'grade\'], \'correct_outcome\');
        expect(conn.parameters[3][\'display_order\'], 1);
      },
    );

    test(
      \'saveRoundScores returns the mid-transaction failure verbatim\',
      () async {
        // Parent upsert ok, then the child delete fails: the whole batch rolls
        // back (modelled by the fake returning the Err verbatim).
        final conn = _script(const [
          Result.ok(<Map<String, dynamic>>[]), // upsert parent
          Result.err(
            AppError.transient(\'db.query_failed\', \'Database query failed\'),
          ), // delete children fails
        ]);
        final repo = PostgresScoreRepository(conn);

        final result = await repo.saveRoundScores([
          _roundScore(
            fixtures: [_graded(_fixtureA, FixtureScoreGrade.incorrect, 0)],
          ),
        ]);

        expect(result, isA<Err<void>>());
        expect((result as Err<void>).error.kind, ErrorKind.transient);
      },
    );'''

test_new = '''    test(
      \'saveRoundScores batches parent upsert + child delete + child insert \'
      \'into exactly 3 queries regardless of participant/fixture count\',
      () async {
        // One participant, two fixtures: still just 1 upsert + 1 delete + 1
        // batched insert (not one insert per fixture) — the whole point of
        // batching via `unnest` instead of a per-row loop.
        final conn = _script(const [
          Result.ok(<Map<String, dynamic>>[]), // upsert parents (batched)
          Result.ok(<Map<String, dynamic>>[]), // delete children (batched)
          Result.ok(<Map<String, dynamic>>[]), // insert children (batched)
        ]);
        final repo = PostgresScoreRepository(conn);

        final result = await repo.saveRoundScores([
          _roundScore(
            fixtures: [
              _graded(_fixtureA, FixtureScoreGrade.exactScoreline, 5),
              _graded(_fixtureB, FixtureScoreGrade.correctOutcome, 2),
            ],
          ),
        ]);

        expect(result, isA<Ok<void>>());
        expect(conn.sqls.length, 3);
        expect(conn.sqls[0], contains(\'INSERT INTO scoring.round_scores\'));
        expect(conn.sqls[0], contains(\'unnest(\'));
        expect(
          conn.sqls[0],
          contains(\'ON CONFLICT (round_id, participant_id)\'),
        );
        expect(
          conn.sqls[1],
          contains(\'DELETE FROM scoring.round_score_fixtures\'),
        );
        expect(conn.sqls[1], contains(\'unnest(\'));
        expect(
          conn.sqls[2],
          contains(\'INSERT INTO scoring.round_score_fixtures\'),
        );
        expect(conn.sqls[2], contains(\'unnest(\'));
        // Parent arrays carry the derived total (5 + 2) for the one score.
        expect(conn.parameters[0][\'total_points\'], [7]);
        expect(conn.parameters[0][\'ruleset_versions\'], [1]);
        // Children flattened in list (prediction) order with display_order
        // 0,1 as parallel arrays.
        expect(conn.parameters[2][\'fixture_ids\'], [_fixtureA, _fixtureB]);
        expect(
          conn.parameters[2][\'grades\'],
          [\'exact_scoreline\', \'correct_outcome\'],
        );
        expect(conn.parameters[2][\'points\'], [5, 2]);
        expect(conn.parameters[2][\'display_orders\'], [0, 1]);
      },
    );

    test(
      \'saveRoundScores returns the mid-transaction failure verbatim\',
      () async {
        // Parent upsert ok, then the child delete fails: the whole batch rolls
        // back (modelled by the fake returning the Err verbatim).
        final conn = _script(const [
          Result.ok(<Map<String, dynamic>>[]), // upsert parents
          Result.err(
            AppError.transient(\'db.query_failed\', \'Database query failed\'),
          ), // delete children fails
        ]);
        final repo = PostgresScoreRepository(conn);

        final result = await repo.saveRoundScores([
          _roundScore(
            fixtures: [_graded(_fixtureA, FixtureScoreGrade.incorrect, 0)],
          ),
        ]);

        expect(result, isA<Err<void>>());
        expect((result as Err<void>).error.kind, ErrorKind.transient);
      },
    );'''

def patch(path, old, new, label):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            print(f"[skip] {label}: already patched")
            return
        raise SystemExit(f"[FAIL] {label}: old block not found — file differs from expected, aborting")
    if text.count(old) != 1:
        raise SystemExit(f"[FAIL] {label}: old block matches {text.count(old)} times, expected 1 — aborting")
    path.write_text(text.replace(old, new), encoding="utf-8")
    print(f"[ok] {label}: patched")

patch(lib_path, lib_old, lib_new, "lib/postgres_score_repository.dart")
patch(test_path, test_old, test_new, "test/postgres_scoring_repositories_test.dart")
print("Done.")
