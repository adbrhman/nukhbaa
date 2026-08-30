import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for the Competition context (Application ADR, Section 9:
/// use-cases depend on repository interfaces; Infrastructure implements them).
///
/// Backed by `PostgresCompetitionRepository`. The interface speaks in domain
/// aggregates and typed ids, never in rows or SQL, so use-cases stay pure and
/// testable against an in-memory fake.
///
/// General contract for every method (Application ADR, Section 2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a domain-integrity conflict it can *only* detect at the storage
///   layer (e.g. a uniqueness violation) to [ErrorKind.invariant], so the
///   use-case reports it as a business-rule conflict, not a transient fault.
/// * Writes SHOULD be idempotent where the id is caller-supplied, but the
///   primary idempotency guarantees are asserted by the use-cases and the
///   schema's unique constraints (Database ADR, Section: domain invariants).
abstract interface class CompetitionRepository {
  /// Persists a newly created [competition]. The id is caller-generated; a
  /// duplicate id is an infrastructure-detected conflict surfaced as
  /// [ErrorKind.invariant].
  Future<Result<void>> saveCompetition(Competition competition);

  /// Loads a competition by id, or an [ErrorKind.invariant]
  /// `competition.not_found` error when it does not exist (a command that
  /// references a missing competition is violating a business precondition).
  Future<Result<Competition>> findCompetition(CompetitionId id);

  /// Persists a newly created [season]. Enforces (with the schema) that the
  /// referenced competition exists; a missing competition surfaces as
  /// [ErrorKind.invariant].
  Future<Result<void>> saveSeason(CompetitionSeason season);

  /// Loads a season by id, or an [ErrorKind.invariant] `competition.season_not_found`
  /// error when absent.
  Future<Result<CompetitionSeason>> findSeason(SeasonId id);

  /// Persists a newly opened [round]. The `(seasonId, sequence)` pair is unique;
  /// a duplicate sequence within a season surfaces as [ErrorKind.invariant].
  Future<Result<void>> saveRound(Round round);

  /// Loads a round by id, or an [ErrorKind.invariant] `competition.round_not_found`
  /// error when absent.
  Future<Result<Round>> findRound(RoundId id);

  /// Persists a lifecycle transition for an existing [round].
  ///
  /// Implementations MUST perform a *guarded* update keyed on the expected prior
  /// status ([expectedPriorStatus]) so a concurrent transition cannot be lost
  /// (optimistic concurrency): if the stored status no longer matches, the
  /// update affects no row and the implementation returns an
  /// [ErrorKind.invariant] `competition.round_transition_conflict`. This is the
  /// storage-layer backstop to the domain's `Round.transitionTo` check.
  Future<Result<void>> updateRoundStatus(
    Round round,
    RoundStatus expectedPriorStatus,
  );

  /// Links a fixture to a round (persists a [RoundFixture]). A duplicate
  /// `(roundId, fixture)` link surfaces as [ErrorKind.invariant].
  Future<Result<void>> saveRoundFixture(RoundFixture link);

  /// Removes the `(roundId, fixture)` link, idempotently. Returns `Ok(true)`
  /// when a row was actually deleted, `Ok(false)` when there was nothing to
  /// remove (a retried delete converges rather than erroring — mirrors
  /// `ReactionRepository.removeReaction`). Callers (the
  /// `RemoveFixtureFromRound` use-case) are responsible for the business
  /// preconditions (round still open, no recorded result) — this port is a
  /// pure storage delete with no invariant of its own beyond the row's
  /// presence.
  Future<Result<bool>> deleteRoundFixture({
    required RoundId roundId,
    required FixtureRef fixture,
  });

  /// Persists a new [participant]. The `(seasonId, userId)` pair is unique — a
  /// user joins a season at most once — so a duplicate enrolment surfaces as
  /// [ErrorKind.invariant] `competition.already_joined`.
  Future<Result<void>> saveParticipant(Participant participant);

  /// Finds the participant for `(seasonId, userId)`, or `Ok(null)` when the user
  /// has not joined. Used by the join use-case to make enrolment idempotent and
  /// by later phases to resolve a user's participant.
  Future<Result<Participant?>> findParticipant(
    SeasonId seasonId,
    UserId userId,
  );

  // ---------------------------------------------------------------------------
  // Read-only browse surface (added for the Flutter client's Competition-browse
  // scope — BLOCKER FA-1, 2026-07-13). These are pure list reads over the
  // already-migrated `competition.*` tables; they add no side effect, no new
  // domain rule, and no write path. Existing methods above are untouched.
  //
  // General contract (unchanged from the class doc): every method MUST NOT
  // throw and MUST map an infrastructure failure to [ErrorKind.transient]. An
  // empty result is a legitimate `Ok(<empty list>)`, never an error — "nothing
  // to browse yet" is a normal outcome, distinct from a transport fault.
  // ---------------------------------------------------------------------------

  /// Lists the competitions the client may browse.
  ///
  /// Returns every *public* competition (the discoverable catalogue — private
  /// competitions have no client-facing discovery surface yet; that binding
  /// arrives with a later phase, mirroring the migration's
  /// `competitions_select_public` RLS policy). Ordered by name for a stable,
  /// presentable catalogue. An empty catalogue is `Ok(<empty list>)`.
  Future<Result<List<Competition>>> listCompetitions();

  /// Lists the seasons of a competition, ordered by their display [label]
  /// (then id for a stable, total order).
  ///
  /// A competition with no seasons yet — or one that does not exist — yields
  /// `Ok(<empty list>)` (a browse read reveals no existence oracle beyond what
  /// the caller could already learn from the competition read). Never a
  /// `not_found`.
  ///
  /// Added for the Flutter Competition-browse middle hop (project-context §4,
  /// FA-1 scope closure, 2026-07-13): the domain has no "current/active season"
  /// concept — `CompetitionSeason` carries no status and no singleton rule — so
  /// a multi-season competition must be browsed season-by-season, and the client
  /// needs this list read to discover them. Same additive, read-only contract as
  /// the other browse reads above.
  Future<Result<List<CompetitionSeason>>> listCompetitionSeasons(
    CompetitionId competitionId,
  );

  /// Finds the single-current-season resolution: the season of
  /// [competitionId] whose window contains [nowUtc] ([CompetitionSeason.
  /// isCurrentAt]), or `Ok(null)` when no season currently covers it (e.g. a
  /// new month has begun and the admin has not yet created its season -- a
  /// legitimate operational gap, not an error).
  ///
  /// There is currently no database constraint preventing two seasons of the
  /// same competition from overlapping (a known gap -- a candidate exclusion
  /// constraint has not been added yet). If more than one season matches,
  /// implementations MUST resolve the tie deterministically by the earliest
  /// [CompetitionSeason.startAt] (then id), so behaviour is stable in the
  /// interim rather than implementation-order-dependent.
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  });

  /// Lists the rounds of a season, ordered by their 1-based [Round.sequence].
  ///
  /// A season with no rounds yet — or one that does not exist — yields
  /// `Ok(<empty list>)` (a browse read reveals no existence oracle beyond what
  /// the caller could already learn from the season read). Never a `not_found`.
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId);

  /// Lists the fixtures linked to a round, ordered by
  /// [RoundFixture.displayOrder] (matchday order) — the set a client renders to
  /// build the prediction form. A round with no linked fixtures (or one that
  /// does not exist) yields `Ok(<empty list>)`.
  Future<Result<List<RoundFixture>>> listRoundFixtures(RoundId roundId);

  // ---------------------------------------------------------------------------
  // Live/partial scoring (Phase: احتساب فوري) — resolves every round a given
  // fixture belongs to, so recording that fixture's actual result can
  // immediately re-score each of those rounds rather than waiting for the
  // whole round to lock. Additive, read-only; same total/never-throws
  // contract as every other browse read above.
  // ---------------------------------------------------------------------------

  /// Lists the ids of every round [fixture] is linked to (a fixture may
  /// belong to more than one round/competition — Axiom 3). Ordered by round
  /// id for a stable, deterministic result. A fixture linked to no round
  /// yields `Ok(<empty list>)`, never an error.
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture);

  // ---------------------------------------------------------------------------
  // Participant-scoped season feed (isolated read layer — first step toward
  // a "my seasons" mobile read; the client fans out to the existing
  // `listSeasonRounds`-analogue `BrowseSeasonFixtures` read per season it
  // returns). Additive, read-only; no use-case/route/mobile wiring lands with
  // this method.
  // ---------------------------------------------------------------------------

  /// Lists every season [userId] is an **active** ([ParticipantStatus.active])
  /// participant in, whose calendar window currently covers [nowUtc]
  /// ([CompetitionSeason.isCurrentAt]), joined with the owning competition's
  /// display name — the row shape a "my seasons" feed needs in one query.
  ///
  /// Ordered by competition name (then id, tie-break), then season label
  /// (then id) — mirrors [listOpenRoundsFeed]'s grouping/order contract. A
  /// user with no active participation currently covered by any season's
  /// window yields `Ok(<empty list>)`, never an error — a legitimate "not in
  /// any season right now" outcome (e.g. a brand-new user who has not yet
  /// made a first prediction, since `FixturePredictionController` auto-joins
  /// only on that first successful submission).
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  });
}
