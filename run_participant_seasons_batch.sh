cd /home/dev/nukhbaa-backup-1787537565

cat > /tmp/apply_batch01.py << 'PYEOF'
#!/usr/bin/env python3
"""Applies the participant-active-seasons read-layer batch (isolated read
layer, no use-case/route/mobile wiring yet). Every edit matches an exact
anchor string exactly once; aborts loudly otherwise — no blind replace."""
import sys

ROOT = "."


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def replace_once(path, old, new, label):
    content = read(path)
    count = content.count(old)
    if count != 1:
        print(f"ABORT [{label}]: expected exactly 1 match in {path}, found {count}")
        sys.exit(1)
    content = content.replace(old, new, 1)
    write(path, content)
    print(f"OK [{label}]: {path}")


def create(path, content, label):
    write(path, content)
    print(f"OK [{label}]: created {path}")


# ---------------------------------------------------------------------------
# 1) New domain entity
# ---------------------------------------------------------------------------
create(
    f"{ROOT}/packages/domain/lib/src/competition/participant_season_feed_entry.dart",
    '''import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/competition/season_id.dart';

/// One season a user is **actively** participating in, right now, joined with
/// its owning competition's display facts — the row shape backing a "my
/// seasons" feed read (the participant-scoped analogue of
/// [OpenRoundFeedEntry]'s platform-wide round feed).
///
/// A cross-aggregate *projection*, not a member of the `Participant`,
/// `CompetitionSeason`, or `Competition` aggregate: it exists solely to carry
/// exactly what a "which seasons am I actively in, currently" read needs out
/// of a single joined query, so the client can then fan out to the
/// already-existing `BrowseSeasonFixtures` read (`GET /seasons/{id}/fixtures`)
/// per season. It never crosses back into a write path.
final class ParticipantSeasonFeedEntry {
  /// Creates a feed entry.
  const ParticipantSeasonFeedEntry({
    required this.competitionId,
    required this.competitionName,
    required this.seasonId,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
  });

  /// The owning competition's identity.
  final CompetitionId competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The season's identity — the key the client uses to fetch its fixtures.
  final SeasonId seasonId;

  /// The season's display label.
  final String seasonLabel;

  /// UTC instant the season's calendar window opens (inclusive).
  final DateTime startAt;

  /// UTC instant the season's calendar window closes (exclusive).
  final DateTime endAt;

  @override
  bool operator ==(Object other) =>
      other is ParticipantSeasonFeedEntry &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.seasonId == seasonId &&
      other.seasonLabel == seasonLabel &&
      other.startAt == startAt &&
      other.endAt == endAt;

  @override
  int get hashCode => Object.hash(
    competitionId,
    competitionName,
    seasonId,
    seasonLabel,
    startAt,
    endAt,
  );

  @override
  String toString() =>
      'ParticipantSeasonFeedEntry(competition: ${competitionId.value} '
      '"$competitionName", season: ${seasonId.value} "$seasonLabel", '
      '$startAt - $endAt)';
}
''',
    "domain entity",
)

# ---------------------------------------------------------------------------
# 2) Domain barrel export
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/packages/domain/lib/domain.dart",
    "export 'src/competition/participant_id.dart';\n"
    "export 'src/competition/participant_status.dart';\n",
    "export 'src/competition/participant_id.dart';\n"
    "export 'src/competition/participant_season_feed_entry.dart';\n"
    "export 'src/competition/participant_status.dart';\n",
    "domain barrel export",
)

