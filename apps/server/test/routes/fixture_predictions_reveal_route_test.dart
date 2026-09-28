import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/predictions/index.dart'
    as predictions_route;
import 'competition_route_harness.dart';

/// Route tests for `GET /seasons/{id}/fixtures/{fixtureId}/predictions`:
/// nothing before kickoff, every prediction with its player's name after.
void main() {
  const fixtureId = '66666666-6666-6666-6666-666666666666';
  const myParticipant = '99999999-9999-9999-9999-999999999999';
  const otherParticipant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final kickoff = DateTime.utc(2026, 9, 28, 18);

  FixtureRef fixture() =>
      (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;

  Participant participant(String id, String userId) => Participant.fromStored(
    id: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
    seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
    userId: (UserId.tryParse(userId) as Ok<UserId>).value,
    status: ParticipantStatus.active,
    joinedAt: DateTime.utc(2026, 9),
  );

  CompositionRoot buildRoot({required DateTime now}) {
    final competition = InMemoryCompetitionRepository();
    final me = participant(myParticipant, kUserId);
    final other = participant(
      otherParticipant,
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    );
    competition.participants.add(me);

    final names = InMemoryParticipantReader()
      ..add(me)
      ..add(other);

    final schedules = InMemoryFixtureScheduleRepository()
      ..seed(
        FixtureSchedule.fromStored(
          fixture: fixture(),
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          kickoffAt: kickoff,
        ),
      );

    final predictions = _InMemoryFixturePredictionRepository()
      ..links.add(
        (SeasonFixture.create(
                  seasonId:
                      (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
                  fixture: fixture(),
                  displayOrder: 0,
                )
                as Ok<SeasonFixture>)
            .value,
      );
    for (final (id, home, away) in [
      (myParticipant, 2, 1),
      (otherParticipant, 1, 1),
    ]) {
      predictions.stored.add(
        FixturePredictionView(
          prediction: FixturePrediction.fromStored(
            id: (PredictionId.tryParse(id) as Ok<PredictionId>).value,
            fixture: fixture(),
            participantId:
                (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
            homeGoals: home,
            awayGoals: away,
          ),
          submittedAt: DateTime.utc(2026, 9, 28, 12),
        ),
      );
    }

    return CompositionRoot.forTesting(
      listFixturePredictions: ListFixturePredictions(
        competitionRepository: competition,
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: schedules,
        participantReader: names,
        clock: FixedClock(now),
      ),
    );
  }

  Future<Response> get(CompositionRoot root, {HttpMethod? method}) =>
      predictions_route.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: method ?? HttpMethod.get,
        ),
        kSeasonId,
        fixtureId,
      );

  test('before kickoff the route refuses and reveals nothing', () async {
    final response = await get(
      buildRoot(now: kickoff.subtract(const Duration(seconds: 1))),
    );

    expect(response.statusCode, HttpStatus.conflict);
    final body = await decodeBody(response);
    expect(body['code'], 'prediction.fixture_not_started');
    expect(body.containsKey('home_goals'), isFalse);
  });

  test('after kickoff every prediction arrives with its player name', () async {
    final response = await get(
      buildRoot(now: kickoff.add(const Duration(minutes: 5))),
    );

    expect(response.statusCode, HttpStatus.ok);
    final rows = (await response.json() as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(rows, hasLength(2));
    final byParticipant = {for (final row in rows) row['participant_id']: row};
    expect(byParticipant[myParticipant]!['home_goals'], 2);
    expect(byParticipant[myParticipant]!['away_goals'], 1);
    expect(byParticipant[otherParticipant]!['home_goals'], 1);
    expect(byParticipant[otherParticipant]!['display_name'], 'Test User');
  });

  test('rejects non-GET methods', () async {
    final response = await get(
      buildRoot(now: kickoff.add(const Duration(minutes: 5))),
      method: HttpMethod.post,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}

final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final List<SeasonFixture> links = [];
  final List<FixturePredictionView> stored = [];

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
    for (final view in stored)
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
