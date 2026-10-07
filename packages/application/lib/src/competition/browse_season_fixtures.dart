import 'package:application/src/competition/fixture_visibility.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: a season's fixtures, in display order, each enriched with
/// its fixture-schedule identity (team names + kickoff).
///
/// Axiom 4 Amendment — the season-scoped sibling of [BrowseRoundFixtures],
/// since a fixture's prediction belongs to its season directly via
/// [SeasonFixture], never a round. Reads
/// [FixturePredictionRepository.listSeasonFixtures] (already ratified,
/// used by `GetSeasonFixtureLeaderboard`) then batches the schedule lookup
/// via [FixtureScheduleRepository.findByFixtures] — one extra query for the
/// whole season, never one per fixture (no N+1). [SeasonFixtureCard.homeTeam]/
/// [awayTeam]/[kickoffAt] are `null` when a linked fixture has no registered
/// schedule yet (Axiom 3: the link never verifies one exists).
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing browse read — no season-membership check, same
/// as [ListSeasonRounds]/[BrowseRoundFixtures]). A season with no linked
/// fixtures — or one that does not exist — yields a legitimate empty list (no
/// existence oracle), never an error.
///
/// Hidden and test fixtures (migration 0098) follow [FixtureVisibility]: a
/// player never receives either; an admin receives test fixtures, flagged,
/// and hidden ones too only when asking for them (`includeHidden`) -- the
/// admin panel's fixture list.
///
/// Never throws; returns a typed [Result].
final class BrowseSeasonFixtures {
  /// Creates the use-case over its repositories.
  const BrowseSeasonFixtures({
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
  }) : _fixturePredictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository;

  final FixturePredictionRepository _fixturePredictions;
  final FixtureScheduleRepository _schedules;

  /// Lists season [seasonId]'s fixtures, visible to [principal], each
  /// enriched with its schedule identity when one is registered.
  Future<Result<List<SeasonFixtureCard>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    bool includeHidden = false,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final idResult = SeasonId.tryParse(seasonId);
    if (idResult is Err<SeasonId>) {
      return Result.err(idResult.error);
    }

    final fixturesResult = await _fixturePredictions.listSeasonFixtures(
      (idResult as Ok<SeasonId>).value,
    );
    if (fixturesResult is Err<List<FixtureRef>>) {
      return Result.err(fixturesResult.error);
    }
    final fixtures = (fixturesResult as Ok<List<FixtureRef>>).value;
    if (fixtures.isEmpty) {
      return const Result.ok([]);
    }

    final schedulesResult = await _schedules.findByFixtures(fixtures);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final byFixture = {
      for (final schedule
          in (schedulesResult as Ok<List<FixtureSchedule>>).value)
        schedule.fixture.value: schedule,
    };

    return Result.ok([
      for (final fixture in fixtures)
        if (FixtureVisibility.listable(
          principal,
          byFixture[fixture.value],
          includeHidden: includeHidden,
        ))
          SeasonFixtureCard(
            seasonId: (idResult).value,
            fixtureId: fixture,
            homeTeam: byFixture[fixture.value]?.homeTeam,
            awayTeam: byFixture[fixture.value]?.awayTeam,
            kickoffAt: byFixture[fixture.value]?.kickoffAt,
            homeTeamId: byFixture[fixture.value]?.homeTeamId,
            awayTeamId: byFixture[fixture.value]?.awayTeamId,
            leagueName: byFixture[fixture.value]?.leagueName,
            leagueLogoUrl: byFixture[fixture.value]?.leagueLogoUrl,
            hidden: byFixture[fixture.value]?.isHidden ?? false,
            isTest: byFixture[fixture.value]?.isTest ?? false,
          ),
    ]);
  }
}
