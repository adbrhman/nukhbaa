import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Competition browse surface of `apps/server`.
///
/// Wraps exactly the read routes that exist today, verbatim — no invented path.
/// The four hops of the browse navigation competition -> season -> round ->
/// fixtures are all reachable now that the FA-1 season/round scope closure
/// (2026-07-13) added the two middle-hop GET branches:
///   * `GET /competitions`               -> `List<CompetitionDto>`
///     (`routes/competitions/index.dart` GET branch, public catalogue)
///   * `GET /competitions/{id}`          -> [CompetitionDto]
///     (`routes/competitions/[id]/index.dart`; `404 competition.not_found`)
///   * `GET /competitions/{id}/seasons`  -> `List<SeasonDto>`
///     (`routes/competitions/[id]/seasons/index.dart` GET branch, label order;
///     an absent competition is a legitimate empty array — no existence oracle)
///   * `GET /seasons/{id}/rounds`        -> `List<RoundDto>`
///     (`routes/seasons/[id]/rounds/index.dart` GET branch, sequence order;
///     an absent season is a legitimate empty array — no existence oracle)
///   * `GET /rounds/{id}`                -> [RoundDto]
///     (`routes/rounds/[id]/index.dart`; `404 competition.round_not_found`)
///   * `GET /rounds/{id}/fixtures`       -> `List<RoundFixtureCardDto>`
///     (`routes/rounds/[id]/fixtures/index.dart` GET branch, display order,
///     each card enriched with its schedule identity — team names + kickoff,
///     all nullable since the round<->fixture link never verifies a schedule
///     exists, Axiom 3; query intent `BrowseRoundFixtures`, Session decision
///     2026-08-07 widened this read instead of a new endpoint; an absent round
///     is a legitimate empty array — no existence oracle)
///
/// All routes are behind `bearerAuth`. The browse reads above are pure (no
/// side effect); [openRound], [linkFixtureToRound], [recordFixtureResult],
/// [scoreRound] below are admin-only commands (authorization enforced
/// server-side inside the use-case, never by this client). [getRoundScores]
/// is a participant-gated read. Every method returns a typed [Result] and
/// never throws.
final class CompetitionApi {
  /// Creates the Competition client over the shared [ApiTransport].
  const CompetitionApi(this._transport);

  final ApiTransport _transport;

  /// `GET /competitions` — the browsable public competition catalogue.
  ///
  /// An empty catalogue is a legitimate `Ok(<empty list>)`, never an error.
  Future<Result<List<CompetitionDto>>> listCompetitions() {
    return _transport.getList<CompetitionDto>(
      '/competitions',
      parseElement: CompetitionDto.fromJson,
    );
  }

  /// `GET /competitions/{id}` — a single competition.
  ///
  /// A missing competition is `Err(invariant, code: competition.not_found)`
  /// (the server returns a true `404` with that stable code); a malformed id is
  /// `Err(validation)`.
  Future<Result<CompetitionDto>> getCompetition(String competitionId) {
    return _transport.getObject<CompetitionDto>(
      '/competitions/$competitionId',
      parse: CompetitionDto.fromJson,
    );
  }

  /// `GET /competitions/{id}/seasons` — the competition's seasons, label order.
  ///
  /// The first middle hop of the browse navigation. A competition with no
  /// seasons — or one that does not exist — is a legitimate `Ok(<empty list>)`
  /// (the server reveals no existence oracle on this browse read).
  Future<Result<List<SeasonDto>>> listCompetitionSeasons(String competitionId) {
    return _transport.getList<SeasonDto>(
      '/competitions/$competitionId/seasons',
      parseElement: SeasonDto.fromJson,
    );
  }

  /// `GET /seasons/{id}/rounds` — the season's rounds, 1-based sequence order.
  ///
  /// The second middle hop of the browse navigation. A season with no rounds —
  /// or one that does not exist — is a legitimate `Ok(<empty list>)` (no
  /// existence oracle). Each [RoundDto] exposes only the ruleset *version*,
  /// never the opaque frozen snapshot.
  Future<Result<List<RoundDto>>> listSeasonRounds(String seasonId) {
    return _transport.getList<RoundDto>(
      '/seasons/$seasonId/rounds',
      parseElement: RoundDto.fromJson,
    );
  }

  /// `POST /seasons/{id}/participants` — enrols the calling user into the
  /// season (command intent `JoinCompetition`; API ADR §2). Any authenticated
  /// user may join (Axiom 1, social-first); the enrolled user is taken from
  /// the verified token, never sent by the client.
  ///
  /// Idempotent: a repeated join returns the existing enrolment (`200`)
  /// rather than erroring.
  Future<Result<ParticipantDto>> joinCompetition(String seasonId) {
    return _transport.postObject<ParticipantDto>(
      '/seasons/$seasonId/participants',
      body: const {},
      parse: ParticipantDto.fromJson,
    );
  }

