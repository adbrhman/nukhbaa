import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/prediction/ports/fixture_prediction_tally_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One card in the unified **current-month** fixture feed: a single fixture
/// linked to a competition's *current* season, enriched with its owning
/// competition's display name and the season's display label.
///
/// Monthly Competitions transition (project-context.md §9) — the aggregation
/// gap identified there: the platform already has [ListCompetitions],
/// [GetCurrentSeason], and [BrowseSeasonFixtures], but no single read
/// flattening "every public competition's current-month fixtures" into one
/// list, the way [ListMatchesFeed] already does for open rounds.
final class CurrentMonthFixtureEntry {
  /// Creates a feed entry.
  const CurrentMonthFixtureEntry({
    required this.competitionId,
    required this.competitionName,
    required this.seasonLabel,
    required this.fixture,
    this.homeWinPercentage,
    this.awayWinPercentage,
  });

  /// The owning competition's identity.
  final CompetitionId competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The current season's display label (e.g. "08/2026").
  final String seasonLabel;

  /// The fixture card itself (season id, fixture id, team names + kickoff;
  /// nullable per Axiom 3).
  final SeasonFixtureCard fixture;

  /// The home share of decisive predictions on this fixture, or `null` when
  /// the feed was built without a [FixturePredictionTallyReader] (no tally
  /// was read at all -- which is NOT the same as a fixture nobody predicted,
  /// which is a genuine `0`).
  final int? homeWinPercentage;

  /// The away share of decisive predictions, with the same null meaning.
  final int? awayWinPercentage;

  @override
  bool operator ==(Object other) =>
      other is CurrentMonthFixtureEntry &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.seasonLabel == seasonLabel &&
      other.fixture == fixture &&
      other.homeWinPercentage == homeWinPercentage &&
      other.awayWinPercentage == awayWinPercentage;

  @override
  int get hashCode => Object.hash(
    competitionId,
    competitionName,
    seasonLabel,
    fixture,
    homeWinPercentage,
    awayWinPercentage,
  );

  @override
  String toString() =>
      'CurrentMonthFixtureEntry(${competitionId.value} "$competitionName", '
      'season "$seasonLabel", $fixture)';
}

/// Query use-case: every public competition's **current** (calendar-month)
/// season, fixtures flattened into one ordered list — the read the Monthly
/// Competitions home feed needs (project-context.md §9), composed entirely
/// from already-ratified reads, no new SQL:
///
/// 1. [CompetitionRepository.listCompetitions] — every public competition,
///    name-ordered.
/// 2. [CompetitionRepository.findCurrentSeason] — per competition (bounded by
///    the number of competitions, not fixtures), the season whose window
///    covers now, if any.
/// 3. [FixturePredictionRepository.listSeasonFixtures] — per current season,
///    its linked fixtures in display order (the same source
///    [BrowseSeasonFixtures] reads for a single season).
/// 4. [FixtureScheduleRepository.findByFixtures] — one batched call across
///    every fixture found in step 3, mirroring [BrowseSeasonFixtures]'s and
///    [ListMatchesFeed]'s existing no-N+1 discipline for the final
///    enrichment hop.
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing browse read — no season-membership check, same
/// as [BrowseSeasonFixtures]). No public competitions, none with a season
/// currently covering "now", or none of those seasons having a linked
/// fixture are all legitimate `Ok(<empty list>)`, never an error.
///
/// Never throws; returns a typed [Result].
final class ListCurrentMonthFixtures {
  /// Creates the use-case over its repositories and clock.
  const ListCurrentMonthFixtures({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required Clock clock,
    FixturePredictionTallyReader? predictionTallyReader,
  }) : _competition = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository,
       _clock = clock,
       _tallies = predictionTallyReader;

  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureScheduleRepository _schedules;
  final Clock _clock;

  /// Optional on purpose: every existing construction of this use-case keeps
  /// compiling, and a feed built without it simply reports no split.
  final FixturePredictionTallyReader? _tallies;

  /// Builds the current-month feed, visible to [principal].
  Future<Result<List<CurrentMonthFixtureEntry>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final competitionsResult = await _competition.listCompetitions();
    if (competitionsResult is Err<List<Competition>>) {
      return Result.err(competitionsResult.error);
    }
    final competitions = (competitionsResult as Ok<List<Competition>>).value;
    if (competitions.isEmpty) {
      return const Result.ok([]);
    }

