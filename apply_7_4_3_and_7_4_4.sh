[#!/usr/bin/env bash
# تطبيق 7.4.3 (LinkFixtureToSeason use-case + port) و7.4.4 (Postgres impl + اختبارات)
# شغّله من جذر المشروع: bash apply_7_4_3_and_7_4_4.sh
# أو مرّر المسار: NUKHBAA_ROOT=/path/to/repo bash apply_7_4_3_and_7_4_4.sh
set -euo pipefail
cd "${NUKHBAA_ROOT:-/home/dev/nukhbaa-backup-1787537565}"

python3 << 'PYEOF'
import pathlib, sys

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    c = s.count(old)
    if c != 1:
        print(f"FAIL ({c} matches, expected 1): {path}", file=sys.stderr)
        sys.exit(1)
    p.write_text(s.replace(old, new, 1))
    print(f"OK edit: {path}")

def create(path, content):
    p = pathlib.Path(path)
    if p.exists():
        print(f"SKIP (already exists): {path}")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    print(f"OK create: {path}")

# ---------------------------------------------------------------------------
# 7.4.3 — Port: FixturePredictionRepository.linkFixtureToSeason
# ---------------------------------------------------------------------------
edit(
    "packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart",
    "  /// Counts how many fixtures [participantId] has already marked as their",
    """  /// Links a fixture to a season (persists a [SeasonFixture]) \u2014 the
  /// per-fixture sibling of `CompetitionRepository.saveRoundFixture`, kept
  /// here (not on `CompetitionRepository`) for the same reason
  /// [findSeasonFixture] is: it keeps that port frozen. A duplicate
  /// `(seasonId, fixture)` link surfaces as [ErrorKind.invariant]
  /// `competition.season_fixture_already_linked`.
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link);

  /// Counts how many fixtures [participantId] has already marked as their""",
)

# ---------------------------------------------------------------------------
# 7.4.3 — application.dart export
# ---------------------------------------------------------------------------
edit(
    "packages/application/lib/application.dart",
    "export 'src/competition/link_fixture_to_round.dart';",
    "export 'src/competition/link_fixture_to_round.dart';\n"
    "export 'src/competition/link_fixture_to_season.dart';",
)

# ---------------------------------------------------------------------------
# 7.4.3 — Fake repository: linkFixtureToSeason
# ---------------------------------------------------------------------------
edit(
    "packages/application/test/prediction/fake_fixture_prediction_repository.dart",
    "    return Result.ok(_seasonFixtures['${seasonId.value}|${fixture.value}']);\n  }",
    """    return Result.ok(_seasonFixtures['${seasonId.value}|${fixture.value}']);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = '${link.seasonId.value}|${link.fixture.value}';
    if (_seasonFixtures.containsKey(key)) {
      return const Result.err(
        AppError.invariant(
          'competition.season_fixture_already_linked',
          'already linked',
        ),
      );
    }
    _seasonFixtures[key] = link;
    return const Result.ok(null);
  }""",
)

# ---------------------------------------------------------------------------
# 7.4.3 — Use-case: LinkFixtureToSeason (new file)
# ---------------------------------------------------------------------------
create(
    "packages/application/lib/src/competition/link_fixture_to_season.dart",
    """import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: link a fixture to a season (Phase 7.4 \u2014 the per-fixture
/// sibling of [LinkFixtureToRound] now that a season no longer needs a
/// round to group fixtures through, Axiom 4 Amendment).
///
/// Establishes the M:N association Competition owns while keeping Football
/// Data decoupled (Axiom 3): the fixture is named by id only ([FixtureRef]),
/// never pulled into the aggregate. Admin-only.
///
/// Unlike [LinkFixtureToRound] there is no lifecycle status to gate against
/// (a season carries none) \u2014 the only precondition is that the season
/// exists. `displayOrder` is caller-supplied, exactly as
/// [LinkFixtureToRound] does it.
///
/// Never throws; returns a typed [Result].
final class LinkFixtureToSeason {
  /// Creates the use-case over its repositories.
  const LinkFixtureToSeason({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
  }) : _competitions = competitionRepository,
       _fixturePredictions = fixturePredictionRepository;

  final CompetitionRepository _competitions;
  final FixturePredictionRepository _fixturePredictions;

  /// Links [fixtureId] into [seasonId] at presentation position
  /// [displayOrder].
  Future<Result<SeasonFixture>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required int displayOrder,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }

    // The season must exist.
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }

    final linkResult = SeasonFixture.create(
      seasonId: sId,
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      displayOrder: displayOrder,
    );
    if (linkResult is Err<SeasonFixture>) {
      return Result.err(linkResult.error);
    }
    final link = (linkResult as Ok<SeasonFixture>).value;

    final saved = await _fixturePredictions.linkFixtureToSeason(link);
    return switch (saved) {
      Ok<void>() => Result.ok(link),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
""",
)

# ---------------------------------------------------------------------------
# 7.4.3 — Use-case tests (new file)
# ---------------------------------------------------------------------------
create(
    "packages/application/test/competition/link_fixture_to_season_test.dart",
    """import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _adminId = '11111111-1111-1111-1111-111111111111';
const _competitionId = '22222222-2222-2222-2222-222222222222';
const _seasonId = '33333333-3333-3333-3333-333333333333';
const _fixtureId = '44444444-4444-4444-4444-444444444444';

CompetitionSeason _season() =>
    (CompetitionSeason.create(
          id: const SeasonId(_seasonId),
          competitionId: const CompetitionId(_competitionId),
          label: 'August',
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        )
        as Ok<CompetitionSeason>)
    .value;

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixturePredictionRepository fixturePredictionRepo;
  late LinkFixtureToSeason useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    fixturePredictionRepo = FakeFixturePredictionRepository();
    useCase = LinkFixtureToSeason(
      competitionRepository: competitionRepo,
      fixturePredictionRepository: fixturePredictionRepo,
    );
  });

  test('admin links a fixture to a season', () async {
    competitionRepo.seedSeason(_season());

    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );

    final link = (result as Ok<SeasonFixture>).value;
    expect(link.seasonId, const SeasonId(_seasonId));
    expect(link.fixture, const FixtureRef(_fixtureId));
    expect(link.displayOrder, 0);
    expect(fixturePredictionRepo.count, 0);
  });

  test('non-admin is rejected', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: userPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );
    expect((result as Err<SeasonFixture>).error.kind, ErrorKind.authorization);
  });

  test('a missing season is an invariant precondition failure', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.season_not_found',
    );
  });

  test('a malformed fixture id is a validation error', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: 'x',
      displayOrder: 0,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.fixture_ref_malformed',
    );
  });

  test('a negative display order is rejected by the domain', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: -1,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.season_fixture_order_invalid',
    );
  });

  test('a duplicate link surfaces as an invariant conflict', () async {
    competitionRepo.seedSeason(_season());
    await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );

    final again = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 1,
    );
    expect(
      (again as Err<SeasonFixture>).error.code,
      'competition.season_fixture_already_linked',
    );
  });
}
""",
)

# ---------------------------------------------------------------------------
# 7.4.4 — PostgresFixturePredictionRepository: linkFixtureToSeason
# ---------------------------------------------------------------------------
edit(
    "packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart",
    """  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //""",
    """  // --------------------------------------------------------------------------
  // linkFixtureToSeason \u2014 persists a SeasonFixture link
  // --------------------------------------------------------------------------

  static const String _insertSeasonFixtureSql = '''
INSERT INTO competition.season_fixtures (season_id, fixture_id, display_order)
VALUES (@season_id, @fixture_id, @display_order)
''';

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    final result = await _connection.query(
      _insertSeasonFixtureSql,
      parameters: {
        'season_id': link.seasonId.value,
        'fixture_id': link.fixture.value,
        'display_order': link.displayOrder,
      },
    );
    return _asVoid(result);
  }

  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //""",
)

edit(
    "packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart",
    """      case 'fixture_predictions_participant_id_fkey':
        return const AppError.invariant(
          'prediction.not_a_participant',
          'Participant not found',
        );
    }""",
    """      case 'fixture_predictions_participant_id_fkey':
        return const AppError.invariant(
          'prediction.not_a_participant',
          'Participant not found',
        );
      case 'season_fixtures_pkey':
        return const AppError.invariant(
          'competition.season_fixture_already_linked',
          'This fixture is already linked to the season',
        );
    }""",
)

# ---------------------------------------------------------------------------
# 7.4.4 — Postgres repository tests
# ---------------------------------------------------------------------------
edit(
    "packages/infrastructure/test/prediction/postgres_fixture_prediction_repository_test.dart",
    "    test('countDoublesOnDay maps the count column', () async {",
    """    test('linkFixtureToSeason binds every field', () async {
      final connection = _FakeConnection([
        const Result.ok(<Map<String, dynamic>>[]),
      ]);
      final repo = PostgresFixturePredictionRepository(connection);
      final link =
          (SeasonFixture.create(
                    seasonId: const SeasonId(_seasonId),
                    fixture: const FixtureRef(_fixtureA),
                    displayOrder: 2,
                  )
                  as Ok<SeasonFixture>)
              .value;

      final result = await repo.linkFixtureToSeason(link);

      expect(result, isA<Ok<void>>());
      expect(connection.parameters.single['season_id'], _seasonId);
      expect(connection.parameters.single['fixture_id'], _fixtureA);
      expect(connection.parameters.single['display_order'], 2);
    });

    test('linkFixtureToSeason passes a transient error through verbatim', () async {
      const error = AppError.transient('boom', 'db down');
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.err(error)]),
      );
      final link =
          (SeasonFixture.create(
                    seasonId: const SeasonId(_seasonId),
                    fixture: const FixtureRef(_fixtureA),
                    displayOrder: 0,
                  )
                  as Ok<SeasonFixture>)
              .value;

      final result = await repo.linkFixtureToSeason(link);

      expect((result as Err<void>).error.code, 'boom');
    });

    test('countDoublesOnDay maps the count column', () async {""",
)

print("DONE: 7.4.3 + 7.4.4 applied")
PYEOF
]
