import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/index.dart' as fixtures_route;
import 'competition_route_harness.dart';

/// Route tests for the new `POST /seasons/{id}/fixtures` command branch
/// (Phase 7.4.5, Axiom 4 Amendment) added beside the untouched `GET` browse
/// read in the same file.
///
/// Mirrors `rounds_browse_test.dart` / `fixture_prediction_scoring_test.dart`:
/// real wiring (`context.read<Future<CompositionRoot>>()` ->
/// `root.linkFixtureToSeason()`) over the harness's
/// [InMemoryCompetitionRepository] (season resolution) plus a local minimal
/// [FixturePredictionRepository] fake (season-fixture link storage). NOT a
/// substitute for the use-case's own tests (application package) or the
/// Postgres adapter's own tests (infrastructure package).
void main() {
  const seasonId = kSeasonId;
  const fixtureId = kFixtureId;

  CompetitionSeason season() =>
      (CompetitionSeason.create(
                id: (SeasonId.tryParse(seasonId) as Ok<SeasonId>).value,
                competitionId: const CompetitionId(kCompetitionId),
                label: 'August',
                startAt: DateTime.utc(2026, 8, 1),
                endAt: DateTime.utc(2026, 9, 1),
              )
              as Ok<CompetitionSeason>)
          .value;

  ({
    CompositionRoot root,
    InMemoryCompetitionRepository comp,
    _InMemoryFixturePredictionRepository preds,
  })
  rootWith({bool seasonExists = true}) {
    final comp = InMemoryCompetitionRepository();
    if (seasonExists) {
      comp.seasons[seasonId] = season();
    }
    final preds = _InMemoryFixturePredictionRepository();
    final root = CompositionRoot.forTesting(
      linkFixtureToSeason: LinkFixtureToSeason(
        competitionRepository: comp,
        fixturePredictionRepository: preds,
      ),
    );
    return (root: root, comp: comp, preds: preds);
  }

  group('POST /seasons/{id}/fixtures', () {
    test('an admin links a fixture and gets 201 with the link DTO', () async {
      final setup = rootWith();
      final context = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {'fixture_id': fixtureId, 'display_order': 2},
      );

      final response = await fixtures_route.onRequest(context, seasonId);

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['schema_version'], 1);
      expect(body['season_id'], seasonId);
      expect(body['fixture_id'], fixtureId);
      expect(body['display_order'], 2);
      expect(setup.preds.count, 1);
    });

    test('a non-admin is rejected (401, no link persisted)', () async {
      final setup = rootWith();
      final context = wireContext(
        root: setup.root,
        principal: userPrincipal(),
        body: {'fixture_id': fixtureId, 'display_order': 0},
      );

      final response = await fixtures_route.onRequest(context, seasonId);

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(setup.preds.count, 0);
    });

    test('a missing fixture_id is 400', () async {
      final setup = rootWith();
      final context = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {'display_order': 0},
      );

      final response = await fixtures_route.onRequest(context, seasonId);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('a missing display_order is 400', () async {
      final setup = rootWith();
      final context = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {'fixture_id': fixtureId},
      );

      final response = await fixtures_route.onRequest(context, seasonId);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test(
      'an unknown season is 409 with code competition.season_not_found',
      () async {
        final setup = rootWith(seasonExists: false);
        final context = wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          body: {'fixture_id': fixtureId, 'display_order': 0},
        );

        final response = await fixtures_route.onRequest(context, seasonId);

        expect(response.statusCode, HttpStatus.conflict);
        final body = await decodeBody(response);
        expect(body['code'], 'competition.season_not_found');
      },
    );

    test('a duplicate link is 409 with code '
        'competition.season_fixture_already_linked', () async {
      final setup = rootWith();
      final first = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {'fixture_id': fixtureId, 'display_order': 0},
      );
      await fixtures_route.onRequest(first, seasonId);

      final second = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {'fixture_id': fixtureId, 'display_order': 1},
      );
      final response = await fixtures_route.onRequest(second, seasonId);

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'competition.season_fixture_already_linked');
    });

    test('an unsupported method (DELETE) is 405', () async {
      final setup = rootWith();
      final context = wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        method: HttpMethod.delete,
      );

      final response = await fixtures_route.onRequest(context, seasonId);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// A minimal in-memory [FixturePredictionRepository] for this route test file
/// only (kept local, mirrors the equivalent private fake in
/// `fixture_prediction_scoring_test.dart` — not a substitute for the
/// application package's own fake). Only `linkFixtureToSeason` is exercised
/// here; every other member is unreachable from this route and left
/// unimplemented on purpose (a call would be a test-scope bug, not a
/// production path). Never throws for the members it does implement.
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final Map<String, SeasonFixture> _seasonFixtures = {};

  int get count => _seasonFixtures.length;

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
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
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) =>
      throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) =>
      throw UnimplementedError('not exercised by this route test file');
}
