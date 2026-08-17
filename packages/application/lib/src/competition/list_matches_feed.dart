import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One card in the unified matches feed: a single open round's fixture,
/// enriched with its owning competition's display name and the round's
/// frozen ruleset version — the wire-adjacent shape `GET /feed/matches`
/// projects (`competition_dto_mapper.matchFeedEntryToDto`).
final class MatchFeedEntry {
  /// Creates a feed entry.
  const MatchFeedEntry({
    required this.competitionName,
    required this.roundId,
    required this.rulesetVersion,
    required this.fixture,
  });

  /// The owning competition's display name.
  final String competitionName;

  /// The owning round's identity — predictions are submitted per round.
  final RoundId roundId;

  /// The round's frozen ruleset version (never the opaque snapshot).
  final int rulesetVersion;

  /// The fixture card itself (team names + kickoff; nullable per Axiom 3).
  final RoundFixtureCard fixture;

  @override
  bool operator ==(Object other) =>
      other is MatchFeedEntry &&
      other.competitionName == competitionName &&
      other.roundId == roundId &&
      other.rulesetVersion == rulesetVersion &&
      other.fixture == fixture;

  @override
  int get hashCode =>
      Object.hash(competitionName, roundId, rulesetVersion, fixture);
}

/// Query use-case: the unified **matches feed** — every currently-open
/// round's fixture(s) across every public competition, flattened into one
/// ordered list, in three database reads total (no client-side fan-out).
///
/// Replaces the former client-side composition (`apps/mobile`'s
/// `matchesFeed` provider walking `GET /competitions` ->
/// `.../seasons` -> `.../rounds` -> per-open-round
/// `GET /rounds/{id}/fixtures`), which degenerated into O(open rounds) HTTP
/// round-trips — most of them empty — once a season accumulated many opened-
/// but-unlinked rounds. This use-case performs the same aggregation
/// server-side over exactly three queries:
///
/// 1. [CompetitionRepository.listOpenRoundsFeed] — every open round of every
///    public competition, joined with its competition's display name.
/// 2. [CompetitionRepository.listFixturesForRounds] — every fixture linked to
///    any of those rounds, batched (the `round_fixtures` analogue of
///    [FixtureScheduleRepository.findByFixtures]'s existing batching).
/// 3. [FixtureScheduleRepository.findByFixtures] — the schedule identity
///    (team names + kickoff) for every fixture named by step 2, batched
///    exactly as [BrowseRoundFixtures] already does for a single round.
///
/// `GET /rounds/{id}/fixtures` (and [BrowseRoundFixtures]) is untouched and
/// stays the read for a single round's prediction-form render; this use-case
/// is purely additive.
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing read). No open rounds anywhere — or none with
/// any linked fixture — is a legitimate `Ok(<empty list>)`, never an error
/// (a browse read reveals no existence oracle).
///
/// Never throws; returns a typed [Result].
final class ListMatchesFeed {
  /// Creates the use-case over its repositories.
  const ListMatchesFeed({
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
  }) : _competition = competitionRepository,
       _schedules = fixtureScheduleRepository;

  final CompetitionRepository _competition;
  final FixtureScheduleRepository _schedules;

  /// Builds the unified feed, visible to [principal].
  Future<Result<List<MatchFeedEntry>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final openRoundsResult = await _competition.listOpenRoundsFeed();
    if (openRoundsResult is Err<List<OpenRoundFeedEntry>>) {
      return Result.err(openRoundsResult.error);
    }
    final openRounds = (openRoundsResult as Ok<List<OpenRoundFeedEntry>>).value;
    if (openRounds.isEmpty) {
      return const Result.ok([]);
    }

    final linksResult = await _competition.listFixturesForRounds([
      for (final entry in openRounds) entry.roundId,
    ]);
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

    // Group links by round, preserving the batch read's order within each
    // round (round_id, then display_order — the port's documented contract),
    // so each round's fixtures still render in matchday order.
    final linksByRound = <String, List<RoundFixture>>{};
    for (final link in links) {
      (linksByRound[link.roundId.value] ??= []).add(link);
    }

    return Result.ok([
      for (final entry in openRounds)
        for (final link
            in linksByRound[entry.roundId.value] ?? const <RoundFixture>[])
          MatchFeedEntry(
            competitionName: entry.competitionName,
            roundId: entry.roundId,
            rulesetVersion: entry.rulesetVersion,
            fixture: RoundFixtureCard(
              roundId: link.roundId,
              fixtureId: link.fixture,
              displayOrder: link.displayOrder,
              homeTeam: byFixture[link.fixture.value]?.homeTeam,
              awayTeam: byFixture[link.fixture.value]?.awayTeam,
              kickoffAt: byFixture[link.fixture.value]?.kickoffAt,
            ),
          ),
    ]);
  }
}
