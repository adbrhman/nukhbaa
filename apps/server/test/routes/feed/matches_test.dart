import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in
// isolation.
// ignore: always_use_package_imports
import '../../../routes/feed/matches/index.dart' as matches_route;
import '../competition_route_harness.dart';

/// Route test for `GET /feed/matches` — the unified matches-feed aggregate
/// read (server-side fan-in, replacing the client-side competition -> season
/// -> round -> fixtures drill-down).
///
/// Tested through the real wiring
/// (`context.read<Future<CompositionRoot>>()` -> `root.listMatchesFeed()`)
/// over the in-memory [InMemoryCompetitionRepository], mirroring
/// `rounds_browse_test.dart`.
void main() {
  RulesetSnapshot snapshot() =>
      (RulesetSnapshot.create(payload: const {'exact': 3}, rulesetVersion: 1)
              as Ok<RulesetSnapshot>)
          .value;

  Competition competition(String id, String name) =>
      (Competition.create(
                id: CompetitionId(id),
                name: name,
                format: FormatType.footballScoreline,
                visibility: CompetitionVisibility.public,
              )
              as Ok<Competition>)
          .value;

  CompetitionSeason season(String id, String competitionId) =>
      (CompetitionSeason.create(
                id: SeasonId(id),
                competitionId: CompetitionId(competitionId),
                label: '2026/27',
              )
              as Ok<CompetitionSeason>)
          .value;

  Round openRound(String id, String seasonId) => Round.fromStored(
    id: RoundId(id),
    seasonId: SeasonId(seasonId),
    sequence: 1,
    predictionDeadline: DateTime.utc(2026, 8, 1, 12),
    status: RoundStatus.open,
    ruleset: snapshot(),
  );

  RoundFixture link(String roundId, String fixtureId, int order) =>
      RoundFixture.fromStored(
        roundId: RoundId(roundId),
        fixture: (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value,
        displayOrder: order,
      );

  late InMemoryCompetitionRepository repo;

  CompositionRoot rootWith() {
    repo = InMemoryCompetitionRepository();
    return CompositionRoot.forTesting(
      listMatchesFeed: ListMatchesFeed(
        competitionRepository: repo,
        fixtureScheduleRepository: InMemoryFixtureScheduleRepository(),
      ),
    );
  }

  test(
    'returns 200 with the feed, grouped by competition then fixture order',
    () async {
      final root = rootWith();
      repo.competitions[kCompetitionId] = competition(
        kCompetitionId,
        'Premier League',
      );
      repo.seasons[kSeasonId] = season(kSeasonId, kCompetitionId);
      repo.rounds[kRoundId] = openRound(kRoundId, kSeasonId);
      repo.links.add(link(kRoundId, kFixtureId, 0));

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      final response = await matches_route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      final items = body.cast<Map<String, Object?>>();
      expect(items, hasLength(1));
      expect(items.single['competition_name'], 'Premier League');
      expect(items.single['round_id'], kRoundId);
      expect(items.single['ruleset_version'], 1);
      final fixture = items.single['fixture']! as Map<Object?, Object?>;
      expect(fixture['fixture_id'], kFixtureId);
      expect(fixture['display_order'], 0);
    },
  );

  test('no open rounds anywhere is a legitimate 200 empty array (no '
      'existence oracle)', () async {
    final context = wireContext(
      root: rootWith(),
      principal: userPrincipal(),
      method: HttpMethod.get,
    );

    final response = await matches_route.onRequest(context);

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.json() as List<Object?>;
    expect(body, isEmpty);
  });

  test('an open round with no linked fixtures contributes nothing', () async {
    final root = rootWith();
    repo.competitions[kCompetitionId] = competition(
      kCompetitionId,
      'Premier League',
    );
    repo.seasons[kSeasonId] = season(kSeasonId, kCompetitionId);
    repo.rounds[kRoundId] = openRound(kRoundId, kSeasonId);
    // No links seeded.

    final context = wireContext(
      root: root,
      principal: userPrincipal(),
      method: HttpMethod.get,
    );

    final response = await matches_route.onRequest(context);

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.json() as List<Object?>;
    expect(body, isEmpty);
  });

  test('an unsupported method (POST) is 405', () async {
    final context = wireContext(root: rootWith(), principal: userPrincipal());

    final response = await matches_route.onRequest(context);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
