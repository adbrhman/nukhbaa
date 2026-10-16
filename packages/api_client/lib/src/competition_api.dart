import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Competition browse surface of `apps/server`.
///
/// Wraps exactly the read routes that exist today, verbatim — no invented path.
/// The browse navigation is competition -> season -> fixtures (Axiom 4
/// Amendment: the round hop is gone):
///   * `GET /competitions`               -> `List<CompetitionDto>`
///     (`routes/competitions/index.dart` GET branch, public catalogue)
///   * `GET /competitions/{id}`          -> [CompetitionDto]
///     (`routes/competitions/[id]/index.dart`; `404 competition.not_found`)
///   * `GET /competitions/{id}/seasons`  -> `List<SeasonDto>`
///     (`routes/competitions/[id]/seasons/index.dart` GET branch, label order;
///     an absent competition is a legitimate empty array — no existence oracle)
///   * `GET /seasons/{id}/fixtures`      -> `List<SeasonFixtureCardDto>`
///     (`routes/seasons/[id]/fixtures/index.dart` GET branch, display order,
///     each card enriched with its schedule identity — team names + kickoff,
///     all nullable since the season<->fixture link never verifies a
///     schedule exists, Axiom 3; query intent `BrowseSeasonFixtures`, Axiom 4
///     Amendment — the season-scoped sibling of the retired round read; an
///     absent season is a legitimate empty array — no existence oracle)
///
/// All routes are behind `bearerAuth`. The browse reads above are pure (no
/// side effect); [recordFixtureResult] and the other writes below are
/// admin-only commands (authorization enforced server-side inside the
/// use-case, never by this client). Every method returns a typed [Result]
/// and never throws.
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

  /// `GET /months` — the monthly contest seasons, newest first.
  ///
  /// The months an admin files fixtures into. A platform with no month
  /// opened yet is a legitimate `Ok(<empty list>)`, never an error.
  Future<Result<List<SeasonDto>>> listMonthlySeasons() {
    return _transport.getList<SeasonDto>(
      '/months',
      parseElement: SeasonDto.fromJson,
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

  /// `GET /seasons/{id}/fixtures` — the season's fixtures in display order,
  /// each enriched with its schedule identity (team names + kickoff) for the
  /// per-fixture prediction browse read (query intent `BrowseSeasonFixtures`;
  /// Axiom 4 Amendment — the season-scoped sibling of the retired round read,
  /// since a fixture's prediction belongs to its season directly via
  /// `SeasonFixture`, never a round; batched, no N+1).
  ///
  /// A season with no linked fixtures — or one that does not exist — is a
  /// legitimate `Ok(<empty list>)` (the server reveals no existence oracle on
  /// this browse read). `homeTeam`/`awayTeam`/`kickoffAt` are `null` when the
  /// linked fixture has no schedule yet (the link never verifies one exists —
  /// Axiom 3).
  ///
  /// [includeHidden] asks for the fixtures an admin hid as well (migration
  /// 0098) -- the admin panel's list; the server ignores it for a player.
  Future<Result<List<SeasonFixtureCardDto>>> browseSeasonFixtures(
    String seasonId, {
    bool includeHidden = false,
  }) {
    return _transport.getList<SeasonFixtureCardDto>(
      '/seasons/$seasonId/fixtures',
      query: includeHidden ? const {'include_hidden': 'true'} : null,
      parseElement: SeasonFixtureCardDto.fromJson,
    );
  }

  /// `POST /seasons/{id}/fixtures` — links an already-registered fixture
  /// into the season at [displayOrder] (command intent
  /// `LinkFixtureToSeason`; Phase 7.4 — the per-fixture sibling of
  /// the retired round link, Axiom 4 Amendment). Admin-only, enforced inside
  /// the server use-case. Same URL as the season fixtures browse `GET`
  /// (2026-08 decision: no competitionId in the path).
  Future<Result<SeasonFixtureDto>> linkFixtureToSeason({
    required String seasonId,
    required String fixtureId,
    required int displayOrder,
  }) {
    return _transport.postObject<SeasonFixtureDto>(
      '/seasons/$seasonId/fixtures',
      body: {'fixture_id': fixtureId, 'display_order': displayOrder},
      parse: SeasonFixtureDto.fromJson,
    );
  }

  /// `DELETE /seasons/{id}/fixtures/{fixtureId}` — unlinks a fixture from
  /// the season (command intent `RemoveFixtureFromSeason`), the inverse of
  /// [linkFixtureToSeason]. Admin-only, enforced inside the server use-case,
  /// which refuses once the fixture carries any prediction or a recorded
  /// result. Returns `true` when a link was actually removed and `false`
  /// when there was none — both are a success.
  Future<Result<bool>> removeFixtureFromSeason({
    required String seasonId,
    required String fixtureId,
  }) {
    return _transport.deleteObject<bool>(
      '/seasons/$seasonId/fixtures/$fixtureId',
      parse: (json) => json['removed']! as bool,
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

  /// `POST /fixtures/{id}/score` — scores every prediction recorded for the
  /// fixture (command intent `ScoreFixture`; Axiom 4 Amendment — the
  /// per-fixture sibling of the retired round-level `scoreRound`). No request body — points are
  /// computed server-side (Axioms 2/5). Admin-only, enforced inside the
  /// server use-case. Idempotent: re-scoring recomputes the same
  /// deterministic result (upsert on `(fixture_id, participant_id)`).
  Future<Result<FixtureScoresDto>> scoreFixture(String fixtureId) {
    return _transport.postObject<FixtureScoresDto>(
      '/fixtures/$fixtureId/score',
      body: const {},
      parse: FixtureScoresDto.fromJson,
    );
  }

  /// `POST /fixtures/{id}/ledger` — posts a **scored** fixture to the
  /// append-only Ledger (command intent `PostFixtureToLedger`; the
  /// per-fixture sibling of the retired round-level `postRoundToLedger`). No request body.
  /// Admin-only, enforced inside the server use-case. Idempotent:
  /// re-posting an already-posted fixture appends nothing new
  /// (`appended_entries` empty).
  Future<Result<PostFixtureToLedgerResponseDto>> postFixtureToLedger(
    String fixtureId,
  ) {
    return _transport.postObject<PostFixtureToLedgerResponseDto>(
      '/fixtures/$fixtureId/ledger',
      body: const {},
      parse: PostFixtureToLedgerResponseDto.fromJson,
    );
  }

  /// `GET /seasons/{id}/fixtures/{fixtureId}/scores` — reads every
  /// participant's computed score for a fixture (query intent
  /// `GetFixtureScores`; Axiom 4 Amendment — the per-fixture sibling of
  /// the retired round-level `getRoundScores`). Gate is season membership only (Option-3, same
  /// philosophy as [scoreFixture]): an unscored fixture is a legitimate
  /// `Ok(<empty list>)`, never a `409` like the round-scoped read.
  Future<Result<FixtureScoresDto>> getFixtureScores({
    required String seasonId,
    required String fixtureId,
  }) {
    return _transport.getObject<FixtureScoresDto>(
      '/seasons/$seasonId/fixtures/$fixtureId/scores',
      parse: FixtureScoresDto.fromJson,
    );
  }

  /// `GET /me/fixture-scores` -- the caller's own grade, points and final
  /// score for every prediction that has a score or a recorded result, in
  /// one read (query intent `ListMyFixtureScores`, script 75). What the
  /// match cards and the history rows show, in place of one
  /// [getFixtureScores] per match. Nothing scored or recorded yet is a
  /// legitimate `Ok(<empty list>)`.
  Future<Result<List<MyFixtureScoreDto>>> myFixtureScores() {
    return _transport.getList<MyFixtureScoreDto>(
      '/me/fixture-scores',
      parseElement: MyFixtureScoreDto.fromJson,
    );
  }

  /// `GET /me/active-seasons` -- every season the caller is an **active**
  /// participant in, right now (query intent `ListMyActiveSeasons`; Axiom 4
  /// Amendment). The participant-scoped "my seasons" read the client fans
  /// out from, one call per season, to [browseSeasonFixtures]. No active
  /// participation right now is a legitimate `Ok(<empty list>)`, never an
  /// error (e.g. a brand-new user who has not yet made a first prediction).
  Future<Result<List<ActiveSeasonDto>>> myActiveSeasons() {
    return _transport.getList<ActiveSeasonDto>(
      '/me/active-seasons',
      parseElement: ActiveSeasonDto.fromJson,
    );
  }

  /// `GET /competitions/{id}/seasons/current` -- resolves the single
  /// "current" monthly season of the competition, computed fresh against
  /// "now" server-side (query intent `GetCurrentSeason`; never stored).
  ///
  /// A month with no season yet created by the admin is a legitimate
  /// `Ok(null)`, never an error -- the same "no existence oracle"
  /// philosophy as [listCompetitionSeasons] (which returns `[]`, never
  /// `404`), not the "owned resource" philosophy of a `404`-returning read.
  Future<Result<SeasonDto?>> getCurrentSeason(String competitionId) {
    return _transport.getNullableObject<SeasonDto>(
      '/competitions/$competitionId/seasons/current',
      parse: SeasonDto.fromJson,
    );
  }

  /// `GET /feed/current-month-fixtures` -- every public competition's
  /// current-month fixtures, flattened into one ordered list, in a single
  /// request (server-side aggregate read; query intent
  /// `ListCurrentMonthFixtures`, Monthly Competitions transition).
  ///
  /// No public competitions, none with a season currently covering "now",
  /// or none of those seasons having a linked fixture are all legitimate
  /// `Ok(<empty list>)` (no existence oracle).
  Future<Result<List<CurrentMonthFixtureItemDto>>> getCurrentMonthFixtures() {
    return _transport.getList<CurrentMonthFixtureItemDto>(
      '/feed/current-month-fixtures',
      parseElement: CurrentMonthFixtureItemDto.fromJson,
    );
  }
}