# ---------------------------------------------------------------------------
# 3) Port interface method
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/packages/application/lib/src/competition/ports/competition_repository.dart",
    """  /// Lists the ids of every round [fixture] is linked to (a fixture may
  /// belong to more than one round/competition — Axiom 3). Ordered by round
  /// id for a stable, deterministic result. A fixture linked to no round
  /// yields `Ok(<empty list>)`, never an error.
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture);
}""",
    """  /// Lists the ids of every round [fixture] is linked to (a fixture may
  /// belong to more than one round/competition — Axiom 3). Ordered by round
  /// id for a stable, deterministic result. A fixture linked to no round
  /// yields `Ok(<empty list>)`, never an error.
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture);

  // ---------------------------------------------------------------------------
  // Participant-scoped season feed (isolated read layer — first step toward
  // a "my seasons" mobile read; the client fans out to the existing
  // `listSeasonRounds`-analogue `BrowseSeasonFixtures` read per season it
  // returns). Additive, read-only; no use-case/route/mobile wiring lands with
  // this method.
  // ---------------------------------------------------------------------------

  /// Lists every season [userId] is an **active** ([ParticipantStatus.active])
  /// participant in, whose calendar window currently covers [nowUtc]
  /// ([CompetitionSeason.isCurrentAt]), joined with the owning competition's
  /// display name — the row shape a "my seasons" feed needs in one query.
  ///
  /// Ordered by competition name (then id, tie-break), then season label
  /// (then id) — mirrors [listOpenRoundsFeed]'s grouping/order contract. A
  /// user with no active participation currently covered by any season's
  /// window yields `Ok(<empty list>)`, never an error — a legitimate "not in
  /// any season right now" outcome (e.g. a brand-new user who has not yet
  /// made a first prediction, since `FixturePredictionController` auto-joins
  /// only on that first successful submission).
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({required UserId userId, required DateTime nowUtc});
}""",
    "port interface method",
)

# ---------------------------------------------------------------------------
# 4) Postgres implementation
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/packages/infrastructure/lib/src/competition/postgres_competition_repository.dart",
    """  // --------------------------------------------------------------------------
  // Shared helpers
  // --------------------------------------------------------------------------""",
    """  // --------------------------------------------------------------------------
  // Participant-scoped season feed (isolated read layer)
  // --------------------------------------------------------------------------

  static const String _listActiveParticipantSeasonsSql = \'\'\'
SELECT c.id AS competition_id, c.name AS competition_name,
       s.id AS season_id, s.label AS season_label,
       s.start_at, s.end_at
FROM competition.participants p
JOIN competition.seasons s ON s.id = p.season_id
JOIN competition.competitions c ON c.id = s.competition_id
WHERE p.user_id = @user_id
  AND p.status = \'active\'::competition.participant_status
  AND s.start_at <= @now
  AND s.end_at > @now
ORDER BY c.name ASC, c.id ASC, s.label ASC, s.id ASC
\'\'\';

  @override
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  }) async {
    final result = await _connection.query(
      _listActiveParticipantSeasonsSql,
      parameters: {'user_id': userId.value, 'now': nowUtc},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(
        value,
        _mapParticipantSeasonFeedEntry,
      ),
    };
  }

  Result<ParticipantSeasonFeedEntry> _mapParticipantSeasonFeedEntry(
    Map<String, dynamic> row,
  ) {
    final competitionIdResult = CompetitionId.tryParse(
      row['competition_id']?.toString(),
    );
    final seasonIdResult = SeasonId.tryParse(row['season_id']?.toString());
    final competitionName = row['competition_name'];
    final seasonLabel = row['season_label'];
    final startAt = _readUtcTimestamp(row['start_at']);
    final endAt = _readUtcTimestamp(row['end_at']);

    if (competitionIdResult is Err<CompetitionId>) {
      return Result.err(
        _corrupt(
          'participants',
          'competition_id',
          competitionIdResult.error.message,
        ),
      );
    }
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(
        _corrupt('participants', 'season_id', seasonIdResult.error.message),
      );
    }
    if (competitionName is! String) {
      return Result.err(
        _corrupt('participants', 'competition_name', 'not a string'),
      );
    }
    if (seasonLabel is! String) {
      return Result.err(
        _corrupt('participants', 'season_label', 'not a string'),
      );
    }
    if (startAt == null) {
      return Result.err(
        _corrupt('participants', 'start_at', 'not a timestamp'),
      );
    }
    if (endAt == null) {
      return Result.err(_corrupt('participants', 'end_at', 'not a timestamp'));
    }

    return Result.ok(
      ParticipantSeasonFeedEntry(
        competitionId: (competitionIdResult as Ok<CompetitionId>).value,
        competitionName: competitionName,
        seasonId: (seasonIdResult as Ok<SeasonId>).value,
        seasonLabel: seasonLabel,
        startAt: startAt,
        endAt: endAt,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Shared helpers
  // --------------------------------------------------------------------------""",
    "postgres implementation",
)

