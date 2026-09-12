import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/prediction-distribution/index.dart'
    as distribution_route;
import 'competition_route_harness.dart';

/// Route tests for the aggregate fixture-prediction distribution read.
/// Individual prediction rows never cross this route boundary.
void main() {
  const fixtureId = '66666666-6666-6666-6666-666666666666';
  const participant1 = '99999999-9999-9999-9999-999999999999';
  const participant2 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const participant3 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

  FixtureRef fixture() =>
      (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;

  SeasonFixture link() =>
      (SeasonFixture.create(
                seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
                fixture: fixture(),
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value;

  FixturePrediction prediction({
    required String participantId,
    required int home,
    required int away,
  }) => FixturePrediction.fromStored(
    id: (PredictionId.tryParse(participantId) as Ok<PredictionId>).value,
    fixture: fixture(),
    participantId:
        (ParticipantId.tryParse(participantId) as Ok<ParticipantId>).value,
    homeGoals: home,
    awayGoals: away,
  );

  ({CompositionRoot root}) buildRoot({bool linked = true}) {
    final repo = _InMemoryFixturePredictionRepository();
    if (linked) {
      repo.links.add(link());
    }
    final submitted = DateTime.utc(2026, 9, 12);
    repo.predictions.addAll([
      FixturePredictionView(
        prediction: prediction(participantId: participant1, home: 2, away: 1),
        submittedAt: submitted,
      ),
      FixturePredictionView(
        prediction: prediction(participantId: participant2, home: 0, away: 1),
        submittedAt: submitted,
      ),
      FixturePredictionView(
        prediction: prediction(participantId: participant3, home: 1, away: 1),
        submittedAt: submitted,
      ),
    ]);
    return (
      root: CompositionRoot.forTesting(
        getFixturePredictionDistribution: GetFixturePredictionDistribution(
          fixturePredictionRepository: repo,
        ),
      ),
    );
  }

  test(
    'GET returns aggregate percentages without individual prediction data',
    () async {
      final setup = buildRoot();
      final response = await distribution_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        kSeasonId,
        fixtureId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['home_win_percentage'], 50);
      expect(body['away_win_percentage'], 50);
      expect(body.containsKey('participant_id'), isFalse);
    },
  );

  test('GET rejects a fixture not linked to the requested season', () async {
    final setup = buildRoot(linked: false);
    final response = await distribution_route.onRequest(
      wireContext(
        root: setup.root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
      kSeasonId,
      fixtureId,
    );

    final body = await decodeBody(response);
    expect(body['code'], 'prediction.fixture_not_in_season');
  });

  test('rejects non-GET methods', () async {
    final setup = buildRoot();
    final response = await distribution_route.onRequest(
      wireContext(
        root: setup.root,
        principal: userPrincipal(),
        method: HttpMethod.post,
      ),
      kSeasonId,
      fixtureId,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}

final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final List<SeasonFixture> links = [];
  final List<FixturePredictionView> predictions = [];

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    for (final link in links) {
      if (link.seasonId == seasonId && link.fixture == fixture) {
        return Result.ok(link);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(false);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok([
    for (final view in predictions)
      if (view.prediction.fixture == fixture) view,
  ]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok(<FixtureRef>[]);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok(<FixturePredictionView>[]);
}
