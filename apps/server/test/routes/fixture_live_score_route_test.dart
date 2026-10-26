import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/live-score/index.dart' as live_score;
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/live/index.dart' as season_live;
import 'competition_route_harness.dart';

final DateTime _now = DateTime.utc(2026, 10, 18, 16, 2);

final class _Predictions extends Mock implements FixturePredictionRepository {}

final class _Totals implements FixtureTotalsReader {
  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => const Result.ok(<ParticipantFixtureTotals>[]);
}

final class _Rules implements RulesetProvider {
  @override
  Future<Result<RulesetSnapshot>> currentSnapshotFor(FormatType format) async =>
      RulesetSnapshot.create(
        payload: const {
          'format': 'football_scoreline',
          'double_multiplier': 2,
          'points': {
            'exact_scoreline': 3,
            'correct_outcome': 0,
            'incorrect': 0,
          },
        },
        rulesetVersion: 3,
      );
}

/// Paris FC - Rennes, 2026-10-18: the feed kept 2-2 after Rennes' second
/// goal was ruled out. Through the real wiring -- the in-process boards the
/// composition root builds, `PUT /fixtures/{id}/live-score`, and the
/// player's own `GET /seasons/{id}/live` -- the admin's 2-1 is what the
/// player's exact 2-1 is graded on, and taking it back restores the feed.
void main() {
  late InMemoryLiveScoreBoard provider;
  late CompositionRoot root;

  setUp(() {
    provider = InMemoryLiveScoreBoard(now: () => _now)
      ..put({
        kFixtureId: LiveScore(
          homeGoals: 2,
          awayGoals: 2,
          minute: 62,
          finished: false,
          updatedAt: _now,
        ),
      });
    final corrections = InMemoryLiveScoreCorrections(now: () => _now);
    final competition = InMemoryCompetitionRepository();
    competition.participants.add(
      Participant.fromStored(
        id: const ParticipantId(kParticipantId),
        seasonId: const SeasonId(kSeasonId),
        userId: const UserId(kUserId),
        status: ParticipantStatus.active,
        joinedAt: DateTime.utc(2026, 10),
      ),
    );
    final predictions = _Predictions();
    when(
      () => predictions.listSeasonFixtures(const SeasonId(kSeasonId)),
    ).thenAnswer((_) async => const Result.ok([FixtureRef(kFixtureId)]));
    when(
      () => predictions.listByFixture(const FixtureRef(kFixtureId)),
    ).thenAnswer(
      (_) async => Result.ok([
        FixturePredictionView(
          prediction: const FixturePrediction.fromStored(
            id: PredictionId('71111111-1111-1111-1111-111111111111'),
            fixture: FixtureRef(kFixtureId),
            participantId: ParticipantId(kParticipantId),
            homeGoals: 2,
            awayGoals: 1,
          ),
          submittedAt: _now.subtract(const Duration(days: 1)),
        ),
      ]),
    );
    root = CompositionRoot.forTesting(
      getLiveStanding: GetLiveStanding(
        competition: competition,
        fixturePredictions: predictions,
        totals: _Totals(),
        results: InMemoryFixtureResultRepository(),
        rulesets: _Rules(),
        liveScores: CorrectedLiveScoreBoard(
          raw: provider,
          corrections: corrections,
        ),
      ),
      correctLiveScore: AdminCorrectLiveScore(
        providerScores: provider,
        corrections: corrections,
        clock: FixedClock(_now),
      ),
    );
  });

  Future<Response> correct(
    AuthenticatedUser principal, {
    HttpMethod method = HttpMethod.put,
    Map<String, Object?>? body,
  }) => live_score.onRequest(
    wireContext(root: root, principal: principal, method: method, body: body),
    kFixtureId,
  );

  Future<Map<String, Object?>> playerLive() async {
    final response = await season_live.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
      kSeasonId,
    );
    expect(response.statusCode, HttpStatus.ok);
    final fixtures = (await decodeBody(response))['fixtures']! as List<Object?>;
    return (fixtures.single! as Map<Object?, Object?>).cast<String, Object?>();
  }

  test(
    'the admin correction is what the player sees and is graded on',
    () async {
      expect((await playerLive())['my_points'], 0);

      final response = await correct(
        adminPrincipal(),
        body: {'home_goals': 2, 'away_goals': 1},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(await decodeBody(response), {
        'fixture_id': kFixtureId,
        'home_goals': 2,
        'away_goals': 1,
      });

      final live = await playerLive();
      expect(
        (
          live['home_goals'],
          live['away_goals'],
          live['minute'],
          live['my_points'],
        ),
        (2, 1, 62, 3),
      );

      final cleared = await correct(
        adminPrincipal(),
        method: HttpMethod.delete,
      );
      expect(cleared.statusCode, HttpStatus.ok);
      expect(await decodeBody(cleared), {'cleared': true});
      final restored = await playerLive();
      expect((restored['home_goals'], restored['away_goals']), (2, 2));
      expect(restored['my_points'], 0);
    },
  );

  test('a player cannot correct a score (401)', () async {
    final response = await correct(
      userPrincipal(),
      body: {'home_goals': 2, 'away_goals': 1},
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect((await playerLive())['home_goals'], 2);
    expect((await playerLive())['away_goals'], 2);
  });

  test('a match the provider no longer reports is refused (409)', () async {
    provider.remove([kFixtureId]);

    final response = await correct(
      adminPrincipal(),
      body: {'home_goals': 2, 'away_goals': 1},
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'football_data.not_live');
  });

  test('any other method is 405', () async {
    final response = await correct(adminPrincipal(), method: HttpMethod.get);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