# ---------------------------------------------------------------------------
# 5) FakeCompetitionRepository (application/test)
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/packages/application/test/competition/fake_competition_repository.dart",
    """  @override
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final roundIds = {
      for (final link in _roundFixtures)
        if (link.fixture.value == fixture.value) link.roundId,
    }.toList()..sort((a, b) => a.value.compareTo(b.value));
    return Result.ok(roundIds);
  }
}""",
    """  @override
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final roundIds = {
      for (final link in _roundFixtures)
        if (link.fixture.value == fixture.value) link.roundId,
    }.toList()..sort((a, b) => a.value.compareTo(b.value));
    return Result.ok(roundIds);
  }

  // ---------------------------------------------------------------------------
  // Participant-scoped season feed (isolated read layer): real in-memory read
  // over the same backing stores, mirroring the Postgres adapter's
  // join/filter/order semantics.
  // ---------------------------------------------------------------------------

  @override
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  }) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final entries =
        [
          for (final p in _participants.values)
            if (p.userId.value == userId.value &&
                p.status == ParticipantStatus.active)
              if (_seasons[p.seasonId.value] case final season?)
                if (season.isCurrentAt(nowUtc))
                  if (_competitions[season.competitionId.value]
                      case final competition?)
                    (competition: competition, season: season),
        ]..sort((a, b) {
          final byName = a.competition.name.compareTo(b.competition.name);
          if (byName != 0) return byName;
          final byCompetitionId = a.competition.id.value.compareTo(
            b.competition.id.value,
          );
          if (byCompetitionId != 0) return byCompetitionId;
          final byLabel = a.season.label.compareTo(b.season.label);
          return byLabel != 0
              ? byLabel
              : a.season.id.value.compareTo(b.season.id.value);
        });
    return Result.ok([
      for (final e in entries)
        ParticipantSeasonFeedEntry(
          competitionId: e.competition.id,
          competitionName: e.competition.name,
          seasonId: e.season.id,
          seasonLabel: e.season.label,
          startAt: e.season.startAt,
          endAt: e.season.endAt,
        ),
    ]);
  }
}""",
    "fake repository",
)

# ---------------------------------------------------------------------------
# 6) InMemoryCompetitionRepository (server test harness)
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/apps/server/test/routes/competition_route_harness.dart",
    """  @override
  Future<Result<List<RoundFixture>>> listFixturesForRounds(
    List<RoundId> roundIds,
  ) async {
    if (roundIds.isEmpty) return const Result.ok(<RoundFixture>[]);
    final wanted = {for (final id in roundIds) id.value};
    final matched =
        [
          for (final link in links)
            if (wanted.contains(link.roundId.value)) link,
        ]..sort((a, b) {
          final byRound = a.roundId.value.compareTo(b.roundId.value);
          if (byRound != 0) return byRound;
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          return byOrder != 0
              ? byOrder
              : a.fixture.value.compareTo(b.fixture.value);
        });
    return Result.ok(matched);
  }
}""",
    """  @override
  Future<Result<List<RoundFixture>>> listFixturesForRounds(
    List<RoundId> roundIds,
  ) async {
    if (roundIds.isEmpty) return const Result.ok(<RoundFixture>[]);
    final wanted = {for (final id in roundIds) id.value};
    final matched =
        [
          for (final link in links)
            if (wanted.contains(link.roundId.value)) link,
        ]..sort((a, b) {
          final byRound = a.roundId.value.compareTo(b.roundId.value);
          if (byRound != 0) return byRound;
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          return byOrder != 0
              ? byOrder
              : a.fixture.value.compareTo(b.fixture.value);
        });
    return Result.ok(matched);
  }

  @override
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  }) async {
    final entries =
        [
          for (final p in participants)
            if (p.userId.value == userId.value &&
                p.status == ParticipantStatus.active)
              if (seasons[p.seasonId.value] case final season?)
                if (season.isCurrentAt(nowUtc))
                  if (competitions[season.competitionId.value]
                      case final competition?)
                    (competition: competition, season: season),
        ]..sort((a, b) {
          final byName = a.competition.name.compareTo(b.competition.name);
          if (byName != 0) return byName;
          final byCompetitionId = a.competition.id.value.compareTo(
            b.competition.id.value,
          );
          if (byCompetitionId != 0) return byCompetitionId;
          final byLabel = a.season.label.compareTo(b.season.label);
          return byLabel != 0
              ? byLabel
              : a.season.id.value.compareTo(b.season.id.value);
        });
    return Result.ok([
      for (final e in entries)
        ParticipantSeasonFeedEntry(
          competitionId: e.competition.id,
          competitionName: e.competition.name,
          seasonId: e.season.id,
          seasonLabel: e.season.label,
          startAt: e.season.startAt,
          endAt: e.season.endAt,
        ),
    ]);
  }
}""",
    "in-memory repository (server harness)",
)

