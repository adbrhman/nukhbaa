import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: a round's fixtures, in matchday order, each enriched with
/// its fixture-schedule identity (team names + kickoff).
///
/// Session decision 2026-08-07: widens the former `ListRoundFixtures` read
/// instead of adding a new endpoint. Batches the schedule lookup via
/// [FixtureScheduleRepository.findByFixtures] — one extra query for the whole
/// round, never one per fixture (no N+1). [RoundFixtureCard.homeTeam]/
/// [awayTeam]/[kickoffAt] are `null` when a linked fixture has no registered
/// schedule yet (Axiom 3: the link never verifies one exists).
///
/// This is the client-facing Competition-context browse read, gated and
/// shaped for the prediction-form render — distinct from the Prediction
/// phase's internal `PredictionRepository.listRoundFixtures`, which stays
/// frozen and untouched.
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing read). A round with no linked fixtures — or one
/// that does not exist — yields a legitimate empty list (no existence
/// oracle), never an error.
///
/// Never throws; returns a typed [Result].
final class BrowseRoundFixtures {
  /// Creates the use-case over its repositories.
  const BrowseRoundFixtures({
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
  }) : _competition = competitionRepository,
       _schedules = fixtureScheduleRepository;

  final CompetitionRepository _competition;
  final FixtureScheduleRepository _schedules;

  /// Lists round [roundId]'s fixtures, visible to [principal], each enriched
  /// with its schedule identity when one is registered.
  Future<Result<List<RoundFixtureCard>>> call({
    required AuthenticatedUser principal,
    required String roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final idResult = RoundId.tryParse(roundId);
    if (idResult is Err<RoundId>) {
      return Result.err(idResult.error);
    }

    final linksResult = await _competition.listRoundFixtures(
      (idResult as Ok<RoundId>).value,
    );
    if (linksResult is Err<List<RoundFixture>>) {
      return Result.err(linksResult.error);
    }
    final links = (linksResult as Ok<List<RoundFixture>>).value;
    if (links.isEmpty) {
      return const Result.ok([]);
    }

    final schedulesResult = await _schedules.findByFixtures([
      for (final link in links) link.fixture,
    ]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final byFixture = {
      for (final schedule
          in (schedulesResult as Ok<List<FixtureSchedule>>).value)
        schedule.fixture.value: schedule,
    };

    return Result.ok([
      for (final link in links)
        RoundFixtureCard(
          roundId: link.roundId,
          fixtureId: link.fixture,
          displayOrder: link.displayOrder,
          homeTeam: byFixture[link.fixture.value]?.homeTeam,
          awayTeam: byFixture[link.fixture.value]?.awayTeam,
          kickoffAt: byFixture[link.fixture.value]?.kickoffAt,
        ),
    ]);
  }
}