    final nowUtc = _clock.nowUtc();

    // Step 2: each competition's current season, if any -- one call per
    // competition (bounded by competition count, not fixture count;
    // project-context.md §9). Order preserved from step 1 (name-ordered).
    final currentSeasons =
        <({Competition competition, CompetitionSeason season})>[];
    for (final competition in competitions) {
      final seasonResult = await _competition.findCurrentSeason(
        competitionId: competition.id,
        nowUtc: nowUtc,
      );
      if (seasonResult is Err<CompetitionSeason?>) {
        return Result.err(seasonResult.error);
      }
      final season = (seasonResult as Ok<CompetitionSeason?>).value;
      if (season != null) {
        currentSeasons.add((competition: competition, season: season));
      }
    }
    if (currentSeasons.isEmpty) {
      return const Result.ok([]);
    }

    // Step 3: each current season's linked fixtures -- one call per season
    // (same bound as step 2; the same source BrowseSeasonFixtures reads).
    final fixturesBySeason = <String, List<FixtureRef>>{};
    for (final entry in currentSeasons) {
      final fixturesResult = await _fixturePredictions.listSeasonFixtures(
        entry.season.id,
      );
      if (fixturesResult is Err<List<FixtureRef>>) {
        return Result.err(fixturesResult.error);
      }
      fixturesBySeason[entry.season.id.value] =
          (fixturesResult as Ok<List<FixtureRef>>).value;
    }

    final allFixtures = <FixtureRef>[
      for (final fixtures in fixturesBySeason.values) ...fixtures,
    ];
    if (allFixtures.isEmpty) {
      return const Result.ok([]);
    }

    // Step 4: one batched schedule lookup across every season's fixtures --
    // never one query per fixture (mirrors BrowseSeasonFixtures/
    // ListMatchesFeed).
    final schedulesResult = await _schedules.findByFixtures(allFixtures);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final byFixture = {
      for (final schedule
          in (schedulesResult as Ok<List<FixtureSchedule>>).value)
        schedule.fixture.value: schedule,
    };

    // Step 5: the prediction split for the same fixture set, in ONE grouped
    // query -- the same no-N+1 discipline as step 4. This used to be a
    // per-card request from the client (one HTTP round trip per fixture on
    // screen); the feed already knows exactly which fixtures it is about to
    // return, so it answers the question while it is here.
    final tallies = <String, FixtureOutcomeTally>{};
    final FixturePredictionTallyReader? tallyReader = _tallies;
    if (tallyReader != null) {
      final talliesResult = await tallyReader.tallyByFixtures(allFixtures);
      if (talliesResult is Err<List<FixtureOutcomeTally>>) {
        return Result.err(talliesResult.error);
      }
      for (final tally
          in (talliesResult as Ok<List<FixtureOutcomeTally>>).value) {
        tallies[tally.fixture.value] = tally;
      }
    }

    return Result.ok([
      for (final entry in currentSeasons)
        for (final fixture in fixturesBySeason[entry.season.id.value]!)
          CurrentMonthFixtureEntry(
            competitionId: entry.competition.id,
            competitionName: entry.competition.name,
            seasonLabel: entry.season.label,
            // A fixture nobody has predicted has no tally row, which is a
            // real 0/0 split, not a missing answer -- so it reads as 0 while
            // the reader is wired, and as null only when it is not.
            homeWinPercentage: tallyReader == null
                ? null
                : (tallies[fixture.value]?.homeWinPercentage ?? 0),
            awayWinPercentage: tallyReader == null
                ? null
                : (tallies[fixture.value]?.awayWinPercentage ?? 0),
            fixture: SeasonFixtureCard(
              seasonId: entry.season.id,
              fixtureId: fixture,
              homeTeam: byFixture[fixture.value]?.homeTeam,
              awayTeam: byFixture[fixture.value]?.awayTeam,
              kickoffAt: byFixture[fixture.value]?.kickoffAt,
              homeTeamId: byFixture[fixture.value]?.homeTeamId,
              awayTeamId: byFixture[fixture.value]?.awayTeamId,
              leagueName: byFixture[fixture.value]?.leagueName,
              leagueLogoUrl: byFixture[fixture.value]?.leagueLogoUrl,
            ),
          ),
    ]);
  }
}