# ---------------------------------------------------------------------------
# 7) composition_root.dart stub
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/apps/server/lib/composition/composition_root.dart",
    """  @override
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture) =>
      _unwired();
}""",
    """  @override
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture) =>
      _unwired();

  @override
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  }) => _unwired();
}""",
    "composition_root stub",
)

# ---------------------------------------------------------------------------
# 8) New Postgres unit tests
# ---------------------------------------------------------------------------
replace_once(
    f"{ROOT}/packages/infrastructure/test/competition/postgres_competition_repository_test.dart",
    """    test('a transient query error is propagated verbatim', () async {
      final repo = PostgresCompetitionRepository(_fails());

      final result = await repo.listFixturesForRounds([_rId]);

      final err = (result as Err<List<RoundFixture>>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, 'db.query_failed');
    });
  });
}""",
    """    test('a transient query error is propagated verbatim', () async {
      final repo = PostgresCompetitionRepository(_fails());

      final result = await repo.listFixturesForRounds([_rId]);

      final err = (result as Err<List<RoundFixture>>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, 'db.query_failed');
    });
  });

  group('listActiveParticipantSeasons', () {
    test(
      'maps every row to a ParticipantSeasonFeedEntry and binds user_id + now',
      () async {
        final now = DateTime.utc(2026, 8, 15);
        final conn = _rows([
          {
            'competition_id': _competitionId,
            'competition_name': 'Premier League',
            'season_id': _seasonId,
            'season_label': '08/2026',
            'start_at': DateTime.utc(2026, 8, 1),
            'end_at': DateTime.utc(2026, 9, 1),
          },
        ]);
        final repo = PostgresCompetitionRepository(conn);

        final result = await repo.listActiveParticipantSeasons(
          userId: _uId,
          nowUtc: now,
        );

        final list = (result as Ok<List<ParticipantSeasonFeedEntry>>).value;
        expect(list, hasLength(1));
        expect(list.single.competitionId.value, _competitionId);
        expect(list.single.competitionName, 'Premier League');
        expect(list.single.seasonId.value, _seasonId);
        expect(list.single.seasonLabel, '08/2026');
        expect(conn.lastParameters, {'user_id': _userId, 'now': now});
      },
    );

    test(
      'no active participation covered by any season now is Ok(<empty list>)',
      () async {
        final repo = PostgresCompetitionRepository(_rows(const []));

        final result = await repo.listActiveParticipantSeasons(
          userId: _uId,
          nowUtc: DateTime.utc(2026, 8, 15),
        );

        expect(
          (result as Ok<List<ParticipantSeasonFeedEntry>>).value,
          isEmpty,
        );
      },
    );

    test('a corrupt season_label maps to transient row_corrupt', () async {
      final conn = _rows([
        {
          'competition_id': _competitionId,
          'competition_name': 'Premier League',
          'season_id': _seasonId,
          'season_label': 42, // not a string
          'start_at': DateTime.utc(2026, 8, 1),
          'end_at': DateTime.utc(2026, 9, 1),
        },
      ]);
      final repo = PostgresCompetitionRepository(conn);

      final result = await repo.listActiveParticipantSeasons(
        userId: _uId,
        nowUtc: DateTime.utc(2026, 8, 15),
      );

      final err = (result as Err<List<ParticipantSeasonFeedEntry>>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, 'competition.row_corrupt');
    });

    test('a transient query error is propagated verbatim', () async {
      final repo = PostgresCompetitionRepository(_fails());

      final result = await repo.listActiveParticipantSeasons(
        userId: _uId,
        nowUtc: DateTime.utc(2026, 8, 15),
      );

      final err = (result as Err<List<ParticipantSeasonFeedEntry>>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, 'db.query_failed');
    });
  });
}""",
    "postgres unit tests",
)