  /// `GET /rounds/{id}` — a single round (status + deadline + ruleset version).
  ///
  /// A missing round is `Err(invariant, code: competition.round_not_found)`
  /// (true `404`); a malformed id is `Err(validation)`. The opaque frozen
  /// ruleset snapshot is never exposed — only [RoundDto.rulesetVersion].
  Future<Result<RoundDto>> getRound(String roundId) {
    return _transport.getObject<RoundDto>(
      '/rounds/$roundId',
      parse: RoundDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/fixtures` — the round's fixtures in display order,
  /// each enriched with its schedule identity (team names + kickoff) for the
  /// prediction-form render (query intent `BrowseRoundFixtures`; Session
  /// decision 2026-08-07 widened this read instead of a new per-fixture
  /// endpoint — batched, no N+1).
  ///
  /// A round with no linked fixtures — or one that does not exist — is a
  /// legitimate `Ok(<empty list>)` (the server reveals no existence oracle on
  /// this browse read). `homeTeam`/`awayTeam`/`kickoffAt` are `null` when the
  /// linked fixture has no schedule yet (the link never verifies one exists —
  /// Axiom 3).
  Future<Result<List<RoundFixtureCardDto>>> browseRoundFixtures(
    String roundId,
  ) {
    return _transport.getList<RoundFixtureCardDto>(
      '/rounds/$roundId/fixtures',
      parseElement: RoundFixtureCardDto.fromJson,
    );
  }

  /// `GET /feed/matches` — the unified matches feed: every currently-open
  /// round's fixture(s) across every public competition, flattened into one
  /// ordered list, in a single request (server-side aggregate read; query
  /// intent `ListMatchesFeed`, replacing the former client-side
  /// competition -> season -> round -> fixtures drill-down).
  ///
  /// No open rounds anywhere — or none with any linked fixture — is a
  /// legitimate `Ok(<empty list>)` (no existence oracle).
  Future<Result<List<MatchFeedItemDto>>> getMatchesFeed() {
    return _transport.getList<MatchFeedItemDto>(
      '/feed/matches',
      parseElement: MatchFeedItemDto.fromJson,
    );
  }

  /// `POST /seasons/{id}/rounds` — opens a new round in the season, freezing
  /// the ruleset (command intent `OpenRound`). Admin-only, enforced inside the
  /// server use-case. [predictionDeadline] must be an ISO 8601 timestamp
  /// string; the server normalizes it to UTC.
  Future<Result<RoundDto>> openRound({
    required String seasonId,
    required int sequence,
    required String predictionDeadline,
  }) {
    return _transport.postObject<RoundDto>(
      '/seasons/$seasonId/rounds',
      body: OpenRoundRequestDto(
        sequence: sequence,
        predictionDeadline: predictionDeadline,
      ).toJson(),
      parse: RoundDto.fromJson,
    );
  }

  /// `POST /rounds/{id}/fixtures` — links an already-registered fixture into
  /// the round at [displayOrder] (command intent `LinkFixtureToRound`; Axiom
  /// 3: the only place Competition names a fixture). Admin-only, enforced
  /// inside the server use-case.
  Future<Result<RoundFixtureDto>> linkFixtureToRound({
    required String roundId,
    required String fixtureId,
    required int displayOrder,
  }) {
    return _transport.postObject<RoundFixtureDto>(
      '/rounds/$roundId/fixtures',
      body: LinkFixtureToRoundRequestDto(
        fixtureId: fixtureId,
        displayOrder: displayOrder,
      ).toJson(),
      parse: RoundFixtureDto.fromJson,
    );
  }

  /// `PUT /fixtures/{id}/result` — records (or idempotently corrects) the
  /// fixture's actual final score (command intent `RecordFixtureResult`;
  /// Axiom 3: a result carries no competition/round reference). Admin-only,
  /// enforced inside the server use-case.
  Future<Result<FixtureResultDto>> recordFixtureResult({
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) {
    return _transport.putObject<FixtureResultDto>(
      '/fixtures/$fixtureId/result',
      body: {'home_goals': homeGoals, 'away_goals': awayGoals},
      parse: FixtureResultDto.fromJson,
    );
  }

  /// `POST /rounds/{id}/score` — scores every prediction in the round
  /// (command intent `ScoreRound`). No request body — points are computed
  /// server-side from the round's frozen ruleset; the client never posts
  /// points (Axioms 2/5). Admin-only, enforced inside the server use-case.
  /// Idempotent: re-scoring an already-`scored` round recomputes the same
  /// deterministic result.
  Future<Result<RoundScoresDto>> scoreRound(String roundId) {
    return _transport.postObject<RoundScoresDto>(
      '/rounds/$roundId/score',
      body: const {},
      parse: RoundScoresDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/scores` — reads every participant's computed score for
  /// a **scored** round (query intent `GetRoundScores`). A not-yet-scored
  /// round is refused `409 scoring.round_not_scored`; a non-participant is
  /// refused `401 scoring.not_a_participant` (server-enforced).
  Future<Result<RoundScoresDto>> getRoundScores(String roundId) {
    return _transport.getObject<RoundScoresDto>(
      '/rounds/$roundId/scores',
      parse: RoundScoresDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/report` — every participant's correct/incorrect
  /// fixture-grade counts and total points for a **scored** round (Task 5).
  /// Same gates as [getRoundScores]: a not-yet-scored round is refused
  /// `409 scoring.round_not_scored`; a non-participant is refused
  /// `401 scoring.not_a_participant` (server-enforced).
  Future<Result<RoundReportDto>> getRoundReport(String roundId) {
    return _transport.getObject<RoundReportDto>(
      '/rounds/$roundId/report',
      parse: RoundReportDto.fromJson,
    );
  }
}