print("ALL PATCHES APPLIED")
PYEOF

python3 /tmp/apply_batch01.py
PATCH_STATUS=$?

if [ $PATCH_STATUS -ne 0 ]; then
  echo "PATCH FAILED — لا تحقق ولا commit. أرسل لي مخرجات هذا السطر كاملة."
  exit 1
fi

flutter analyze packages/domain packages/application packages/infrastructure apps/server > /tmp/analyze_out.txt 2>&1
ANALYZE_STATUS=$?
cat /tmp/analyze_out.txt

flutter test packages/domain packages/application packages/infrastructure apps/server > /tmp/test_out.txt 2>&1
TEST_STATUS=$?
cat /tmp/test_out.txt

TIME_NOW="$(date +%H:%M)"
if [ $ANALYZE_STATUS -eq 0 ] && [ $TEST_STATUS -eq 0 ]; then
  RESULT_AR="نجح"
else
  RESULT_AR="فشل"
fi

cat >> docs/checkpoints/session-log.md << EOF
- [${TIME_NOW}] إصلاح: listActiveParticipantSeasons (طبقة قراءة معزولة، Postgres+Fake+InMemory+composition_root+اختبارات) | ملفات: packages/domain/lib/src/competition/participant_season_feed_entry.dart, packages/domain/lib/domain.dart, packages/application/lib/src/competition/ports/competition_repository.dart, packages/infrastructure/lib/src/competition/postgres_competition_repository.dart, packages/application/test/competition/fake_competition_repository.dart, apps/server/test/routes/competition_route_harness.dart, apps/server/lib/composition/composition_root.dart, packages/infrastructure/test/competition/postgres_competition_repository_test.dart | اختبار: ${RESULT_AR}
EOF

if [ "$RESULT_AR" = "نجح" ]; then
  git add -A
  git commit -m "competition: add CompetitionRepository.listActiveParticipantSeasons (isolated read layer)

- Port: new listActiveParticipantSeasons({userId, nowUtc}) on CompetitionRepository.
- New domain entity ParticipantSeasonFeedEntry (competition+season display
  projection), mirroring OpenRoundFeedEntry's role.
- PostgresCompetitionRepository: implementation joining
  participants -> seasons -> competitions on user_id + active status +
  season window covering nowUtc.
- FakeCompetitionRepository + InMemoryCompetitionRepository (server test
  harness): matching in-memory implementations, same filter/order semantics.
- composition_root.dart: _UnwiredCompetitionRepository stub updated
  (interface compliance only, no live wiring yet).
- New unit tests in postgres_competition_repository_test.dart (mapping,
  empty result, corrupt row, transient error, parameter binding).

No use-case, no route, no live composition-root wiring, no mobile UI yet —
isolated read-layer batch only, same pattern as the earlier
FixturePredictionRepository.listByUser batch."
  git log --oneline -1
  echo "تم الـcommit محليًا. لا يوجد push — بانتظار إذنك الصريح هنا في هذه المحادثة تحديدًا قبل أي git push."
else
  echo "التحقق فشل (analyze أو test) — راجع /tmp/analyze_out.txt و /tmp/test_out.txt. لا commit تم."
fi
