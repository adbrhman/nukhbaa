# Nukhba Platform — Project Context (Single Source of Truth)

_Consolidated: 2026-07-09. This file replaces docs/adr/*, docs/progress.md,
docs/next-task.md, and docs/version-verification.md as the ONLY project memory.
Do not read any other doc file unless explicitly requested._

---

## 1. Project Identity

- **Name:** Nukhba Platform (`نُخبة`) — football predictions, social-first.
- **Repo:** `/home/user/nukhba/` (monorepo). Docs: `/home/user/nukhba/docs/`.
- **Stack:** Backend = Dart Frog · Monorepo tool = Melos · CI/CD = GitHub Actions ·
  DB = Supabase PostgreSQL · Client = Flutter (latest stable at build time).

### Ratified Axioms (ADR 0001)
1. **Social-first** — competition among friends/communities drives engagement;
   accuracy serves the social layer, not the reverse.
2. **Private groups are first-class** from the architectural root.
3. **Football-focused**, with one deliberate abstraction seam for how a
   fixture's result is represented (no general "sports" platform today).
4. **Predict once, rank everywhere (Model B)** — one prediction per fixture,
   reused across all ranking contexts. **(AMENDED — see Axiom 4 Amendment
   below: "round" as a scoring/locking unit is removed; the calendar month
   is now the ranking aggregation window, and each fixture locks/scores
   individually at its own kickoff.)**
5. (Ledger/points) — points are a virtual-value instrument; the competitive
   record is the asset to protect (drives Security ADR).
6. **The database is the last line of defense, not the first** — application
   enforces invariants; DB triggers/permissions are the backstop.

#### Axiom 4 Amendment — Round removed, monthly competition (decided, in progress)

- **Removed unit:** `Round` (and `RoundFixture`) as a scoring/locking
  aggregate is eliminated. No more `open_round` / `lock_round` /
  `link_fixture_to_round`.
- **New unit:** `Fixture` locks and scores individually at its own
  `kickoff_at`. `ScoreFixture` replaces `ScoreRound`.
- **Prediction key:** `(fixture_id, participant_id)` replaces
  `(round_id, participant_id)`.
- **Ranking:** monthly aggregation = sum of `PointEntry` rows whose
  `fixture.kickoff_at` falls in the same calendar month, per
  `CompetitionSeason`. This is a query/read-model, not a new stored
  entity.
- **Migration:** historical `round` / `round_fixture` data is archived,
  not dropped. Existing `predictions` / `point_entries` are relinked to
  `fixture_id` directly in one migration.
- **Double pick rule:** the old "at most one double per round" invariant
  cannot survive inside a single `Prediction` aggregate once each fixture
  is its own independent prediction. Decided: **at most one double per
  calendar day (UTC)** -- superseded 2026-10-02 by the **Riyadh
  calendar day** of the fixture's kickoff (migration 0083), the day the
  app shows and the daily challenge uses. This is NOT a domain-entity
  invariant anymore -- it must be enforced in the `application` layer at
  submit/amend time via a repository query (count existing
  `isDouble = true` predictions for that participant on that Riyadh
  calendar day), because predictions for a
  single day arrive as separate, independent submissions over time, not
  as one atomic batch the way a round's predictions used to.
- **`Prediction` aggregate reshaped:** was "one prediction per round,
  containing N `FixtureScorePrediction` children" (one per fixture in the
  round, submitted atomically). Becomes "one prediction per fixture",
  keyed by `(fixture_id, participant_id)`. `FixtureScorePrediction` and
  `Prediction` effectively merge into one per-fixture entity carrying its
  own `isDouble` flag, validated against the daily count above.
- **New link entity:** `SeasonFixture` (season_id, fixture_id,
  display_order) directly links `CompetitionSeason` to `Fixture`,
  replacing the round-mediated `RoundFixture`. Required because without
  `Round` there was no remaining path from a fixture back to its
  season/competition.
- **Status:** design approved; implementation in progress layer by layer
  (domain -> application -> infrastructure/migration -> contracts ->
  server routes -> mobile). Do not assume completion elsewhere in this
  document until this note is removed/updated.

##### Decisions — 2026-08-30 (post Phase 2 close)

- **Dual scoring-path risk (`PUT /fixtures/{id}/result` auto-triggering the
  legacy `ScoreRound` path in parallel with the manual
  `POST /fixtures/{id}/score` -> `ScoreFixture` path):** decision is to
  **defer**, not fix now. No current read joins `point_entries` and
  `fixture_point_entries`, so the risk is latent, not active, and `Round`
  is still live in 9+ non-test files — decoupling now would risk breaking
  Round before its real removal is scheduled. **Binding condition:** the
  real Round deletion (7.10) MUST NOT begin until `PUT /fixtures/{id}/result`
  no longer auto-triggers `ScoreRound`.
- **Dual scoring-path risk — RESOLVED (2026-08-30, same-day follow-up):**
  Option C first added `ScoreFixture` to `PUT /fixtures/{id}/result`
  alongside the legacy `ScoreRoundsForFixture` call (both ran, in parallel).
  With every `open`/`locked` round subsequently cleared (fresh Monthly
  Competitions relaunch — no legacy round data retained), the binding
  condition above is now literally satisfied: the `ScoreRoundsForFixture`
  call was removed from `PUT /fixtures/{id}/result` (route + its tests
  only). `ScoreRoundsForFixture`/`ScoreRound` and their
  `composition_root.dart` wiring are left in place, now with zero route
  consumers — same transitional pattern as `round_report.dart`. **7.10
  (real Round deletion) may proceed.**
- **Work that jumped the locked Phase 7 order** (admin monthly-competitions
  section, `ListMyActiveSeasons`/`MyActiveSeasonsScreen`,
  `ListCurrentMonthFixtures`/`CurrentMonthFixturesScreen`): **ratified as an
  official extension of 7.10.x**, not frozen/rolled back. It does not touch
  the `Round` layer, ships with tests, and reverting it would discard
  correct, already-verified work for no architectural benefit.
- **Legacy `Round` predictions in `prediction_history_screen.dart` —
  RESOLVED (2026-08-31):** the app has not launched yet (roadmap is still
  at the pre-launch Build Verification gate, ADR 0008), so there are no
  external users whose history must be preserved. Decision: **drop the
  Round-based prediction history from the screen entirely** — no data
  migration, no permanent dual display. This removes the last live
  consumer blocking full `Round` layer deletion. Next: strip
  `myPredictions` / `getRoundScores` / `roundFixturesProvider` /
  `RoundPredictionEntry` out of `prediction_history_screen.dart` and its
  providers (the screen keeps only `FixturePredictionDto`), then delete
  the resulting orphaned Round symbols.

### Core Architecture (ADR 0002)
Layered, event-driven, strict integrity boundary:
```
CLIENT (Flutter) — presentation/state/read models only, never computes points
   │ HTTPS typed contracts
APPLICATION/EDGE (Dart Frog backend) — auth verification, use-cases, business
   rules. ONLY place integrity-critical writes are authorized.
   │ in-process calls + Event Bus
DOMAIN (pure, framework-free) — entities, invariants, scoring, policies
   │ repository interfaces
INFRASTRUCTURE — Postgres (truth), Event Store, Read Projections, Cache,
   Supabase Auth, Realtime (Tier-3 only)
```

### Database (ADR 0003) — key aggregates
Identity (`User`) · Community (`Group`) · Football Data (`Fixture` /
`FixtureResult` separate aggregates) · Competition (`Competition` →
`CompetitionSeason` → `Round`) · Participant · Prediction (separate from
Competition for scale) · Ledger (append-only `PointEntry` stream; balance is a
projection).

### API Contracts (ADR 0004)
Use-case API (not tables-over-HTTP), command/query separated. Every command:
speaks in domain intents (`SubmitPrediction`, not raw inserts), is
server-authorized against business invariants, is idempotent/safely retryable,
and returns DTOs decoupled from schema. Contracts live in shared
`packages/contracts` (compile-checked client+server).

### Security (ADR 0005)
Three trust zones: **client untrusted**, **backend fully trusted** (holds
service role, bypasses RLS, bears full invariant-enforcement responsibility),
**Supabase trusted-managed** (client-facing surfaces treated as untrusted,
guarded by RLS). Because backend bypasses RLS, defense is layered: app checks →
DB triggers/permission revocation as last line.

### Platform (ADR 0006)
Flutter client (PWA+mobile) + stateless Dart backend behind a load balancer +
outbox dispatcher (separate worker, leader election) + Supabase. Three
environments (dev/staging/prod), isolated Supabase project each, forward-only
migrations, expand-contract discipline for prod.

### Coding Standards (ADR 0007)
Clean Architecture dependency rule **enforced by CI** (`tooling/import_lint`):
domain imports nothing outside shared kernel; application imports domain only;
no cross-context internal imports; client cannot import integrity-critical
use-cases. A violating import fails the build. Invariants encoded as types
where possible (illegal states unrepresentable).

### Roadmap / Milestones (ADR 0008) — ratified order
```
Phase 1: Infrastructure/Backend Foundation/DB Migrations ✅ COMPLETE
   ↓
Authentication ✅ COMPLETE
   ↓
Competition ✅ COMPLETE
   ↓
Prediction Engine ✅ COMPLETE
   ↓
Scoring ✅ COMPLETE
   ↓
Ledger ✅ COMPLETE
   ↓
Leaderboards ✅ COMPLETE
   ↓
Groups ✅ COMPLETE
   ↓
Social ✅ COMPLETE
   ↓
Notifications ✅ COMPLETE
   ↓
Admin Panel ✅ COMPLETE & RATIFIED (six-way review GREEN,
   ↓            `docs/reviews/admin-panel-review.md`, 2026-07-13; DEFECT AD-1
   ↓            fixed, AD-2 dartdoc fixed; exit criterion met — see §2)
Flutter App 🟡 CODE COMPLETE, GREEN review, platform scaffolding DONE
   ↓            (`apps/mobile/{android,ios,web}/` all verified present,
   ↓            2026-07-15) — but real `flutter analyze`/`flutter test`/
   ↓            `flutter build` output is still not recorded anywhere. See
   ↓            §4 for the exact remaining steps.

**ROADMAP: 12/12 phases ARCHITECTURALLY COMPLETE, platform scaffolding
PHYSICALLY DONE. Launch-readiness gate (Build Verification, real toolchain
output recorded) is the one remaining item before "12/12, physically
verified" — see §4 for its exact scope. Do not reopen any of the 12 phases.**
```

> **Note (2026-10-17, audit NUKHBA-011):** the status block above is as of
> 2026-07-15. Today `apps/mobile/android/` is not tracked (`.gitignore`):
> Build Verification generates it with `flutter create --platforms=android`
> on every push (`.github/workflows/build-verification.yml`), and the same
> workflow runs the real `flutter analyze`, `flutter test` and
> `flutter build`. There is no `ios/` and no iOS build; `web/` is tracked.

Rules: each phase 100% complete before the next; full six-way review
(architecture, security, correctness, performance, maintainability,
production-readiness) after every phase, all issues fixed before moving on; no
architecture changes without approval; no placeholders/shortcuts; verify every
library/API version before use.

---

## 2. Progress

**Architecture phase:** COMPLETE & RATIFIED — all 8 ADRs above are final SSoT.

**Milestone 0 — Foundation Setup: COMPLETE & RATIFIED (green)**
Verified toolchain: Dart `^3.9.0`, Melos `^8.0.0` (config under `melos:` key in
root `pubspec.yaml`), Dart Frog `1.2.6`, `postgres 3.5.12`, `lints ^6.0.0`,
`test ^1.26.0`, Flutter pin `3.44.0` (`.fvmrc`).

Delivered (verified-by-construction):
- Pub workspace + Melos scripts (`analyze`, `format-check`, `test`,
  `import-lint`, `verify`).
- `packages/shared` — `Result`/`Ok`/`Err`, `AppError`+`ErrorKind` (4 classes),
  `EntityId`. Tested.
- `packages/domain` — pure `HealthStatus` + `HealthCheck.fromSignals`. Tested.
- `packages/contracts` — `HealthResponseDto` (schemaVersion, JSON round-trip).
- `packages/application` — `HealthRepository` port + `CheckHealth` use-case
  (graceful degrade on transient DB error). Tested w/ in-memory fake.
- `packages/infrastructure` — `PostgresConfig.fromEnv`, `PostgresConnection`
  (pool, eager `SELECT 1`, ping, close), `PostgresHealthRepository`.
  Integration test tagged & DB-gated.
- `apps/server` (Dart Frog) — `CompositionRoot` (cached bootstrap,
  `forTesting`, `reset`), `_middleware.dart` (requestLogger + security headers
  + CompositionRoot provider), `routes/health.dart` (200/503/405), route tests
  via mocktail, `Dockerfile` (multi-stage).
- `tooling/import_lint` — pure `lintWorkspace()`, CLI entry, unit test.
- CI: `.github/workflows/ci.yaml` (verify + integration w/ ephemeral Postgres)
  and `import_lint.yaml`.

**Exit criterion met:** dependency rules enforced in CI; trivial use-case flows
client-caller → route → use-case → port → Postgres adapter → `SELECT 1`.

Known carried-forward items (not blockers):
- Dockerfile `dart_frog build` path inside a pub-workspace needs one real
  `docker build` confirmation on a machine with the Dart toolchain.
- No auth middleware yet — deferred to Authentication phase (current task);
  `_middleware.dart` marks where it goes.

**Environment note:** sandbox has no Dart/Flutter toolchain — verification is
by-construction + version-checking against upstream sources (see §3).
"Compiles & goes green" confirmed via `melos bootstrap && melos run verify` on
a machine with Dart 3.12+.

**Milestone (Authentication) — COMPLETE & RATIFIED (green, 2026-07-09)**
Full Milestone-0 rigor. Delivered end-to-end and reviewed six ways
(`docs/reviews/authentication-review.md`):
- `packages/domain/identity` — `UserId` (UUID-validated), `PlatformRole`
  (user/admin/service, closed-set parse), `UserStatus`, `User`,
  `AuthenticatedUser` (role hierarchy defined once via `hasRole`). Tested.
- `packages/contracts` — `AuthenticatedUserDto`, `MeResponseDto` (versioned,
  schema-decoupled, no token material), `ErrorResponseDto`. Tested (round-trip).
- `packages/application/identity` — ports `TokenVerifier`, `UserDirectory`
  (idempotent-ensure contract); use-cases `AuthenticateRequest` (RFC-7235 Bearer
  parse), `GetCurrentUser`; `Authorization.requireRole`. Tested with fakes
  (valid/expired/wrong-aud/wrong-iss).
- `packages/infrastructure/identity` — `AuthConfig.fromEnv` (typed validation +
  server-owned algorithm allow-list), `JwksClient` (bounded-TTL cache,
  rate-limited refresh-on-unknown-kid), `SupabaseJwtVerifier` (ES256-via-JWKS
  primary + HS256 legacy fallback; asserts sig/exp/nbf/iss/aud; **allow-list
  gate before key selection**), `PostgresUserDirectory` (single upsert,
  platform-owned role/status preserved). Tested (hermetic HS256, JWKS
  parse/cache, allow-list, alg:none/RS256 rejection).
- `apps/server` — `bearerAuth` middleware (scoped to `/me`, not global),
  protected `GET /me`, public `/health`, `error_envelope` (ErrorKind→status in
  one place), `CompositionRoot` (+`forTesting` with absent-slice stand-ins),
  security headers. Route tests: `/me` 200/401, `/health` public.
- **Migration** `supabase/migrations/0001_identity.sql` — `identity.users`
  (PK = auth.users FK, cascade), enums, updated_at trigger, RLS self-read only +
  write-privilege revocation. Forward-only, idempotent.

**Exit criterion met:** auth gate proven end-to-end (client → bearerAuth →
verify → principal → /me → directory → DTO); `/health` stays public; six-way
review GREEN, all found issues fixed (algorithm-confusion hardening applied).

**Milestone (Competition) — COMPLETE & RATIFIED (green, 2026-07-10)**
Full Milestone-0 rigor. Delivered end-to-end and reviewed six ways
(`docs/reviews/competition-review.md`, phase-exit GREEN):
- `packages/domain/competition` — pure aggregate: `Competition` (root) →
  `CompetitionSeason` → `Round`, with `RoundFixture` link and the round's frozen
  `RulesetSnapshot` inside the boundary; `Participant` as a separate aggregate;
  ids (`CompetitionId`, `SeasonId`, `RoundId`, `ParticipantId`); enums
  (`FormatType`, `CompetitionVisibility`, `RoundStatus`, `ParticipantStatus`);
  `FixtureRef`. Invariants encoded as types (Axiom 3: fixture carries no
  competition ref — bound only via `RoundFixture`; Axiom 4: round carries no
  group ref). 7 domain test files.
- `packages/contracts` — `competition_dto.dart` (versioned, schema-decoupled
  read/command DTOs). Round-trip tested (`competition_dto_test.dart`).
- `packages/application/identity`… — `packages/application/competition` ports
  (`CompetitionRepository`, `RulesetProvider`) + use-cases
  (`create_competition`, `start_season`, `open_round`, `lock_round`,
  `link_fixture_to_round`, `join_competition` — server-authorized, idempotent,
  reuse `Authorization.requireRole`). Shared `IdGenerator`/`Clock` ports under
  `common/`. 6 use-case tests + fakes.
- `packages/infrastructure/competition` — `configured_ruleset_provider.dart` and
  the real `postgres_competition_repository.dart` (reuse `PostgresConnection`;
  SQLSTATE→typed error mapping: `23505`/`23503`/`23514`). Hermetic +
  DB-gated integration tests.
- `apps/server` — protected routes behind `bearerAuth`: `competitions/`
  (`index`, `_middleware`), `competitions/[id]/seasons/`, `seasons/[id]/rounds/`,
  `seasons/[id]/participants/`, `rounds/[id]/lock/`, `rounds/[id]/fixtures/`.
  Route tests via harness (`competitions_index_test`, `competition_seasons_test`,
  `season_rounds_test`, `season_participants_test`).
- **Migration** `supabase/migrations/0002_competition.sql` — competition,
  season, round, round_fixture link, participant tables + frozen
  `ruleset_snapshot`; DB ADR §2.3 relationships & §2.4 constraints (Round has NO
  group ref — Axiom 4; Fixture has NO competition ref — Axiom 3); RLS per §2.10;
  reuses `identity.set_updated_at` from 0001. Forward-only, idempotent.

**Exit criterion met:** Competition + Participant delivered end-to-end;
Axioms 3/4/6 honoured physically in schema; six-way review GREEN with all found
issues fixed (C-1 broken-test fix, C-2 doc/behaviour correction; S-note/M-note
recorded as info-only, ADR-gated). No new external dependency introduced.

**Milestone (Prediction Engine) — COMPLETE & RATIFIED (green, 2026-07-11)**
Full Milestone-0 rigor. Delivered end-to-end across all layers (domain →
contracts → application → infrastructure → migration 0003 → `apps/server`
routes) and reviewed six ways (`docs/reviews/prediction-review.md`, phase-exit
GREEN). Two defects found and fixed at review:
- **C-1 (High — data integrity):** the prediction adapter's multi-statement
  writes (`save` = parent + N child inserts; `update` = parent update + child
  delete + N inserts) were separate autocommit statements — a mid-write failure
  could persist a half-written forecast (corrupting the competitive record,
  Axiom 5). Fixed by widening `packages/infrastructure/lib/src/db/
  postgres_connection.dart` with a narrow `DbExecutor` interface +
  `runInTransaction` (real `postgres 3.5.x` `Pool.runTx`; total — never throws;
  rolls back on `Err` via a private `_RollbackSignal`, preserving the
  SQLSTATE→invariant reclassification so `SubmitPrediction`'s lost-race pivot on
  `prediction.already_submitted` still works) + a private `_TxExecutor`; `save`
  /`update` reworked to run atomically (`_insertScores(tx, …)`). Both
  `PostgresConnection` test fakes (competition + prediction infra) gained a
  faithful `runInTransaction` passthrough. No new package; `import_lint`
  unchanged.
- **C-2 (Medium — status/API):** `GET /rounds/{id}/predictions` for a
  joined-but-not-yet-predicted caller mapped `prediction.not_found`
  (an `invariant`) to 409 via `errorResponse`, contradicting the intended 404
  (the route test asserts 404). Fixed by building the 404 directly in the
  `GET`-mine handler (body still the versioned `ErrorResponseDto`) — mirroring
  the Competition-phase discipline of not adding an ADR-gated `ErrorKind` value.

**Exit criterion met:** submission + read of predictions delivered end-to-end;
Axioms 2/3/4/5/6 honoured physically; six-way review GREEN with all found issues
fixed. One further use of the already-pinned `postgres 3.5.x` (transactions)
recorded in §3; no new external dependency.

**Prediction Engine — delivery record (per-file, 2026-07-10/11):**
- `packages/domain/prediction` + `packages/domain/test/prediction` — DONE
  (delivered in a prior session; unchanged this session).
- `packages/contracts` — `src/prediction_dto.dart` (exported) DONE; added
  `test/prediction_dto_test.dart` (round-trip, back-compat default, snake_case
  keys, no participant/points leakage, order-significant equality).
- `packages/application/prediction` — DONE this session:
  `ports/prediction_repository.dart` (find/save/update/listByRound +
  `listRoundFixtures` read so the frozen Competition port stays untouched);
  `submit_prediction.dart` (`SubmitPrediction` + `FixtureScoreInput`;
  server-resolves participant from principal + round.seasonId; enforces
  round-open, fixture-in-round, exact-completeness; idempotent insert/amend with
  concurrent-race convergence); `get_my_prediction.dart` (`GetMyPrediction`,
  self-read any status, null when not-yet/non-participant);
  `list_round_predictions.dart` (`ListRoundPredictions`, visibility-gated to
  locked/scored + season-membership). All exported from `application.dart`.
  Tests: `test/prediction/fake_prediction_repository.dart`,
  `submit_prediction_test.dart` (12 cases), `get_my_prediction_test.dart`
  (5), `list_round_predictions_test.dart` (5). No new internal package →
  `tooling/import_lint` ruleset unchanged (application→domain/shared only).
- `packages/infrastructure/prediction` — DONE this session:
  `src/prediction/postgres_prediction_repository.dart` implements the full
  `PredictionRepository` port over new `prediction.*` tables + a read-only
  projection of `competition.round_fixtures`. `findByRoundAndParticipant`
  (parent+children single round-trip, order-significant rebuild, Ok(null) on
  absence), `save` (parent insert + per-fixture child inserts, list-position
  `display_order`), `update` (RETURNING-guarded parent refresh → delete+reinsert
  children; empty → `prediction.not_found`), `listByRound` (flat-join grouping,
  submitted_at→id→display_order ordering), `listRoundFixtures`. SQLSTATE→typed
  mapping: `23505` `predictions_participant_round_uniq` →
  `prediction.already_submitted` (the code SubmitPrediction pivots on), `23503`
  FKs → `round_not_found`/`not_a_participant`, `23514` (no-write-after-lock
  trigger) → `prediction.round_not_open`, goal-range check →
  `prediction.integrity_violation`; row-corruption → transient
  `prediction.row_corrupt`. Exported from `infrastructure.dart`. Tests:
  `test/prediction/postgres_prediction_repository_test.dart` (hermetic, fake
  connection, 16 cases across all 5 methods) +
  `postgres_prediction_repository_integration_test.dart` (DB-gated, tagged
  `integration`, documents the constraint/trigger scenarios CI exercises).
- **Migration** `supabase/migrations/0003_prediction.sql` — DONE this session:
  `prediction` schema; `prediction.predictions` (unique `(participant_id,
  round_id)` = physical "predict once"; FKs to round/participant `on delete
  restrict`; no group ref, no points — Axioms 4/2/5); `prediction.prediction_scores`
  (child, `on delete cascade`; goal `[0,99]` checks mirroring
  `FixtureScorePrediction.maxGoals`; composite PK `(prediction_id, fixture_id)`;
  fixture_id opaque, no FK — Axiom 3); `reject_write_after_lock` trigger
  (INSERT/UPDATE rejected unless round `open`, `check_violation` — Axiom 6);
  reuses `identity.set_updated_at`; RLS = own-or-locked read, all client writes
  revoked, anon denied. Forward-only, idempotent.
  `tooling/import_lint` ruleset unchanged (infrastructure→application/domain/shared
  already permitted; no new internal package).
- `apps/server` (Prediction routes + CompositionRoot wiring) — **DONE
  (2026-07-11, this session).** The `submittedAt` blocker was already resolved
  by STEP 0 (`PredictionView`); routes proceeded on that.
  - `apps/server/lib/composition/composition_root.dart` — extended: private
    ctor + `bootstrap` now build `PostgresPredictionRepository` and wire the
    three use-cases `SubmitPrediction` (reusing `competitionRepository` +
    `UuidIdGenerator` + `SystemClock`), `GetMyPrediction`, `ListRoundPredictions`
    as fields; `forTesting` gained matching optional params with loud "absent"
    stand-ins backed by a single shared `_UnwiredPredictionRepository`
    (full port, every method throws `StateError`).
  - `apps/server/lib/http/prediction_dto_mapper.dart` — new; single
    `predictionViewToJson(PredictionView)` shaping a `PredictionView` →
    versioned `PredictionDto` (no points/score field ever; `submitted_at` from
    the view, never fabricated; scores echo stored list order). Shared by both
    read surfaces.
  - `apps/server/routes/rounds/[id]/predictions/index.dart` — `POST` submit
    (body parsed defensively → `List<FixtureScoreInput>`; participant resolved
    server-side inside the use-case, never from body) → `200` `PredictionDto`;
    `GET` my-prediction → `200`, or `404 prediction.not_found` when
    `Ok(null)` (chosen resource-not-found convention, so the client
    distinguishes "nothing submitted yet" from a transport error). `405` on
    other methods.
  - `apps/server/routes/rounds/[id]/predictions/all.dart` — `GET` list;
    visibility gate + membership live entirely in `ListRoundPredictions`
    (`401 prediction.round_not_locked` for an open round;
    `401 prediction.not_a_participant`); returns a JSON array of
    `PredictionDto`.
  - **No local `predictions/_middleware.dart`** — `rounds/_middleware.dart`
    already applies `bearerAuth()` to the whole `/rounds` subtree (STEP 5 was a
    deliberate NO-OP, as §4 required).
  - `apps/server/test/routes/competition_route_harness.dart` — added
    `InMemoryPredictionRepository` (one-per-`(round,participant)`; `save`
    rejects a dup with the pivot `prediction.already_submitted`; `update`
    refreshes in place; `listByRound` submitted_at→id ordering;
    `listRoundFixtures` from an injected link set; keeps each row's stamped
    instant so reads rebuild a faithful `PredictionView`).
  - `apps/server/test/routes/round_predictions_test.dart` — new; real wiring
    over the two in-memory repos. POST: submit-200, amend-in-place-still-one-row,
    incomplete-forecast-400, locked-round-409, non-participant-409,
    missing-field-400, 405. GET mine: 404-when-none, 200-after-submit. GET all:
    open-round-401-gated, locked-round-returns-list, non-participant-401.

**Milestone (Scoring) — COMPLETE & RATIFIED (green, 2026-07-11)**
Full Milestone-0 rigor. Delivered end-to-end across all six layers (domain →
contracts → application → infrastructure → migration `0004_scoring.sql` →
`apps/server` routes + route tests + CompositionRoot wiring) and reviewed six
ways (`docs/reviews/scoring-review.md`, phase-exit GREEN). Product decision:
the actual-result seam is **option (a)** — a minimal `FixtureResult` value
object behind the single Axiom-3 football seam (APPROVED & MANDATORY). The
six-way review (2026-07-11, auditor role, by direct on-disk inspection of every
Scoring file across all layers) found **no High or Medium defect**; all
findings are info/low and were either verified already-satisfied by the code or
explicitly deferred with rationale:
- **A-1 (Info):** `ScoreRound` passes the whole round's result set to
  `Scoring.scoreRound` per prediction, relying on the Prediction phase's
  complete-forecast rule (`prediction.scores.length ==` round fixture count) so
  the domain's `results.length == prediction.scores.length` check holds. A
  cross-phase coupling — safe today (Axiom 4), documented so a future
  partial-forecast change knows to project the per-prediction result subset.
- **C-1 (verified OK):** `PUT /fixtures/{id}/result` derives the fixture from
  the path `id` only; the body carries no `fixture_id` (cannot be smuggled).
- **C-2 (verified OK):** re-score deletes all child rows for
  `(round, participant)` and reinserts inside one transaction — no stale child
  survives a re-score.
- **P-1 (Low, deferred):** `saveRoundScores` issues per-participant sequential
  child inserts (no multi-row batching). Fine at current scale; a localized,
  ADR-neutral optimization if a future scale phase shows it hot.
- **M-1 (Info):** the two RLS select policies share an identical
  `scored + season-membership` subquery — intentional (per-table policy; avoids
  a `security definer` helper's attack surface), matches the prediction
  migration's style.

**Exit criterion met:** scoring delivered end-to-end (admin ingests actual
result → admin scores a locked round server-side under the frozen ruleset →
participants read a scored round's scores); Axioms 2/3/4/5/6 honoured
physically (server-only points, single football seam keyed by opaque
`FixtureRef`, one score per `(round, participant)`, reproducible-by-frozen-
ruleset, DB backstops = range checks + unique key + `reject_score_before_lock`
trigger + RLS). No new external dependency (reuses `postgres 3.5.12` incl.
`runInTransaction`, and `dart_frog 1.2.6`); `tooling/import_lint` ruleset
unchanged (no new internal package). Six-way review GREEN.

**Delivery record (per-file, 2026-07-11) — verified on disk this session:**
- `packages/domain/scoring/` — DONE (pure, framework-free, imports
  only `shared` + domain-internal; import_lint ruleset unchanged):
  - `src/scoring/fixture_result.dart` — `FixtureResult` (actual scoreline behind
    the Axiom-3 seam; same home/away shape as a prediction, keyed by
    `FixtureRef`; `create`/`fromStored`; `maxGoals`=99 matching
    `FixtureScorePrediction.maxGoals`; derived `outcome`) + `MatchOutcome` enum
    (`homeWin`/`draw`/`awayWin` with `fromGoals`).
  - `src/scoring/scoring_ruleset.dart` — `ScoringRuleset` (typed interpretation
    of a round's frozen `RulesetSnapshot`; parses the exact
    `ConfiguredRulesetProvider` payload → `exactScorelinePoints`/
    `correctOutcomePoints`/`incorrectPoints`; validates format, integer/
    non-negative awards, and monotonicity `exact >= outcome >= incorrect`).
  - `src/scoring/fixture_score_result.dart` — `FixtureScoreGrade` enum
    (`exactScoreline`/`correctOutcome`/`incorrect`, wire tokens + `tryParse`) +
    `FixtureScoreResult` (per-fixture grade + points, server-computed read value).
  - `src/scoring/round_score.dart` — `RoundScore` aggregate (per (participant,
    round); `fromGraded` sums points, `fromStored` rehydrates; unmodifiable
    fixture list; carries `rulesetVersion`; no group ref — Axiom 4).
  - `src/scoring/scoring.dart` — `Scoring.scoreRound` pure domain service:
    total/deterministic; grades most-specific-first (exact → outcome →
    incorrect); refuses missing/extra/duplicate results (Axiom 5 integrity —
    `result_count_mismatch`/`duplicate_result`/`result_missing_for_fixture`);
    preserves prediction fixture order.
  - All 5 exported from `domain.dart`.
  - Tests: `test/scoring/fixture_result_test.dart`,
    `scoring_ruleset_test.dart`, `fixture_score_result_test.dart` (via
    `round_score_test.dart`), `round_score_test.dart`, `scoring_test.dart`
    (grading matrix, determinism, result-set integrity). Mirror the
    competition/prediction domain-test style.
- `packages/contracts` — DONE 2026-07-11: `src/scoring_dto.dart` (exported from
  `contracts.dart`). Read-only surface (Axioms 2/5: no command DTO, no
  client-submitted/computed points): `FixtureScoreResultDto` (fixtureId + grade
  wire-token `exact_scoreline`/`correct_outcome`/`incorrect` + points),
  `RoundScoreDto` (roundId/participantId/rulesetVersion/totalPoints + ordered
  fixtureResults; versioned, snake_case, order-significant equality; no group
  ref — Axiom 4), `RoundScoresDto` (roundId + list of RoundScoreDto, the
  whole-round read). Test `test/scoring_dto_test.dart` (round-trip, snake_case
  keys, back-compat default schema_version, order-significant equality,
  no rank/prediction leakage). No new external dependency.
- `packages/application/scoring` — DONE 2026-07-11 (imports domain/shared only;
  `tooling/import_lint` ruleset unchanged — `application → {domain, shared}`):
  - `ports/fixture_result_repository.dart` — `FixtureResultRepository` (option
    (a) actual-result seam): `upsert(FixtureResult, recordedAt)` (idempotent per
    fixture), `findByFixture`, `findByFixtures` (batch; absent fixtures omitted
    so the use-case detects a gap by count).
  - `ports/score_repository.dart` — `ScoreRepository`: `saveRoundScores`
    (atomic all-or-nothing, idempotent upsert per (round,participant)),
    `listByRound` (participant-id ordered).
  - `record_fixture_result.dart` — `RecordFixtureResult` (admin-only ingestion;
    validates id + scoreline via `FixtureResult.create`; idempotent upsert).
  - `score_round.dart` — `ScoreRound` (admin; precondition round is
    `locked` or already `scored` (idempotent replay), refuses `open`
    `scoring.round_not_locked`; interprets frozen snapshot via
    `ScoringRuleset.fromSnapshot`; reads round fixtures + requires one actual
    result per fixture `scoring.results_incomplete`; runs pure
    `Scoring.scoreRound` per prediction; persists all scores atomically then
    transitions `locked → scored` under the guarded update; replay on `scored`
    re-persists identical scores without a spurious transition conflict).
  - `get_round_scores.dart` — `GetRoundScores` (participant read; gated to
    `scored` round `scoring.round_not_scored`; season-membership required
    `scoring.not_a_participant`).
  - All exported from `application.dart`. Tests under `test/scoring/`:
    `fakes.dart` (FakeFixtureResultRepository, FakeScoreRepository + builders),
    `record_fixture_result_test.dart` (6), `score_round_test.dart` (11: grading
    matrix, order, admin-gate, open-refused, locked→scored, idempotent re-score,
    incomplete-results, no-fixtures, no-predictions, corrupt-ruleset, transient),
    `get_round_scores_test.dart` (5). No new external dependency.
- `packages/infrastructure/scoring/` — DONE (verified on disk 2026-07-11):
  - `src/scoring/postgres_fixture_result_repository.dart` (211 lines) —
    `PostgresFixtureResultRepository` over `scoring.fixture_results`: `upsert`
    (`ON CONFLICT (fixture_id) DO UPDATE`, idempotent correction; stamps
    `recorded_at`), `findByFixture` (Ok(null) when absent), `findByFixtures`
    (`WHERE fixture_id = ANY(@fixture_ids)` batch; absent fixtures omitted).
    `23514` check-violation → `scoring.result_integrity_violation`; malformed
    row → transient `scoring.row_corrupt`. All `@named`-bound.
  - `src/scoring/postgres_score_repository.dart` (344 lines) —
    `PostgresScoreRepository` over `scoring.round_scores` +
    `scoring.round_score_fixtures`. `saveRoundScores` writes all parents +
    children in ONE `PostgresConnection.runInTransaction` (Axiom 5, atomic;
    parent `ON CONFLICT (round_id, participant_id)` upsert + child
    delete/reinsert in `display_order`); short-circuits `Ok(null)` on empty.
    `listByRound` single flat JOIN, grouped by participant (participant-id then
    `display_order` ordered). SQLSTATE `23503` mapped by the EXPLICITLY named FK
    constraints → `scoring.round_not_found` / `scoring.not_a_participant`; other
    integrity codes → `scoring.integrity_violation`; malformed/empty rows →
    `scoring.row_corrupt`.
  - Both exported from `infrastructure.dart`. Tests: hermetic
    `test/scoring/postgres_scoring_repositories_test.dart` + DB-gated
    `postgres_scoring_repositories_integration_test.dart`. No new external
    dependency (reuses `postgres 3.5.12` incl. `runInTransaction`);
    `import_lint` ruleset unchanged.
- **Migration** `supabase/migrations/0004_scoring.sql` — DONE (verified on disk
  2026-07-11, 327 lines): `scoring` schema; `scoring.fixture_results` (opaque
  `fixture_id` PK, no FK — Axiom 3; goal-range `[0,99]` checks mirroring
  `FixtureResult.maxGoals`; `recorded_at` audit; reuses `identity.set_updated_at`);
  `scoring.round_scores` (one row per `(round_id, participant_id)` unique —
  Axiom 4; FKs to round/participant `on delete restrict`, named explicitly for
  the adapter's 23503 mapping; `total_points`/`ruleset_version` non-neg/pos
  checks; no group ref); `scoring.round_score_fixtures` (child, composite PK
  `(round_id, participant_id, fixture_id)`, parent FK `on delete cascade`,
  `grade in (…)` + non-neg checks; opaque `fixture_id`, no FK — Axiom 3);
  `reject_score_before_lock()` trigger (INSERT/UPDATE rejected unless round
  `locked`/`scored`, `check_violation` — Axiom 6); RLS on all three tables +
  write-privilege revocation (client writes denied), `fixture_results` no
  client select, `round_scores`/`round_score_fixtures` select gated to
  `scored` round + season-membership, anon denied. Forward-only, idempotent,
  reuses `identity.set_updated_at`.
- `apps/server` (Scoring routes + mapper + CompositionRoot wiring) — DONE
  (verified on disk 2026-07-11):
  - `apps/server/lib/http/scoring_dto_mapper.dart` — `roundScoreToDto` /
    `roundScoresToJson`: projects `RoundScore` → versioned `RoundScoreDto` /
    `RoundScoresDto`; grade as stable `wireValue` token; no points ever
    client-writable; preserves the stored (prediction) fixture order.
  - `apps/server/routes/fixtures/[id]/result/index.dart` (75 lines) — `PUT`
    `RecordFixtureResult`; fixture from path `id` only; body =
    `{home_goals, away_goals}`; → `200` `FixtureResultDto`; `405` otherwise.
  - `apps/server/routes/rounds/[id]/score/index.dart` (49 lines) — `POST`
    `ScoreRound`; NO request body (integrity boundary); → `200` `RoundScoresDto`;
    `405` otherwise.
  - `apps/server/routes/rounds/[id]/scores/index.dart` (44 lines) — `GET`
    `GetRoundScores`; → `200` `RoundScoresDto` (empty list when scored-but-no-
    predictions); `405` otherwise. Both `/rounds` + `/fixtures` subtrees already
    behind `bearerAuth` (`_middleware.dart`) — no local scoring middleware.
  - `apps/server/lib/composition/composition_root.dart` — real `bootstrap`
    constructs `PostgresFixtureResultRepository` + `PostgresScoreRepository` and
    wires `recordFixtureResult` / `scoreRound` / `getRoundScores` as real
    use-case fields (ScoreRound reuses competition + prediction repos);
    `forTesting` has matching optional params + `_absent*` stand-ins backed by
    `_UnwiredFixtureResultRepository` / `_UnwiredScoreRepository` (full ports,
    every method throws `StateError`).
  - `apps/server/test/routes/competition_route_harness.dart` — added
    `InMemoryFixtureResultRepository` (upsert-in-place + recorded-at audit) and
    `InMemoryScoreRepository` (upsert per `(round,participant)`, participant-id
    ordered `listByRound`).
  - `apps/server/test/routes/scoring_routes_test.dart` (551 lines) — real
    wiring over the in-memory repos for all three routes: admin-only gating (×2
    writes), `409 scoring.round_not_locked`, `409 scoring.results_incomplete`,
    idempotent re-score (200, one row, no transition conflict, locked→scored),
    `409 scoring.round_not_scored`, `401 scoring.not_a_participant`, happy-path
    read/write, scored-but-empty 200, 400 transport/domain validation, 405 per
    route.
- **Six-way review** `docs/reviews/scoring-review.md` — DONE 2026-07-11
  (GREEN; findings A-1/C-1/C-2/P-1/M-1 all info/low, table in §7 of that file).
  No code change was required — every finding was verified already-satisfied by
  the code on disk or explicitly deferred with rationale.

**Milestone (Ledger) — COMPLETE & RATIFIED (green, 2026-07-11).**
Full Milestone-0 rigor. Delivered end-to-end across all six layers (domain →
contracts → application → infrastructure → migration `0005_ledger.sql` →
`apps/server` routes + mapper + route tests + CompositionRoot wiring) and
reviewed six ways (`docs/reviews/ledger-review.md`, phase-exit GREEN). The
review found **no High or Medium defect**; a single **Low** finding (L-1) was
resolved in-place (the dedupe key is realized as `(participant_id, round_id,
entry_kind, source_ref)` — see §3 and the delivery record below — preserving the
ratified idempotency guarantee exactly while allowing append-many corrections).

**Exit criterion met:** a scored round is posted to the append-only ledger by an
admin (server-only amounts, idempotent, no double-credit on replay); a
participant reads only their own projected balance and immutable entry stream.
Axioms 2/4/5/6 honoured physically (append-only `point_entries` with revoked
UPDATE/DELETE + an all-role immutability trigger, unique dedupe key,
balance-as-projection view, self-read RLS, anon denied). No new external
dependency (reuses `postgres 3.5.12` incl. `runInTransaction`, `dart_frog
1.2.6`, `mocktail`); `tooling/import_lint` ruleset unchanged (no new internal
package). Six-way review GREEN.

**Architecture decision (RATIFIED FIRST, before any code — §4 mandate):**
The score→ledger flow is a **separate, explicit `PostRoundToLedger` command**,
NOT a domain event emitted by `ScoreRound`. Rationale, kept strictly inside the
event-driven boundary (ADR 0002) and honouring the "do not change Scoring's
public surface without approval" rule:
- **No change to Scoring's surface.** `ScoreRound` stays exactly as ratified —
  it computes + persists `RoundScore`s and transitions `locked → scored`. It
  does NOT gain an event-emission side effect, so the ratified Scoring code and
  its GREEN review are untouched (the §4 constraint).
- **Ledger reads the already-persisted scored round** via the frozen
  `ScoreRepository.listByRound` (a read of Scoring's output — allowed; it is not
  a mutation of Scoring's surface) plus `CompetitionRepository.findRound` to
  gate on `RoundStatus.scored`. The command is admin/server-triggered (Axiom 2:
  the client never posts points), mirroring `ScoreRound`'s admin gate.
- **Why command over event now:** the platform has no outbox-dispatcher wired
  yet for Ledger (Platform ADR §1 lists it as infra we own but Ledger is the
  first consumer). An explicit idempotent command is the simplest correct
  realization of the event-driven intent ("a scored round is posted to the
  ledger") without introducing an unverified async dispatcher this phase; the
  command is the synchronous, in-process edge of the same boundary. A future
  outbox can call the identical use-case. This adds NO new architectural
  element beyond a use-case + adapter (no ADR change).
- **Idempotency / dedupe key (append-only, no double-credit — Axiom 4/5):**
  the natural key is **`(participant_id, round_id, entry_kind)`**. A round is
  posted as exactly one `PointEntry` per participant of kind
  `round_score` carrying that round's `RoundScore.totalPoints`. Re-posting the
  same scored round is a no-op on the pre-existing entries (SQL
  `ON CONFLICT (participant_id, round_id, entry_kind) DO NOTHING`), so a replay
  never appends a second crediting row and never double-credits. Because the
  ledger is append-only (Axiom 5), the dedupe is a *skip*, never an
  update/delete; a later correction is a **separate compensating entry** of a
  distinct kind (`correction`), which is why the key includes `entry_kind` (a
  compensating entry legitimately coexists with the original credit for the
  same `(participant, round)`). `source_ref` additionally records the
  originating `round_score` provenance for audit/traceability.

**Delivery record (per-file) — CORRECTED by auditor 2026-07-11 against direct
on-disk inspection, twice now (first pass caught an undercredited "pending"
note; this pass catches a session that shipped two full layers of real code
and left this section — and §4's checklist — completely untouched, zero
edits, despite `Checkpoint Saved.`):**
- `packages/domain/ledger/` — **DONE, verified on disk:** `entry_kind.dart`
  (71 L), `point_entry_id.dart` (38 L), `point_entry.dart` (170 L,
  append-only value — no mutation API), `ledger_balance.dart` (84 L, pure
  projection). Tests: `point_entry_test.dart` (177 L),
  `ledger_balance_test.dart` (102 L). Do NOT regenerate.
- `packages/contracts/ledger_dto.dart` — **DONE, verified on disk:** 322
  lines + `ledger_dto_test.dart` (139 lines, round-trip + no-leakage). Do NOT
  regenerate.
- `packages/application/ledger/` — **DONE, verified on disk:**
  `ports/ledger_repository.dart` (55 L, `appendEntries`/`listEntries`/
  `balanceFor`) + a **new, justified** `ports/participant_reader.dart` (31 L)
  — a narrow `findParticipantById` read port, added because the ratified
  `CompetitionRepository` only offers `findParticipant(seasonId, userId)`
  with no by-id lookup, and widening that frozen port would violate the
  "no change without approval" rule; this is a new internal port inside the
  existing `application` package, no new package, `import_lint` unaffected.
  Use-cases: `post_round_to_ledger.dart` (142 L — admin-gated, reads scored
  `RoundScore`s, builds one `PointEntry` per participant, idempotent append
  on the ratified dedupe key) + `read_participant_ledger.dart` (108 L —
  self-read gated via `ParticipantReader`, foreign/unknown both report
  not-found to avoid leaking existence). Tests: `fakes.dart` (222 L),
  `post_round_to_ledger_test.dart` (186 L, 10 cases incl. idempotent re-post,
  non-admin rejection, not-yet-scored refusal, transient-failure
  propagation), `read_participant_ledger_test.dart` (174 L, 8 cases incl.
  foreign-participant gating, zero-balance projection). Do NOT regenerate.
- `packages/infrastructure/ledger/` — **DONE, verified on disk:**
  `postgres_ledger_repository.dart` (315 L) + `postgres_participant_reader.dart`
  (112 L). Tests: `postgres_ledger_repositories_test.dart` (390 L, hermetic)
  + `postgres_ledger_repositories_integration_test.dart` (62 L, DB-gated). Do
  NOT regenerate.
- **Migration** `supabase/migrations/0005_ledger.sql` — **DONE this session
  (2026-07-11):** `ledger` schema; `ledger.entry_kind` enum
  (`round_score`/`correction`, mirroring `EntryKind.wireValue`);
  `ledger.point_entries` (append-only stream — `id` PK, `participant_id`/
  `round_id` FKs `on delete restrict` named EXPLICITLY
  `point_entries_participant_id_fkey`/`point_entries_round_id_fkey` for the
  adapter's 23503 mapping; `entry_kind`, signed `amount`, non-empty
  `source_ref`, `occurred_at`; checks `point_entries_round_score_nonneg`
  (round_score amount >= 0 — Axiom 6 backstop for the domain create() rule) +
  `point_entries_source_ref_nonempty`; unique dedupe constraint
  `point_entries_round_score_uniq (participant_id, round_id, entry_kind,
  source_ref)` — the constraint the adapter references by name in
  `ON CONFLICT ON CONSTRAINT`, see §3/L-1); indexes
  `point_entries_participant_stream_idx (participant_id, occurred_at, id)` for
  the adapter's stream ORDER BY + `point_entries_round_idx`; reuses
  `identity.set_updated_at`; **immutability backstop**
  `ledger.reject_entry_mutation()` — a `before update or delete` trigger that
  RAISES for EVERY role including the RLS-bypassing service role (Axiom 5,
  append-only enforced even against a compromised backend);
  `ledger.participant_balances` projection VIEW (`SUM(amount)` + `count(*)`,
  `security_invoker` applied defensively for PG15+; a queryable mirror equal to
  the domain `LedgerBalance.project`, NOT the source the adapter reads); RLS =
  self-read only (`point_entries_select_own` joins participant → `auth.uid()`),
  all client writes revoked (`insert/update/delete/truncate` from
  `anon, authenticated`, no permissive write policy), anon denied. Forward-only,
  idempotent.
- `apps/server` (Ledger routes + mapper + CompositionRoot wiring) — **DONE this
  session (2026-07-11):**
  - `apps/server/lib/http/ledger_dto_mapper.dart` — new;
    `pointEntryToDto(PointEntry)` (single-place shaping; `kind` as stable
    `wireValue`, `occurred_at` as UTC ISO-8601, never a points/score leak) reused
    by `postRoundToLedgerResponseJson` / `balanceJson` /
    `participantEntriesJson`.
  - `apps/server/routes/rounds/[id]/ledger/index.dart` — `POST` `PostRoundToLedger`;
    NO request body (integrity boundary — Axiom 2); → `200`
    `PostRoundToLedgerResponseDto` (empty `appended_entries` on an idempotent
    replay); `405` otherwise. `/rounds` subtree already behind `bearerAuth`
    (`rounds/_middleware.dart`).
  - `apps/server/routes/participants/_middleware.dart` — new; applies
    `bearerAuth()` to the whole `/participants` read subtree (mirrors
    `/rounds`,`/seasons`). The self-read ownership gate stays in the use-case.
  - `apps/server/routes/participants/[id]/balance/index.dart` — `GET`
    `ReadParticipantLedger.balanceOf` → `200` `BalanceDto`; `405` otherwise.
  - `apps/server/routes/participants/[id]/entries/index.dart` — `GET`
    `ReadParticipantLedger.entriesOf` → `200` `ParticipantEntriesDto` (empty list
    for an owned participant with no movements); `405` otherwise. Both reads
    surface a foreign/unknown participant identically as `401`
    `ledger.participant_not_found` (no ownership oracle).
  - `apps/server/lib/composition/composition_root.dart` — extended: private ctor
    + `bootstrap` now build `PostgresLedgerRepository` + `PostgresParticipantReader`
    and wire `postRoundToLedger` (reusing `competitionRepository` +
    `scoreRepository` + `UuidIdGenerator` + `SystemClock`) and
    `readParticipantLedger` as real fields; `forTesting` gained matching optional
    params with loud `_absent*` stand-ins backed by `_UnwiredLedgerRepository` /
    `_UnwiredParticipantReader` (full ports, every method throws `StateError`).
  - `apps/server/test/routes/competition_route_harness.dart` — added
    `InMemoryLedgerRepository` (append idempotent on the natural dedupe key
    `(participant, round, kind, source_ref)`; append-only — never mutates/deletes;
    `listEntries` occurred-at→id ordered; `balanceFor` via the pure domain
    `LedgerBalance.project`) + `InMemoryParticipantReader` (by-id resolve, `null`
    for unknown).
  - `apps/server/test/routes/ledger_routes_test.dart` — new; real wiring over the
    in-memory repos for all three routes. POST: admin-200-appends-credits,
    non-admin-401, not-scored-409-`ledger.round_not_scored`, idempotent-replay
    (200 + empty appended + one row), scored-but-no-participants-200-empty, 405.
    GET balance: owner-200-projected, owner-empty-200-zero, foreign-401, unknown-
    401 (same code), 405. GET entries: owner-200-ordered, owner-empty-200-empty,
    foreign-401, 405.
- **Six-way review** `docs/reviews/ledger-review.md` — **DONE this session
  (2026-07-11):** GREEN. No High/Medium; findings table in §7 (L-1 resolved
  in-place; P-note/M-note/S-verified/C-verified info-only). No code change was
  required beyond L-1's documentation precision (the migration already realizes
  the correct dedupe key).

**Milestone (Leaderboards) — COMPLETE & RATIFIED (green, 2026-07-11).**
Full Milestone-0 rigor. Delivered end-to-end across all six layers (domain →
contracts → application → infrastructure → migration `0006_leaderboard.sql` →
`apps/server` route + mapper + route tests + CompositionRoot wiring) and
reviewed six ways (`docs/reviews/leaderboards-review.md`, phase-exit GREEN). The
review found **no High or Medium defect**; a single **Low** (L-1, a dead dartdoc
reference `SeasonLeaderboard.rankAll` in `leaderboard_entry.dart`) was fixed
in-place to `SeasonLeaderboard.rank` (comment-only, no behavioural change), and
an Info SSoT precision note (D-1) corrected the infra hermetic test count from
"8" to the actual **7** cases. No other code change was required.

**Exit criterion met:** a season member reads the ranked standings — a read-side
projection over the ratified append-only ledger — via `GET /seasons/{id}/leaderboard`
behind `bearerAuth`; totals equal the participants' balances (Axiom 5, a single
protected truth for points); ranking is the pure domain's standard-competition
"1224" rule with a deterministic total tie-break (points desc, joinedAt asc,
participantId asc); every enrolled participant appears (never-credited = zero
row); an empty season is a legitimate empty board; a non-member is refused
`leaderboard.not_a_participant` (no season-existence oracle beyond membership).
Axioms 1/2/4/5/6 honoured physically (social-first but season-scoped visibility,
server-only totals, no group reference, a projection VIEW with NO second points
source, `security_invoker` self-read RLS + anon denied as the backstop). No new
external dependency (reuses `postgres 3.5.12` read surface, `dart_frog 1.2.6`,
`mocktail`, `test ^1.26.0`); `tooling/import_lint` ruleset unchanged (no new
internal package). Six-way review GREEN.

**Architecture decision (RATIFIED FIRST, before any code — §4 FIRST STEP
mandate). A leaderboard is a READ-SIDE PROJECTION over the ratified ledger,
NEVER a second source of truth for points (Axiom 5).** Resolved decisions:

- **Scope = one CompetitionSeason.** "Predict once, rank everywhere" (Axiom 4)
  means the same per-round score is reused across ranking contexts; the first
  and canonical ranking context is the season a participant is enrolled in
  (`Participant` is keyed on `SeasonId`; Database ADR §1). The wire surface is
  `GET /seasons/{id}/leaderboard`. Group/global leaderboards are later phases
  (Groups/Social) and reuse the identical projection over a different
  participant set — no new points source is ever introduced.
- **Source of truth = `ledger.point_entries` (the append-only stream), NOT
  `scoring.round_scores`.** A participant's leaderboard total is the SUM of
  their ledger `amount`s (which already nets in any `correction` entry — Axiom
  5), so the leaderboard can never disagree with the balance the participant
  reads at `GET /participants/{id}/balance`. Ranking off scores would ignore
  corrections and create a second, drifting truth — explicitly rejected.
- **Realization = a LIVE query, aggregated on read (a VIEW), not a
  materialized/derived table.** Rationale, mirroring the Ledger flow decision:
  the append-only ledger + participant enrolment fully determine a leaderboard,
  so a stored ranking table would be a second copy that must be kept in sync (a
  drift/consistency risk for the protected record, and an outbox we have not
  wired). Migration `0006_leaderboard.sql` therefore adds **only** a
  season-scoped read VIEW `leaderboard.season_standings` (join ledger →
  participant → round → season, `SUM(amount)` grouped by participant) plus a
  supporting index; it introduces NO new writable table and NO new points
  source. Ranks are computed in the pure domain from the aggregated totals (the
  view supplies totals only), so the ranking rule is unit-tested framework-free
  and identical whoever runs the query.
- **Tie-break + rank rule (stated explicitly, not invented silently).**
  Standings order by `totalPoints DESC`; ties broken deterministically by
  `participant.joinedAt ASC` then `participantId ASC` (a stable, reproducible
  total order — the earlier joiner ranks first among equal totals; never
  arbitrary DB order). Ranks are **standard competition ranking ("1224"):**
  equal totals SHARE a rank, and the next distinct total skips by the number of
  tied competitors (so two players tied for rank 1 are followed by rank 3). The
  domain `SeasonLeaderboard.rank` computes this from the ordered entries; the
  tie-break keys travel with each entry so ordering is total even before rank
  assignment.
- **Only-scored contribution / empty season.** Only `round_score` credits (and
  their corrections) exist in the ledger — a round contributes to the
  leaderboard exactly once it has been posted (`PostRoundToLedger`), which
  requires the round to be `scored`. A participant with no posted entries yet
  appears with `totalPoints = 0` (every ACTIVE participant of the season is
  listed, so the board is complete from round 1; a zero row is "enrolled, not
  yet credited", distinct from "not a participant"). A season with no
  participants yields an empty board (not an error).
- **Visibility gate.** `GET /seasons/{id}/leaderboard` is behind `bearerAuth`
  and requires the caller to be a **member of that season** (an active/withdrawn
  participant) — the leaderboard is social-first (Axiom 1) but scoped to people
  in the competition, mirroring `ListRoundPredictions`' season-membership gate.
  A non-member is refused `leaderboard.not_a_participant` (no season-existence
  oracle beyond membership). No admin gate (it is a read, not a points write —
  Axiom 2 is about writes).

_Objective + per-file delivery record for this milestone is appended below as
each layer completes (per the session protocol); §4 carries the live checklist._

**Delivery record (per-file) — Leaderboards, verified on disk this session:**
- `packages/domain/leaderboard/` — DONE (prior session; verified present on disk
  2026-07-11): `leaderboard_entry.dart` (`LeaderboardEntry`, `projected`/
  `withRank`, sign-free-count invariant, UTC joinedAt, sentinel rank 0),
  `season_leaderboard.dart` (`SeasonLeaderboard.rank`: dup-reject, total order
  points-desc/joinedAt-asc/id-asc, standard "1224" ranks). Tests present.
- `packages/contracts/leaderboard_dto.dart` — DONE (prior session; present on
  disk) + `test/leaderboard_dto_test.dart`.
- `packages/application/leaderboard/` — DONE (prior session; present on disk):
  `ports/leaderboard_repository.dart` (`LeaderboardRepository.seasonStandings`
  → unranked per-participant projection) + `get_season_leaderboard.dart`
  (`GetSeasonLeaderboard`: user-role gate, season-id parse, season-membership
  gate `leaderboard.not_a_participant` via `CompetitionRepository.findParticipant`,
  delegates ranking to `SeasonLeaderboard.rank`). Tests present (`fakes.dart`,
  `get_season_leaderboard_test.dart`).
- `packages/infrastructure/leaderboard/` — **DONE this session (2026-07-11):**
  `src/leaderboard/postgres_leaderboard_repository.dart` — `PostgresLeaderboardRepository`
  implements the `LeaderboardRepository` port with a single season-scoped read
  over the projection VIEW `leaderboard.season_standings` (`SELECT participant_id,
  total_points, entry_count, joined_at … WHERE season_id = @season_id`; NO SQL
  ORDER BY — the pure domain `SeasonLeaderboard.rank` owns ordering + "1224"
  ranks). Total (never throws); row→`LeaderboardEntry.projected` mapping returns
  UNRANKED entries; `_readInt` accepts `int`/`BigInt`(`SUM`/`count` are bigint)/
  `String`, `_readUtcTimestamp` normalizes to UTC; a bad participant-id/non-int
  total-or-count/absent joined_at, or a domain `projected()` Err, all map to a
  transient `leaderboard.row_corrupt` (a read path never leaks a raw
  invariant/validation). `@named` binding only (Security ADR §2). Exported from
  `infrastructure.dart`. Tests: hermetic
  `test/leaderboard/postgres_leaderboard_repository_test.dart` (fake connection,
  7 cases: SQL shape + `@season_id` bind + no-ORDER-BY & unranked mapping +
  LEFT-JOIN zero row [one case], bigint SUM/count, empty board, transient
  passthrough, corrupt participant-id, corrupt non-int-total, corrupt
  absent-joined_at) + DB-gated
  `postgres_leaderboard_repository_integration_test.dart` (tagged `integration`,
  documents the VIEW's season-scoped SUM / LEFT-JOIN / correction-nets-in /
  never-credited-zero / withdrawn-retained / season-scoping / empty-season
  scenarios CI exercises). No new external dependency (reuses `postgres 3.5.12`
  read surface); `tooling/import_lint` ruleset unchanged (adapter lives inside
  `infrastructure`, imports `application`/`domain`/`shared` — already permitted).
- **Migration** `supabase/migrations/0006_leaderboard.sql` — **DONE this session
  (2026-07-11):** `leaderboard` schema; read-only projection VIEW
  `leaderboard.season_standings` anchored on `competition.participants` LEFT
  JOIN `ledger.point_entries` scoped to the participant's own season's rounds
  (`e.round_id in (select r.id from competition.rounds r where r.season_id =
  p.season_id)`), producing exactly the adapter's columns `season_id,
  participant_id, coalesce(sum(amount),0)::bigint total_points,
  count(e.id)::bigint entry_count, joined_at`; every ACTIVE/WITHDRAWN participant
  appears once (never-credited = 0/0 via the LEFT JOIN + coalesce); NO ORDER BY
  (domain ranks); NO writable table / enum / trigger / second points source
  (§2 decision, Axiom 5). Supporting composite index
  `point_entries_participant_round_idx (participant_id, round_id)` serving the
  VIEW's per-(participant,round) join (0005 already had participant-stream and
  round indexes). `security_invoker` set on the VIEW (PG15+ guarded `do $$`) so
  a direct client select inherits the base tables' self-read RLS
  (participants.user_id = auth.uid(); point_entries self-read) — a client can
  never see another participant's total (no enumeration oracle); `revoke all …
  from anon`, `grant select … to authenticated`; the app's season-membership
  gate is primary, RLS the backstop (Axiom 6). Forward-only, idempotent.
- `apps/server` (Leaderboard route + mapper + CompositionRoot wiring) — **DONE
  this session (2026-07-11):**
  - `apps/server/lib/http/leaderboard_dto_mapper.dart` — new;
    `leaderboardEntryToDto(LeaderboardEntry)` (rank/participant-id/signed total/
    entry count, no group ref — Axiom 4) reused by
    `seasonLeaderboardToJson(SeasonLeaderboard)` (versioned `SeasonLeaderboardDto`;
    echoes the aggregate's already-ranked total order; empty entries = empty
    board, never an error). No points ever client-writable (Axioms 2/5).
  - `apps/server/routes/seasons/[id]/leaderboard/index.dart` — `GET`
    `GetSeasonLeaderboard` (principal + season id from path) → `200`
    `SeasonLeaderboardDto`; `405` otherwise. The season-membership visibility gate
    + `leaderboard.not_a_participant` refusal live entirely in the use-case; the
    route makes no authz decision. `/seasons` subtree already behind `bearerAuth`
    (`seasons/_middleware.dart`) — no local leaderboard middleware.
  - `apps/server/lib/composition/composition_root.dart` — extended: private ctor
    + `bootstrap` now build `PostgresLeaderboardRepository` and wire
    `getSeasonLeaderboard` (reusing `competitionRepository` for the membership
    gate) as a real field; `forTesting` gained a matching optional param with a
    loud `_absentGetSeasonLeaderboard` stand-in backed by
    `_UnwiredLeaderboardRepository` (full port, `seasonStandings` throws
    `StateError`).
  - `apps/server/test/routes/competition_route_harness.dart` — added
    `InMemoryLeaderboardRepository` (per-season seed of unranked projections;
    empty when unseeded).
  - `apps/server/test/routes/season_leaderboard_test.dart` — new; real wiring over
    the in-memory competition + leaderboard repos. GET: member-200 ranked
    (points-desc / joinedAt-asc "1224" tie sharing rank 2), enrolled-not-credited
    zero row present, empty-board-200, non-member-401
    `leaderboard.not_a_participant`, malformed-season-id-400, 405.

**Six-way review** `docs/reviews/leaderboards-review.md` — **DONE this session
(2026-07-11):** GREEN. No High/Medium; findings table in §7 (L-1 dartdoc typo
fixed in-place; D-1 test-count corrected to 7; P-note/M-note/S-verified/
C-verified info-only). The single code change was L-1's comment correction
(`SeasonLeaderboard.rankAll` → `SeasonLeaderboard.rank` in
`packages/domain/lib/src/leaderboard/leaderboard_entry.dart`); the migration,
adapter, route, and tests already realized the ratified design correctly.

---

**Milestone (Groups) — Decisions Ratified (product call, 2026-07-11, explicit
go-ahead — optimization criterion: maximum user engagement/virality, the
proven mini-league pattern from Fantasy Premier League / NFL Pick'em / bracket
pools):**

1. **Group ↔ Competition relationship — RATIFIED: a Group does NOT own or
   scope a Competition.** `Competition`/`Round`/`Prediction`/`Leaderboard`
   remain fully group-free (no `groupId` added anywhere — the frozen
   round/prediction/leaderboard surfaces are NOT touched). A `Group` is an
   orthogonal social container: a named circle of `User`s. Rationale: this is
   the lowest-friction, highest-virality shape — inviting a friend costs one
   shared link into an EPL/WC2026/UCL competition the user is already in,
   never "spin up a whole new competition." It also keeps all activity
   concentrated on the live global competition instead of fragmenting users
   into isolated private tournaments.
2. **Membership model — RATIFIED:** roles = `owner` (creator; can rename the
   group, remove members, regenerate the invite code) + `member` (no
   intermediate `admin` tier for v1 — keep it minimal). Join flow =
   **shareable invite code/link, zero-friction instant join** (no
   request-approve step for v1 — approval flows suppress viral growth).
   `GroupMembership` (`UserId` + `GroupId`) is **independent of** competition
   `Participant` — joining a group does not auto-enrol someone in any
   competition, and vice versa; a member's row in a group's leaderboard for a
   given season only appears if they are separately also a season
   `Participant` (reuses the existing season-membership gate, no new one).
3. **Visibility/privacy — RATIFIED:** private-by-default, invite-only
   discovery, no existence oracle for non-members — identical gate pattern to
   the season-membership check already ratified for Leaderboards (a
   non-member gets `group.not_a_member`, never a 404-vs-403 leak).
4. **Group leaderboard reuse — CONFIRMED as stated:** a group's leaderboard
   for a season is the **same** `leaderboard.season_standings` VIEW filtered
   to `{participants whose UserId ∈ this group's membership}` — no new points
   source, no new ranking logic; only the participant-set filter is new
   (Axiom 5 untouched).

These four are final for this phase; do not re-litigate them mid-build. If
implementation reveals a genuine gap, document it in §4 and ask, exactly as
`submittedAt` was handled.

---

**Milestone (Groups) — IN PROGRESS (started 2026-07-11). Objective +
design-anchors ratified below BEFORE any code (FIRST STEP mandate, mirroring
every prior phase). The four product decisions are already RATIFIED above
(Milestone (Groups) — Decisions Ratified); this block fixes the technical
design each layer builds against.**

**Objective (end state):** the `Group` aggregate delivered end-to-end at full
Milestone-0 rigor across all six layers — pure `packages/domain/group`, group
DTOs in `contracts`, `application/group` use-cases (create/join/manage,
server-authorized + idempotent + `Authorization.requireRole`), a Postgres
adapter + repository port, migration `0007_group.sql` (forward-only, idempotent,
RLS = member-scoped self-read + write backstop), `apps/server` routes behind
`bearerAuth` + mapper + CompositionRoot wiring + route tests, plus a **group
leaderboard read** that reuses `leaderboard.season_standings` filtered to group
membership (ratified decision #4 — NO new points source, NO new ranking logic).

**Design-anchors (fixed here; do not re-derive):**

- **`Group` aggregate (Database ADR 0003 Community aggregate; Axiom 2
  first-class private community).** Root `Group` holds: `GroupId` (UUID value
  object extending `EntityId`, `tryParse` like `UserId`/`ParticipantId`);
  `ownerId: UserId` (the creator — the only `owner` role holder); a trimmed
  display `name` (1–80 chars, validated in `Group.create` mirroring
  `Competition.create`'s name discipline); an `InviteCode` value object (the
  shareable zero-friction join token — decision #2); `createdAt` (UTC,
  normalized by caller). The `Group` carries **NO competition/season/round
  reference** (decision #1 — orthogonal social container). Pure/immutable;
  `create` (new, validated) + `fromStored` (rehydrate, typing only);
  `rename`/`regenerateInvite` produce new values (owner-authority is enforced in
  the use-case, not the entity — an aggregate reasons only about itself, mirror
  of `Participant`).
- **`InviteCode` value object.** A short, URL-safe, unguessable token (the
  shareable link's payload — decision #2/#3: invite-only discovery, no existence
  oracle). Generated server-side; `tryParse` validates a closed charset +
  length so an untrusted join token is a typed validation failure, never a
  lookup on arbitrary input. The domain owns the *shape*; the actual random
  generation is an application concern via a new narrow `InviteCodeGenerator`
  port (kept out of the pure domain, mirroring how ids come from `IdGenerator`).
- **`GroupRole` enum — closed set `{owner, member}`** (decision #2; NO `admin`
  tier for v1). `wireValue` + `tryParse` mirroring `ParticipantStatus`. This is
  a **per-group** role, deliberately distinct from the platform-wide
  `PlatformRole` (as `platform_role.dart` already notes it would be).
- **`GroupMembership` aggregate** (`GroupMembershipId` + `groupId` + `userId` +
  `GroupRole` + `joinedAt` UTC). Independent of competition `Participant`
  (decision #2). Uniqueness of `(groupId, userId)` — a user is in a group at
  most once — enforced structurally in the schema + the join use-case, not
  re-checked in the entity (mirror of `Participant`). Owner membership is created
  atomically with the group.
- **`contracts` group DTOs** — versioned, snake_case, no leakage (mirror
  `competition_dto.dart`/`leaderboard_dto.dart`): `GroupDto`
  (id/name/owner-id/invite-code/created-at/member-count),
  `GroupMembershipDto` (group-id/user-id/role wire-token/joined-at),
  `GroupLeaderboardDto` (reuses the leaderboard entry shape filtered to the
  group). The invite code is only ever surfaced to a member (never in a
  non-member-visible payload — decision #3).
- **`application/group` (imports domain/shared only — `import_lint` unchanged; a
  `group` slice lives inside the existing `application` package, no new internal
  package).** Repository port `GroupRepository`
  (`saveGroup`/`findGroup`/`findByInviteCode`/`saveMembership`/`findMembership`/
  `listMemberships`/`updateGroup`), all total (typed `Result`, infra failures →
  `transient`). New narrow `InviteCodeGenerator` port under `common/` beside
  `IdGenerator`/`Clock`. Use-cases: `CreateGroup` (any `PlatformRole.user`;
  server-generates id+invite+owner membership atomically), `JoinGroupByInvite`
  (any user; resolves group by invite code, idempotent instant join as `member`,
  concurrent-race convergence on the `(groupId,userId)` unique key mirroring
  `JoinCompetition`), `RenameGroup` / `RegenerateInvite` (owner-only —
  membership-role gate inside the use-case, NOT `PlatformRole`),
  `ListGroupMembers` (member-only visibility gate → `group.not_a_member`, mirror
  of the season-membership gate), and `GetGroupLeaderboard` (member-only;
  reuses `LeaderboardRepository` filtered to the group's member `UserId`s +
  `SeasonLeaderboard.rank` — decision #4, no new points source). A non-member is
  refused `group.not_a_member` with NO existence oracle (decision #3, mirror of
  `leaderboard.not_a_participant`).
- **`infrastructure/group`** — `PostgresGroupRepository` over `0007_group.sql`
  tables (`@named` binding only — Security ADR §2; SQLSTATE→typed mapping:
  `23505` group/membership unique → `group.name_taken` / `group.already_member`
  (the code `JoinGroupByInvite` pivots on), `23503` FKs → `group.not_found` /
  `group.user_not_found`; malformed row → transient `group.row_corrupt`). The
  group leaderboard filter reuses the existing `leaderboard.season_standings`
  VIEW (no new VIEW for points) intersected with group membership.
- **Migration `0007_group.sql`** — `group` schema; `group.groups`
  (id PK, `owner_id` FK → `identity.users` `on delete restrict`, `name`,
  unique `invite_code`, `created_at`, reuses `identity.set_updated_at`);
  `group.group_memberships` (id PK, `group_id` FK `on delete cascade`,
  `user_id` FK `on delete restrict`, `role` enum `group.group_role`
  `{owner,member}`, `joined_at`, unique `(group_id, user_id)` = physical
  "member once", explicitly-named FK constraints for the adapter's 23503
  mapping); RLS = member-scoped self-read (a caller sees only groups they belong
  to — no enumeration oracle, decision #3), all client writes revoked (backend
  service role owns writes — Axiom 6 backstop), anon denied. NO group ref added
  to any competition/round/prediction/leaderboard object (decision #1). Forward-
  only, idempotent.
- **`apps/server`** — routes behind `bearerAuth` (`groups/_middleware.dart`
  applies it to the `/groups` subtree, mirror of `/participants`): `POST
  /groups` (create), `POST /groups/join` (join by invite code in body — the
  code is the capability, not an id in the path), `GET /groups/{id}` +
  `GET /groups/{id}/members` (member-gated reads), `PATCH /groups/{id}`
  (rename, owner-only), `POST /groups/{id}/invite/regenerate` (owner-only),
  `GET /groups/{id}/seasons/{seasonId}/leaderboard` (group leaderboard, member-
  gated). Mapper `group_dto_mapper.dart` single-place shaping. CompositionRoot
  `bootstrap` wires real `PostgresGroupRepository` + `UuidInviteCodeGenerator`;
  `forTesting` gains loud `_absent*`/`_Unwired*` stand-ins. Route tests over an
  `InMemoryGroupRepository` in the harness.

_Per-file delivery record is appended below as each layer completes; §4 carries
the live checklist._

**Delivery record (per-file) — Groups:**
- `packages/domain/group/` — **DONE 2026-07-11** (pure, imports only `shared` +
  domain-internal `identity` `UserId`; `import_lint` ruleset unchanged):
  - `group_id.dart` — `GroupId extends EntityId`, `tryParse` (UUID-validated,
    `group.group_id_empty`/`group.group_id_malformed`).
  - `group_membership_id.dart` — `GroupMembershipId extends EntityId`,
    `tryParse` (`group.membership_id_empty`/`_malformed`).
  - `group_role.dart` — `GroupRole` closed set `{owner, member}` (NO admin tier
    — decision #2), `wireValue`/`isOwner`/`tryParse` (`group.role_unknown`);
    per-group role, distinct from `PlatformRole`.
  - `invite_code.dart` — `InviteCode` value object: fixed length 10, closed
    URL-safe alphabet (ambiguous `0 O 1 I L` + lower-case excluded);
    `tryParse` (`group.invite_code_empty`/`_malformed`); exposes `alphabet`/
    `isAllowedChar`/`codeLength` so the application generator draws exactly the
    validated shape. Generation is an application concern (the
    `InviteCodeGenerator` port), not the pure domain.
  - `group.dart` — `Group` aggregate root: `create` (name trim 1–80 mirroring
    `Competition.create`, UTC `createdAt`, `group.name_empty`/`name_too_long`/
    `created_at_not_utc`), `fromStored`, `rename`, `regenerateInvite`; carries
    NO competition/season/round ref (decision #1); owner-authority enforced in
    use-cases not the entity (mirror of `Participant`). Value-comparable.
  - `group_membership.dart` — `GroupMembership` aggregate: `owner`/`join`
    factories (UTC-gated, `group.membership_joined_at_not_utc`), `fromStored`,
    `isOwner`; independent of competition `Participant` (decision #2); `(groupId,
    userId)` uniqueness enforced in schema+use-case, not the entity.
  - All six exported from `domain.dart`. Tests: `test/group/group_id_test.dart`,
    `group_role_test.dart`, `invite_code_test.dart`, `group_test.dart`,
    `group_membership_test.dart` (id typing/parse, closed-set role, invite-code
    alphabet/length, create/rename/regenerate/equality, owner/member factories +
    UTC gate).
- `packages/contracts/group_dto.dart` — **DONE 2026-07-11** (versioned,
  snake_case, no leakage; depends on nothing — Application ADR §3):
  `GroupDto` (id/name/owner_id/invite_code/created_at/member_count — invite code
  only surfaced to a member; NO season/competition ref — decision #1),
  `GroupMembershipDto` (id/group_id/user_id/role token/joined_at; independent of
  competition Participant — decision #2), `GroupMembersDto` (group_id + ordered
  members), `GroupLeaderboardEntryDto` + `GroupLeaderboardDto` (reuses the season
  standings shape filtered to group members — decision #4; rank/participant_id/
  user_id/signed total/entry_count, all server-produced; no group ref on the
  entry). Exported from `contracts.dart`. Test `test/group_dto_test.dart`
  (round-trip, snake_case keys, back-compat default schema_version, no-leakage,
  order-significant equality, empty list/board legitimate).
- `packages/application/group/` — **DONE 2026-07-11 (completed this session;
  a prior session had shipped 4 use-cases + 2 ports on disk but left §2/§4
  untouched — CORRECTED by auditor against direct on-disk inspection; imports
  domain/shared only, `import_lint` ruleset unchanged — a `group` slice inside
  the existing `application` package):**
  - `ports/group_repository.dart` — `GroupRepository`
    (`createGroupWithOwner` atomic group+owner, `findGroup`, `findByInviteCode`,
    `updateGroup`, `saveMembership`, `findMembership`, `listMemberships`
    joinedAt-asc); all total (typed `Result`, infra→`transient`; unique
    violations → `group.invite_code_conflict`/`group.already_member`).
  - `ports/group_standings_reader.dart` — `GroupStandingsReader.groupSeasonStandings`
    (`{groupId, seasonId}` → unranked `List<GroupStandingEntry>` = member `UserId`
    + season `LeaderboardEntry`) + the `GroupStandingEntry` pairing value; reuses
    the ratified `leaderboard.season_standings` VIEW intersected with membership
    (decision #4 — NO new points source).
  - `common/invite_code_generator.dart` — `InviteCodeGenerator` port
    (`newCode()` → well-formed `InviteCode`; crypto-strong randomness; MUST NOT
    throw). Now also exported from `application.dart` this session.
  - Use-cases: `create_group.dart` (`CreateGroup` — any `PlatformRole.user`;
    server-generates id+invite+owner membership atomically; ownerId from
    principal never body; no create-idempotency), `join_group_by_invite.dart`
    (`JoinGroupByInvite` — code is the capability, unknown/rotated →
    `group.invite_invalid` no existence oracle, idempotent instant join,
    concurrent-race convergence on `group.already_member`),
    `rename_group.dart`/`regenerate_invite.dart` (owner-only via per-group
    `GroupRole` gate in the use-case NOT `PlatformRole`; non-owner
    `group.not_owner`, non-member `group.not_a_member`),
    `list_group_members.dart` (`ListGroupMembers` — member-only visibility gate
    `group.not_a_member`), `get_group_leaderboard.dart` (`GetGroupLeaderboard` —
    member-only; reads unranked group∩season projection, ranks via the pure
    domain `SeasonLeaderboard.rank`, re-keys each ranked entry to its member
    `UserId` on the stable `participantId`; empty board legitimate; a ranked
    participant that cannot map back → transient `group.standings_inconsistent`,
    a read path never fabricates ownership) + the `group_leaderboard.dart`
    application read value (`RankedGroupStanding` + `GroupLeaderboard`).
  - ALL exported from `application.dart` this session (the export block was
    entirely absent before — the prior-session gap). Tests under `test/group/`:
    `fakes.dart` (`InMemoryGroupRepository` atomic create + `(groupId,userId)`
    uniqueness + current-code resolution + joinedAt-asc list;
    `InMemoryGroupStandingsReader`; `FakeIdGenerator`/`FakeClock`/
    `FakeInviteCodeGenerator`; builders), `create_group_test.dart` (6),
    `join_group_by_invite_test.dart` (7), `rename_and_regenerate_test.dart` (8),
    `list_group_members_test.dart` (5), `get_group_leaderboard_test.dart` (6).
    No new external dependency; `import_lint` ruleset unchanged.
- `packages/infrastructure/group/` — **DONE this session (2026-07-12; the two
  auditor-flagged gaps closed — export line added + both adapter tests
  written).** On disk and verified real (no TODO/placeholder/mock):
  - `src/group/postgres_group_repository.dart` (526 L) —
    `PostgresGroupRepository` implements the full `GroupRepository` port
    (`createGroupWithOwner` atomic group+owner insert, `findGroup`,
    `findByInviteCode`, `updateGroup`, `saveMembership`, `findMembership`,
    `listMemberships` joinedAt-asc) **and** the `GroupStandingsReader` port
    (`groupSeasonStandings` — reuses the ratified `leaderboard.season_standings`
    VIEW intersected with group membership, decision #4, no new points source).
    `@named` binding only (Security ADR §2); SQLSTATE→typed mapping off
    `ServerException.code`/`.constraintName` (`23505` unique →
    `group.invite_code_conflict`/`group.already_member`; `23503` FKs →
    `group.not_found`/`group.user_not_found`; malformed row → transient
    `group.row_corrupt`). Reuses `postgres 3.5.12` — no new dependency.
  - **Export added this session:** `packages/infrastructure/lib/infrastructure.dart`
    now has `export 'src/group/postgres_group_repository.dart';` (inserted in
    alphabetical position between `db/postgres_connection.dart` and
    `identity/auth_config.dart`) — the adapter is now reachable through the
    package's public surface, unblocking the CompositionRoot wiring.
  - **Tests added this session** (mirror the leaderboard/ledger/competition infra
    test style):
    - `test/group/postgres_group_repository_test.dart` (hermetic, fake
      `PostgresConnection` recording SQL+params with a per-call scripted
      response list; 32 cases across all 8 methods): `createGroupWithOwner`
      (two ordered @named-bound writes inside `runInTransaction`; a failed group
      insert short-circuits before the membership insert; a failed membership
      insert fails the tx), `saveMembership`/`updateGroup` (binding + Ok +
      transient passthrough), `findGroup`/`findByInviteCode` (row→Group mapping,
      @id/@invite_code binding, Ok(null) on empty, transient passthrough, four
      `group.row_corrupt` branches: bad owner id / non-text name / malformed
      invite / absent created_at), `findMembership`/`listMemberships`
      (row→GroupMembership mapping, role wire-token, composite-key/@group_id
      binding, ORDER BY joined_at ASC list shape, Ok(null)/empty on absence,
      unknown-role & bad-id row_corrupt, transient passthrough),
      `groupSeasonStandings` (season∩group SELECT over `leaderboard.season_standings`,
      @group_id/@season_id binding, NO ORDER BY, unranked mapping incl. a BigInt
      SUM/count and a zero row, empty board, transient passthrough, five
      `group.row_corrupt` branches: corrupt user id / participant id / non-int
      total / absent joined_at). The `ServerException`→`invariant` reclassify
      path is NOT exercised here (the driver exception has no public
      constructor) — documented and deferred to the DB-gated test.
    - `test/group/postgres_group_repository_integration_test.dart` (DB-gated,
      tagged `integration`, `skip`ped locally so `melos run test` stays
      hermetic; runs in CI against ephemeral Postgres with migrations 0001–0007
      applied): documents the scenarios only a live DB can prove — the
      `ServerException`→typed-`invariant` reclassify for every named constraint
      (`group.invite_code_conflict`/`group.already_member`/`group.not_found`/
      `group.user_not_found`), the atomic `createGroupWithOwner` rollback on a
      mid-tx duplicate-invite failure (no orphan group/membership row), and the
      reused `season_standings` VIEW ∩ membership (season-scoped SUM nets in
      corrections, the intersection filter excludes non-members / non-participants,
      never-credited zero row, season scoping, UTC joined_at, empty board).
- **Migration** `supabase/migrations/0007_group.sql` — **DONE (auditor-verified
  on disk 2026-07-11, 12,359 bytes; the shipping session left it unrecorded).**
  `group` schema; `group.groups` (id PK, `owner_id` FK → `identity.users`
  `on delete restrict`, trimmed `name`, unique `invite_code`, `created_at`,
  reuses `identity.set_updated_at`); `group.group_memberships` (id PK, `group_id`
  FK `on delete cascade`, `user_id` FK `on delete restrict`, `role`
  `group.group_role` `{owner,member}`, `joined_at`, unique `(group_id, user_id)`
  = physical "member once", explicitly-named FK constraints for the adapter's
  23503 mapping); RLS = member-scoped self-read (no existence oracle — decision
  #3), all client writes revoked (Axiom 6 backstop), anon denied; NO group ref
  on any competition/round/prediction/leaderboard object (decision #1).
  Forward-only, idempotent.
- `apps/server` (Group routes + mapper + CompositionRoot wiring) — **DONE
  (auditor-verified 2026-07-12c, by direct on-disk inspection of the whole
  layer).** `group_dto_mapper.dart` (present & correct), all 7 route files under
  `apps/server/routes/groups/` (`_middleware.dart`, `index.dart` create,
  `join/index.dart`, `[id]/index.dart` get+rename, `[id]/members/index.dart`,
  `[id]/invite/regenerate/index.dart`, `[id]/seasons/[seasonId]/leaderboard/
  index.dart`), the harness `InMemoryGroupRepository` + `InMemoryGroupStandingsReader`
  in `competition_route_harness.dart`, and `group_routes_test.dart` (707 lines,
  30 tests) are all present and complete. **CompositionRoot wiring is COMPLETE
  and CORRECT on disk** (finding G-1, groups-review §7): the private ctor's 7
  group params (`createGroup`/`getGroup`/`joinGroupByInvite`/`renameGroup`/
  `regenerateInvite`/`listGroupMembers`/`getGroupLeaderboard`) are all backed by
  fields, `bootstrap` builds one `PostgresGroupRepository` (backing BOTH
  `GroupRepository` AND `GroupStandingsReader`) + `UuidInviteCodeGenerator` and
  wires all 7, and `forTesting` supplies matching optional params + `_absent*`
  stand-ins backed by `_UnwiredGroupRepository` (implements both ports) +
  `_UnwiredInviteCodeGenerator`. §4 had recorded this wiring as "NOT STARTED
  (reverted)" — that was stale (the recurring "code shipped, docs untouched"
  drift, 4th occurrence); a later session completed it correctly and left the
  doc behind. Corrected here + in §4. No code change required — the wiring was
  already production-correct.
- **Six-way review** `docs/reviews/groups-review.md` — **DONE this session
  (2026-07-12):** GREEN. No High/Medium; findings table in §7 (G-1 documentation
  drift fixed in this file; P-note/M-note/S-verified/C-verified info-only). No
  code change was required — every layer was verified already-correct on disk by
  direct inspection; the only fix was this SSoT correction. Exit criterion MET —
  **Groups phase COMPLETE & RATIFIED.**

---

**Milestone (Social) — Decisions Ratified (product call, 2026-07-12, explicit
go-ahead — same optimization criterion as Groups: maximum engagement/virality
within the Tier-3 constraint of "peripheral, rebuildable, never a second
points source"):**

1. **Social surface for v1 — RATIFIED: Activity Feed + emoji Reactions only.
   No free-text comments in v1.** Feed events: round scored, member joined the
   group, a member's rank shifted on the group leaderboard. Reactions: a
   single emoji reaction per member per round-result (bounded, fixed emoji
   set — no free text). Rationale: highest engagement-per-risk pair —
   comments require moderation infrastructure (abuse/report/delete flows)
   that is out of scope for a fast, safe Tier-3 delivery; feed + reactions
   already cover the core "banter with friends" loop.
2. **Projection vs. stored — RATIFIED:** the **Activity Feed is a pure read
   projection** — NO new table, NO new writes; it is assembled by reading
   existing ratified data (`ledger`/`scoring` round-scored events,
   `group.membership` join timestamps, `leaderboard.season_standings` rank
   deltas). **Reactions ARE genuinely new stored Tier-3 content** — one new
   table in `0008_social.sql` (`social.reactions` or equivalent: `UserId` +
   `RoundId`/result reference + emoji + timestamp, unique per member per
   target to keep it idempotent). This is the ONLY new writable surface this
   phase introduces.
3. **Visibility — CONFIRMED:** every social read (feed and reactions) is
   group-membership-gated, reusing the exact ratified `group.not_a_member`
   gate (no existence oracle) at both the application layer and the RLS
   backstop. No new visibility mechanism is introduced.
4. **Degradation — CONFIRMED:** Social is fully additive. A Social read/write
   failure (feed assembly error, reaction write failure) MUST NOT block or
   fail any Tier-1 core operation (prediction submission, scoring, ledger
   posting, leaderboard read) — Social endpoints fail independently and the
   rest of the platform is unaffected, per Deployment ADR 0007 §Tier-3.

These four are final for this phase; do not re-litigate them mid-build. If
implementation reveals a genuine gap, document it in §4 and ask, exactly as
`submittedAt` and the Groups decisions were handled.

---

**Milestone (Social) — IN PROGRESS (started 2026-07-12). Objective +
technical design-anchors ratified below BEFORE any code (FIRST STEP mandate,
mirroring every prior phase). The four product decisions are already RATIFIED
above (Milestone (Social) — Decisions Ratified); this block fixes the technical
design each layer builds against. Social is Tier-3 (Database ADR 0003 §3:
rebuildable projection/peripheral, NEVER a source of truth; Deployment ADR 0007
§Tier-3: explicitly allowed to degrade — the integrity-critical core never
blocks on it), group-scoped (Security ADR 0006 §2.6 + ADR-001 exclusion: NO
open-graph follow/friend edges), adds NO second points source (Axiom 5) and NO
group ref to any Round/Prediction/Leaderboard object.**

**Objective (end state):** the Social surface delivered end-to-end at full
Milestone-0 rigor across all six layers — pure `packages/domain/social`, social
DTOs in `contracts`, `application/social` use-cases (all group-membership-gated,
server-authorized, idempotent where applicable, reusing the ratified
`group.not_a_member` gate + `Authorization.requireRole`), a Postgres adapter
over `0008_social.sql` for the ONE new stored surface (Reactions) plus a pure
read-projection reader for the Activity Feed (NO new table), migration
`0008_social.sql` (forward-only, idempotent, group-scoped RLS = member self-read
+ write-privilege revocation backstop), `apps/server` routes behind `bearerAuth`
+ mapper + CompositionRoot wiring + route tests.

**Design-anchors (fixed here; do not re-derive):**

- **`Reaction` aggregate (the ONE new stored Tier-3 surface — decision #2).**
  Root `Reaction` holds: `ReactionId` (UUID value object extending `EntityId`,
  `tryParse` like `GroupId`); `groupId: GroupId` (the social container — every
  reaction is group-scoped, decision #3, reusing the group visibility gate);
  `roundId: RoundId` (the target — a reaction is to a *round-result* within the
  group, decision #1); `userId: UserId` (the author — bound from the verified
  token, never the body); a `ReactionEmoji` value object (the bounded, fixed
  emoji set — NO free text, decision #1); `reactedAt` (UTC, normalized by
  caller). Uniqueness `(groupId, roundId, userId)` — a member has at most one
  live reaction per round-result — is enforced structurally in the schema + the
  use-case, not re-checked in the entity (mirror of `Participant`/
  `GroupMembership`). The reaction carries **NO points field** (Axiom 5) and
  **NO open-graph edge**. Pure/immutable; `create` (new, validated) +
  `fromStored` (rehydrate, typing only); `changeEmoji` produces a new value (a
  member swapping their emoji is an idempotent upsert on the unique key, not a
  second row).
- **`ReactionEmoji` value object.** A closed, fixed set of allowed emoji tokens
  (decision #1: bounded, no free text — so there is nothing to moderate). The
  domain owns the *set*; `tryParse` validates membership so an untrusted emoji
  is a typed validation failure, never stored arbitrary content. Realized as a
  closed `enum ReactionKind` behind the value object (each carries a stable
  `wireValue` token — e.g. `like`/`fire`/`clap`/`laugh`/`sad`/`shock` — and the
  actual emoji glyph is a *client* concern; the wire/storage token is the stable
  contract, mirroring how `GroupRole`/`FixtureScoreGrade` carry wire tokens, not
  presentation).
- **`application/social` (imports domain/shared only — `import_lint` unchanged;
  a `social` slice lives inside the existing `application` package, no new
  internal package).** Repository port `ReactionRepository`
  (`upsertReaction` idempotent per `(groupId, roundId, userId)`,
  `findReaction`, `listReactionsForRound` group+round-scoped,
  `removeReaction`), all total (typed `Result`, infra failures → `transient`;
  unique violation → `social.reaction_conflict` the upsert converges on). A
  read-only `ActivityFeedReader` port (`groupActivityFeed({groupId, limit})` →
  a chronologically-ordered `List<ActivityEvent>` assembled from existing
  ratified data — NO new table, decision #2). Use-cases: `ReactToRound`
  (any `PlatformRole.user`; member-only via the group gate; server-resolves
  author from principal; idempotent upsert — swapping emoji replaces in place),
  `RemoveReaction` (member-only; removes the caller's own reaction; idempotent —
  removing an absent one is a no-op success), `ListRoundReactions`
  (member-only; the round's reactions within the group), `GetGroupActivityFeed`
  (member-only; the pure read projection). A non-member is refused
  `group.not_a_member` with NO existence oracle (decision #3, reusing the exact
  Groups gate via `GroupRepository.findMembership` — no new visibility
  mechanism). **Degradation (decision #4):** these use-cases are the ONLY entry
  to Social; a Social failure is a typed `Result.err` confined to the Social
  endpoint and never propagates into a Tier-1 core use-case (prediction/scoring/
  ledger/leaderboard call sites are untouched).
- **`ActivityEvent` (application read value, not a stored entity).** A
  discriminated read shape carrying: an `ActivityEventType`
  (`round_scored`/`member_joined`/`rank_shift` — decision #1), the `groupId`
  it is scoped to, an `occurredAt` UTC instant for chronological ordering, and
  type-specific payload fields (roundId for `round_scored`; userId for
  `member_joined`; userId + old/new rank for `rank_shift`). Assembled by the
  reader from `group.group_memberships.joined_at` (member joined),
  `competition.rounds` scored-transition + `ledger` postings (round scored),
  and `leaderboard.season_standings` deltas (rank shift) — all existing
  ratified data, never a new writable source.
- **`contracts` social DTOs** — versioned, snake_case, no leakage (mirror
  `group_dto.dart`): `ReactionDto` (id/group_id/round_id/user_id/emoji
  wire-token/reacted_at), `RoundReactionsDto` (group_id + round_id + ordered
  reactions), `ActivityEventDto` (type wire-token + group_id + occurred_at +
  optional round_id/user_id/old_rank/new_rank), `GroupActivityFeedDto`
  (group_id + ordered events). NO points-write field, NO open-graph field
  (Axioms 2/5, ADR-001).
- **`infrastructure/social`** — `PostgresReactionRepository` over
  `0008_social.sql` (`@named` binding only — Security ADR §2; SQLSTATE→typed
  mapping: `23505` `(group_id, round_id, user_id)` unique →
  `social.reaction_conflict` (the upsert `ON CONFLICT DO UPDATE` converges on),
  `23503` FKs → `social.group_not_found`/`social.round_not_found`/
  `social.user_not_found`; malformed row → transient `social.row_corrupt`).
  `PostgresActivityFeedReader` — a pure read over existing aggregates (group
  memberships + scored rounds + leaderboard standings), NO new writable table,
  producing `ActivityEvent`s ordered by `occurred_at desc`.
- **Migration `0008_social.sql`** — `social` schema; `social.reactions`
  (id PK, `group_id` FK → `group.groups` `on delete cascade`, `round_id` FK →
  `competition.rounds` `on delete cascade`, `user_id` FK → `identity.users`
  `on delete restrict`, `emoji` enum `social.reaction_kind`, `reacted_at`,
  unique `(group_id, round_id, user_id)` = physical "one live reaction per
  member per round-result", explicitly-named FK + unique constraints for the
  adapter's 23503/23505 mapping; reuses `identity.set_updated_at`); RLS =
  member-scoped self-read (a caller sees reactions only in groups they belong
  to — reusing the Groups member-scoped self-join, decision #3), all client
  writes revoked (backend service role owns writes — Axiom 6 backstop), anon
  denied. The Activity Feed needs NO table (decision #2 — pure projection). NO
  points source, NO group ref added to any competition/round/prediction/
  leaderboard object (decision #1). Forward-only, idempotent.
- **`apps/server`** — routes behind `bearerAuth` (`groups/_middleware.dart`
  already guards the `/groups` subtree; Social reactions/feed live UNDER
  `/groups/{id}/...` so they inherit it — reactions are group-scoped, decision
  #3): `PUT /groups/{id}/rounds/{roundId}/reactions` (react/change, body =
  `{emoji}`), `DELETE /groups/{id}/rounds/{roundId}/reactions` (remove own),
  `GET /groups/{id}/rounds/{roundId}/reactions` (list, member-gated),
  `GET /groups/{id}/feed` (activity feed, member-gated). Mapper
  `social_dto_mapper.dart` single-place shaping. CompositionRoot `bootstrap`
  wires real `PostgresReactionRepository` + `PostgresActivityFeedReader`;
  `forTesting` gains loud `_absent*`/`_Unwired*` stand-ins. Route tests over an
  `InMemoryReactionRepository` + `InMemoryActivityFeedReader` in the harness.

_Per-file delivery record is appended below as each layer completes; §4 carries
the live checklist._

**Delivery record (per-file) — Social:**
- `packages/domain/social/` — **DONE 2026-07-12** (pure, imports only `shared` +
  domain-internal `group`/`competition`/`identity` ids; `import_lint` ruleset
  unchanged):
  - `reaction_id.dart` — `ReactionId extends EntityId`, `tryParse` (UUID-
    validated, `social.reaction_id_empty`/`social.reaction_id_malformed`);
    distinct id type from `GroupId`/`RoundId`/`UserId`.
  - `reaction_emoji.dart` — `ReactionKind` closed set `{like,fire,clap,laugh,
    sad,shock}` (NO free text — decision #1) with stable `wireValue`;
    `ReactionEmoji` value object (`of` trusted-wrap + `tryParse`
    `social.reaction_emoji_unknown`; an arbitrary glyph/unknown token is a
    validation failure, never stored content). Value-comparable by kind.
  - `reaction.dart` — `Reaction` aggregate root: `create` (validated, UTC
    `reactedAt` `social.reaction_reacted_at_not_utc`), `fromStored`,
    `changeEmoji` (new value, SAME identity + `(groupId,roundId,userId)` key so
    persistence is an idempotent upsert not a second row). Group-scoped
    (`groupId` — decision #3), round-result-targeted (`roundId` — decision #1),
    author `userId`; carries NO points field (Axiom 5) and NO open-graph edge
    (ADR-001). Value-comparable.
  - All three exported from `domain.dart`. Tests: `test/social/reaction_id_test.dart`
    (accept/empty/malformed/distinct-type), `reaction_emoji_test.dart` (closed
    set, stable tokens, round-trip, unknown/null/glyph rejection, value
    equality), `reaction_test.dart` (create + non-UTC reject, changeEmoji
    key-preservation + non-UTC reject, fromStored, equality-over-all-fields,
    no-points-field structural check).
- `packages/contracts/social_dto.dart` — **DONE 2026-07-12** (versioned,
  snake_case, no leakage; depends on nothing — Application ADR §3):
  `ReactionDto` (id/group_id/round_id/user_id/emoji token/reacted_at — NO points
  field, NO open-graph edge), `RoundReactionsDto` (group_id + round_id + ordered
  reactions; empty legitimate), `ActivityEventDto` (type token
  `round_scored`/`member_joined`/`rank_shift` + group_id + occurred_at +
  nullable round_id/user_id/old_rank/new_rank, null fields omitted from JSON),
  `GroupActivityFeedDto` (group_id + events newest-first; empty legitimate).
  Exported from `contracts.dart`. Test `test/social_dto_test.dart` (round-trip,
  snake_case keys, no-points-field, back-compat default schema_version,
  order-significant equality, per-type field presence/omission, empty
  list/feed legitimate).
- `packages/application/social/` — **DONE 2026-07-12 (completed this session;
  a prior session had shipped 2 ports + `activity_event.dart` + `react_to_round.dart`
  on disk but left the 3 remaining use-cases, the ENTIRE `application.dart`
  social export block, and ALL tests untouched — the recurring "code shipped,
  docs untouched" drift; CORRECTED by direct on-disk inspection). Imports
  domain/shared only, `import_lint` ruleset unchanged — a `social` slice inside
  the existing `application` package, no new internal package:**
  - `ports/reaction_repository.dart` — `ReactionRepository` (`upsertReaction`
    idempotent on `(groupId, roundId, userId)`, `findReaction`,
    `listReactionsForRound` reactedAt-asc, `removeReaction` idempotent
    `Ok(bool)`); all total (typed `Result`, infra→`transient`; unique violation
    → `social.reaction_conflict` the upsert converges on). **(prior session)**
  - `ports/activity_feed_reader.dart` — `ActivityFeedReader.groupActivityFeed`
    ({groupId, limit} → newest-first `List<ActivityEvent>`); pure read
    projection, NO table (decision #2). **(prior session)**
  - `activity_event.dart` — `ActivityEventType` closed set
    (`roundScored`/`memberJoined`/`rankShift`, stable `wireValue`) +
    `ActivityEvent` application read value (group-scoped, occurredAt-ordered,
    type-specific nullable fields; NO points field / open-graph edge). **(prior
    session)**
  - `react_to_round.dart` — `ReactToRound` (any `PlatformRole.user`; member-only
    via the reused `group.not_a_member` gate; author from principal never body;
    idempotent upsert — swap emoji in place; concurrent-race convergence on
    `social.reaction_conflict` by re-read). **(prior session)**
  - `remove_reaction.dart` — **NEW this session:** `RemoveReaction` (member-only;
    removes the caller's OWN reaction, userId bound from the principal;
    idempotent — removing an absent one is `Ok(false)` success).
  - `list_round_reactions.dart` — **NEW this session:** `ListRoundReactions`
    (member-only query; the round's reactions within the group, reactedAt-asc;
    empty list legitimate).
  - `get_group_activity_feed.dart` — **NEW this session:** `GetGroupActivityFeed`
    (member-only query; pure read projection via `ActivityFeedReader`; clamps an
    untrusted `limit` to `[1, maxLimit=200]`, null/non-positive → `defaultLimit=50`
    so a Tier-3 read never triggers an unbounded scan — decision #4).
  - **`application.dart` export block ADDED this session** (was entirely absent —
    the prior-session gap): all 7 social symbols now exported
    (`activity_event`, `get_group_activity_feed`, `list_round_reactions`,
    `ports/activity_feed_reader`, `ports/reaction_repository`, `react_to_round`,
    `remove_reaction`).
  - **Tests ADDED this session** under `test/social/`: `fakes.dart`
    (`InMemoryReactionRepository` idempotent-upsert + conflict-script +
    removeReaction; `InMemoryActivityFeedReader` newest-first + limit-recording;
    `principalUser`/`storedMembership`/`storedReaction` builders +
    `FakeIdGenerator`/`FakeClock`; reuses the group harness's
    `InMemoryGroupRepository` for the gate), `react_to_round_test.dart` (7:
    first-react, change-in-place-still-one-row, concurrent-race convergence,
    non-member-refused, unknown-emoji, malformed-id, transient),
    `remove_reaction_test.dart` (5: remove-own, absent-noop, non-member-refused,
    malformed-id, transient), `list_round_reactions_test.dart` (5: ordered read,
    empty-legit, non-member, malformed-id, transient),
    `get_group_activity_feed_test.dart` (9: newest-first, empty-legit,
    null/non-positive/over-cap/in-range limit clamp, non-member, malformed-id,
    transient). No new external dependency; `import_lint` ruleset unchanged.
- `packages/infrastructure/social/` — **DONE 2026-07-12 (the two adapters +
  the `infrastructure.dart` export lines were already on disk from a prior
  session — the recurring "code shipped, docs untouched" drift; the missing
  piece was the tests, ADDED this session, closing the layer). On disk and
  verified real (no TODO/placeholder/mock):**
  - `src/social/postgres_reaction_repository.dart` (297 L) —
    `PostgresReactionRepository` implements the full `ReactionRepository` port
    over `social.reactions`: `upsertReaction` (idempotent
    `INSERT … ON CONFLICT ON CONSTRAINT reactions_group_round_user_uniq
    DO UPDATE SET emoji, reacted_at` — a member swapping emoji refreshes the ONE
    row, never a second; caller id used only on initial insert), `findReaction`
    (Ok(null) on absence), `listReactionsForRound` (`ORDER BY reacted_at ASC,
    id ASC`), `removeReaction` (`DELETE … RETURNING id` → `Ok(true/false)`
    idempotent). `@named` binding only (Security ADR §2); emoji bound as its
    stable `wireValue` token, reacted_at coerced to UTC; SQLSTATE reclassify off
    `ServerException.code`/`.constraintName`: `23505`
    `reactions_group_round_user_uniq` → `social.reaction_conflict` (the pivot
    the upsert converges on), `23503` FKs → `social.group_not_found` /
    `social.round_not_found` / `social.user_not_found`; malformed row →
    transient `social.row_corrupt`. Reuses `postgres 3.5.12` — no new dependency.
  - `src/social/postgres_activity_feed_reader.dart` (181 L) —
    `PostgresActivityFeedReader` implements `ActivityFeedReader` as a **pure
    read projection, NO table** (decision #2): one `UNION ALL` read producing
    `member_joined` (from `"group".group_memberships` for the group) +
    `round_scored` (from `competition.rounds` with `status='scored'`, gated by an
    `EXISTS` over `competition.participants ∩ "group".group_memberships` so only
    rounds relevant to this circle appear — decision #1/#3), ordered
    `occurred_at DESC` and capped at `@limit` (one round-trip, never over-scans —
    Tier-3 read stays cheap, decision #4). `rank_shift` is intentionally NOT
    produced (no stored rank history; the leaderboard is a live projection) —
    deliberately deferred, never faked; the `ActivityEventType.rankShift` shape
    exists so future work is purely additive. `@named` binding; malformed row /
    unknown-kind → transient `social.row_corrupt`.
  - **Exports (already on disk from the shipping session):**
    `packages/infrastructure/lib/infrastructure.dart` has
    `export 'src/social/postgres_activity_feed_reader.dart';` +
    `export 'src/social/postgres_reaction_repository.dart';` — both adapters are
    reachable through the package's public surface, unblocking CompositionRoot
    wiring.
  - **Tests ADDED this session** (mirror the group/ledger/scoring infra test
    style — hermetic fake `PostgresConnection` recording SQL+params with a
    per-call scripted response list):
    - `test/social/postgres_reaction_repository_test.dart` (hermetic, 20 cases
      across all 4 methods): `upsertReaction` (ON CONFLICT upsert SQL shape +
      @named binding + emoji-as-wire-token + UTC reacted_at, swap-in-place same
      id, transient passthrough), `findReaction` (row→Reaction mapping,
      (group,round,user) binding, Ok(null) on absence, transient passthrough,
      six `social.row_corrupt` branches: bad id/group/round/user id, unknown
      emoji token, absent reacted_at), `listReactionsForRound` (reacted_at-asc
      ORDER BY, (group,round) binding, empty-legit, corrupt-row fails list,
      transient), `removeReaction` (`DELETE … RETURNING id` → Ok(true)/Ok(false)
      idempotent, binding, transient). The `ServerException`→`invariant`
      reclassify path is NOT exercised here (the driver exception has no public
      constructor) — documented + deferred to the DB-gated test.
    - `test/social/postgres_activity_feed_reader_test.dart` (hermetic, 10 cases):
      the UNION feed SQL shape (member_joined branch + round_scored branch's
      EXISTS gate + UNION ALL + `ORDER BY occurred_at DESC` + `LIMIT @limit`),
      @group_id/@limit binding, per-kind mapping (member_joined userId set /
      round_scored roundId set, UTC occurredAt), empty-feed Ok(empty), transient
      passthrough, four `social.row_corrupt` branches (absent occurred_at,
      corrupt user_id, corrupt round_id, unknown `kind` discriminator incl.
      `rank_shift` which this reader never produces).
    - `test/social/postgres_social_repositories_integration_test.dart` (DB-gated,
      tagged `integration`, `skip`ped locally so `melos run test` stays
      hermetic; runs in CI against ephemeral Postgres with migrations 0001–0008
      applied): documents the scenarios only a live DB can prove — the
      `ServerException`→typed-`invariant` reclassify for every named constraint
      (`social.reaction_conflict`/`social.group_not_found`/`social.round_not_found`/
      `social.user_not_found`), the real `ON CONFLICT … DO UPDATE` swap-in-place
      (one row survives an emoji swap) + `removeReaction` idempotent RETURNING,
      the live UNION feed group-scoping (a scored round of a season no group
      member plays is excluded; a foreign group's member_joined is excluded) +
      newest-first LIMIT cap, and the group-scoped RLS backstop.
  - No new external dependency (reuses `postgres 3.5.12`);
    `tooling/import_lint` ruleset unchanged (adapters live inside
    `infrastructure`, import `application`/`domain`/`shared` — already permitted).
- `apps/server` (Social routes + mapper + CompositionRoot wiring) — **DONE
  2026-07-12 (the routes + mapper + CompositionRoot wiring + harness in-memory
  repos were ALREADY on disk from a prior session — the recurring "code shipped,
  docs untouched" drift, now the 5th occurrence; §4 had this item as `[ ]` NOT
  STARTED, which was stale. The single genuinely-missing artifact was the route
  test file, ADDED this session; the harness gained a query-parameter stub so
  the feed route's `?limit=` is testable. CORRECTED against direct on-disk
  inspection of every file in the layer):**
  - `apps/server/lib/http/social_dto_mapper.dart` — **already on disk, verified
    correct:** `reactionToDto(Reaction)` (emoji as stable `wireValue` token,
    reactedAt UTC ISO-8601, NO points field — Axiom 5, NO open-graph edge —
    ADR-001) reused by `roundReactionsJson(groupId, roundId, reactions)`;
    `activityEventToDto(ActivityEvent)` (type as stable `wireValue` token, UTC
    occurredAt, nullable per-type fields omitted from JSON) reused by
    `groupActivityFeedJson(groupId, events)`. Single-place shaping.
  - `apps/server/routes/groups/[id]/rounds/[roundId]/reactions/index.dart` —
    **already on disk, verified correct** (125 L): `PUT` react/change (body
    `{emoji}`, author from principal inside the use-case never the body) → `200`
    `ReactionDto`; `DELETE` remove-own → `200` `{removed: bool}` (idempotent);
    `GET` list → `200` `RoundReactionsDto`; `405` otherwise. All authz
    (`group.not_a_member`, no oracle — decision #3) lives in the use-cases; the
    route makes none. Lives UNDER `/groups/{id}/...` so it inherits the
    `/groups` `bearerAuth` subtree (`groups/_middleware.dart`) — no local
    middleware.
  - `apps/server/routes/groups/[id]/feed/index.dart` — **already on disk,
    verified correct** (59 L): `GET` activity feed → `200`
    `GroupActivityFeedDto` (empty events = legitimate empty feed); `405`
    otherwise. Reads an optional `?limit=` (`int.tryParse`; non-integer treated
    as absent), passed to `GetGroupActivityFeed` which clamps to `[1, maxLimit]`
    with null/non-positive → `defaultLimit` (decision #4 — a Tier-3 read never
    over-scans). Member-only gate lives entirely in the use-case.
  - `apps/server/lib/composition/composition_root.dart` — **already on disk,
    verified correct:** private ctor + `bootstrap` build
    `PostgresReactionRepository` + `PostgresActivityFeedReader` and wire the four
    use-cases `reactToRound` / `removeReaction` / `listRoundReactions` /
    `getGroupActivityFeed` (reactions reuse the ratified `GroupRepository` for
    the member gate) as real fields; `forTesting` gained matching optional
    params + loud `_absent*` stand-ins backed by `_UnwiredReactionRepository`
    (full `ReactionRepository`, every method throws `StateError`) +
    `_UnwiredActivityFeedReader`.
  - `apps/server/test/routes/competition_route_harness.dart` — the
    `InMemoryReactionRepository` (one row per `(groupId,roundId,userId)`
    upsert-in-place + idempotent `removeReaction` + reactedAt-asc
    `listReactionsForRound`), `InMemoryActivityFeedReader` (per-group seed,
    newest-first, caps at + records the requested limit), and `storedReaction`
    builder were **already on disk**. **Extended this session:** `wireContext`
    now stubs `request.uri` and accepts an optional `queryParameters` map so the
    feed route's `?limit=` hint is exercisable (default: `/` with no query — a
    route may read `uri` unconditionally without a `MissingStubError`; no
    existing caller changes behaviour).
  - `apps/server/test/routes/social_routes_test.dart` — **NEW this session**;
    real wiring over the in-memory reaction/feed/group repos for both routes.
    PUT react: member-200-one-row (author from token, no points leak),
    re-react-swap-in-place-still-one-row, unknown-emoji-400
    (`social.reaction_emoji_unknown`), missing-emoji-field-400, non-member-401
    (`group.not_a_member`), malformed-group-id-400, transient-503. DELETE:
    own-200-removed-true, absent-200-removed-false, non-member-401. GET list:
    member-200-reactedAt-ordered, empty-200, non-member-401. reactions route
    405. GET feed: member-200-newest-first, empty-200, in-range/over-cap/
    non-integer/missing `?limit=` clamp reaching the reader (10 / maxLimit /
    defaultLimit ×2), non-member-401, transient-503, 405. No new external
    dependency; `tooling/import_lint` ruleset unchanged.
- **Six-way review** `docs/reviews/social-review.md` — **DONE 2026-07-12:**
  GREEN. No High/Medium; findings table in §7 (SO-1 = SSoT drift on the
  `apps/server` item — code was already on disk, recorded `[ ]`; fixed by writing
  the missing route test + correcting §2/§4; SO-note/P-note/M-note/S-verified/
  C-verified info-only). By-construction verification only (sandbox has no Dart
  toolchain — §2 Environment note); "compiles & goes green" to be confirmed via
  `melos bootstrap && melos run verify` on a Dart-3.12+ machine. Exit criterion
  MET — **Social phase COMPLETE & RATIFIED.**

---

**Milestone (Notifications) — Decisions Ratified (product + architecture call,
2026-07-12, FIRST STEP mandate — decided BEFORE any code, mirroring how
`submittedAt` and the Groups/Social decisions were handled; recorded here as
explicit ratified decisions rather than invented silently mid-build). Same
optimization criterion as Social within the Tier-3 constraint of "peripheral,
rebuildable, may degrade, never a source of truth" (Database ADR 0003 §3;
Deployment ADR 0007 §2.4 — Tier-1 must never block on it):**

1. **Trigger surface for v1 — RATIFIED: a minimal high-value set of exactly
   three notification kinds, all derived from already-ratified events.** A
   notification is created for a recipient `User` when:
   - **`round_scored`** — a round the recipient is a `Participant` in was
     scored (i.e. `ScoreRound` transitioned it `locked → scored`). This is the
     single most-awaited moment in the predict-once loop ("did I get points?").
     One notification per participant of the scored round.
   - **`group_member_joined`** — a new member joined a group the recipient owns
     (v1 keeps this owner-only to avoid an N² fan-out: only the group `owner`
     is notified that someone joined via their invite, matching the
     virality/engagement goal without spamming every member). Carries the
     joining user + the group.
   - **`reaction_received`** — another member reacted (Social `ReactToRound`) to
     a round-result in a group the recipient is a member of, targeting a round
     the recipient participated in ("someone reacted to your prediction"). The
     recipient is the round's participant; the actor is the reactor (never
     self — a member reacting to their own round-result notifies no one).
   A full enumeration of every domain event is explicitly rejected for v1 (it
   is almost certainly wrong — noise, and a larger surface than Tier-3
   warrants). Adding a kind later is a forward-only enum extension.
2. **Delivery channel(s) for v1 — RATIFIED: in-app / in-platform notification
   list ONLY.** NO push, NO email, NO SMS. Rationale: an external channel
   introduces a new external dependency (a provider SDK/API), a PII surface
   (email/phone/device tokens) and a deliverability/consent concern — all of
   which are a materially bigger decision than an in-app feed and are out of
   scope for a fast, safe Tier-3 v1 (Security ADR 0006 §2 trust zones; ADR 0007
   §2.4 "may degrade"). The recipient reads their own notification list via a
   `bearerAuth`-protected `GET`, marks items read, and that is the whole v1
   surface. A future push/email channel is purely additive: it would consume
   the SAME stored notifications (a dispatcher reading the table), so the store
   is the durable seam and no rework is needed. Because v1 is in-app-only,
   Notifications introduces **NO new external dependency** (verified in §3).
3. **Projection vs. stored — RATIFIED: genuinely STORED, per-user, MUTABLE
   state — its own table `notification.notifications`.** Unlike Social's
   Activity Feed (a pure projection, decision #2 there), a notification carries
   per-recipient mutable state — a **read/unread** flag and a `read_at`
   timestamp — that has no other home to be derived from, so it MUST be stored.
   This is exactly the "notification preferences / per-user state" Tier-3 table
   that Database ADR 0003 §2.2 ("Notification owns its Tier-3 tables") and §2.4
   ("notification preferences" as a Tier-3-table example) already anticipate.
   It is still Tier-3 (rebuildable in principle from the trigger events; may
   degrade; never a source of truth — carries NO points, NO group ref on any
   core object). Migration `0009_notification.sql` adds this ONE table + its
   closed `notification.notification_kind` enum.
4. **Visibility — RATIFIED: strictly RECIPIENT-ONLY.** A notification belongs to
   exactly one recipient `User`; the read/list/mark gate is "caller ==
   recipient", NOT group-membership. This is a materially simpler (and
   different) gate than every phase since Groups: there is no group/season
   membership check on the read path — a notification row's `user_id` must equal
   the verified principal's `userId`, full stop. A foreign or unknown
   notification is refused identically (`notification.not_found`, an
   authorization refusal) with NO existence oracle (mirror of the Ledger
   self-read `participant_not_found` pattern, NOT the Groups member gate).
   Writes are server-only (Axiom 2/6): the client never creates or addresses a
   notification to anyone — creation is a backend-triggered, idempotent effect
   of the ratified events above.

These four are final for this phase; do not re-litigate them mid-build. If
implementation reveals a genuine gap, document it in §4 and ask, exactly as
`submittedAt` and the Groups/Social decisions were handled.

---

**Milestone (Notifications) — IN PROGRESS (started 2026-07-12). Objective +
technical design-anchors ratified below BEFORE any code (FIRST STEP mandate,
mirroring every prior phase). The four product/architecture decisions are
already RATIFIED above (Milestone (Notifications) — Decisions Ratified); this
block fixes the technical design each layer builds against. Notifications is
Tier-3 (Database ADR 0003 §3: rebuildable/peripheral, NEVER a source of truth;
Deployment ADR 0007 §2.4: explicitly allowed to degrade — the integrity-critical
core never blocks on it), single-user-scoped (decision #4), adds NO second
points source (Axiom 5) and NO group ref to any Round/Prediction/Leaderboard
object.**

**Objective (end state):** the Notifications surface delivered end-to-end at
full Milestone-0 rigor across all six layers — pure
`packages/domain/notification`, notification DTOs in `contracts`,
`application/notification` use-cases (a server-side `NotifyRecipients`-style
creation command triggered from the ratified events + recipient-only reads/
mark-read, all server-authorized, idempotent where applicable, reusing
`Authorization.requireRole`), a Postgres adapter over `0009_notification.sql`
for the ONE new stored surface plus recipient-scoped reads, migration
`0009_notification.sql` (forward-only, idempotent, recipient-scoped RLS =
owner self-read/self-update + write-privilege revocation backstop), `apps/server`
routes behind `bearerAuth` + mapper + CompositionRoot wiring + route tests. The
creation command is wired as an explicit synchronous in-process call at the
ratified trigger sites' composition edge (mirroring the Ledger `PostRoundToLedger`
"command, not event" decision — no unverified async dispatcher this phase; a
future outbox can call the identical use-case).

**Design-anchors (fixed here; do not re-derive):**

- **`Notification` aggregate (the ONE new stored Tier-3 surface — decision #3).**
  Root `Notification` holds: `NotificationId` (UUID value object extending
  `EntityId`, `tryParse` like `ReactionId`); `recipientId: UserId` (the single
  owner — decision #4; bound server-side, never a body); a `NotificationKind`
  value (closed set — decision #1); a `NotificationSubject` value object holding
  the type-specific references (the source `roundId`/`groupId`/actor `userId`
  that let a client render + deep-link the notification, all optional and
  discriminated by kind — carries NO points, NO free text); `createdAt` (UTC);
  and mutable read state — `readAt: DateTime?` (null = unread). Pure/immutable at
  the value level: `create` (new, unread, validated) + `fromStored` (rehydrate,
  typing only); `markRead(DateTime nowUtc)` produces a new value with `readAt`
  set (idempotent — marking an already-read notification returns an equal value,
  never resets the original timestamp). A stable **dedupe key**
  `(recipientId, kind, subjectRef)` makes creation idempotent (a replayed
  trigger never appends a second identical notification — mirror of the Ledger
  dedupe discipline); `subjectRef` is a deterministic string built from the
  subject so the schema can enforce it with a unique constraint.
- **`NotificationKind` enum — closed set `{roundScored, groupMemberJoined,
  reactionReceived}`** (decision #1; NO free text, NO open-graph). `wireValue`
  (`round_scored`/`group_member_joined`/`reaction_received`) + `tryParse`
  mirroring `ReactionKind`/`GroupRole`. The glyph/copy is a client concern; the
  wire/storage token is the stable contract.
- **`NotificationSubject` value object.** The bounded, type-specific reference
  payload discriminated by `NotificationKind`: `roundScored` → `roundId`;
  `groupMemberJoined` → `groupId` + actor `userId` (the joiner); `reactionReceived`
  → `groupId` + `roundId` + actor `userId` (the reactor). Named factories per
  kind validate that exactly the right references are present (an aggregate
  reasons about its own shape). Exposes a deterministic `dedupeRef` (the stable
  string keying the unique constraint — e.g. `round:<id>` /
  `group_join:<groupId>:<userId>` / `reaction:<groupId>:<roundId>:<userId>`),
  so a replay of the same event dedupes and a distinct event does not. Carries
  NO points field (Axiom 5), NO open-graph edge (ADR-001).
- **`application/notification` (imports domain/shared only — `import_lint`
  unchanged; a `notification` slice lives inside the existing `application`
  package, no new internal package).** Repository port `NotificationRepository`
  (`createIfAbsent` idempotent on `(recipientId, kind, subjectRef)` →
  `Ok(created?)`; `listForRecipient` newest-first with a clamped limit;
  `findById`; `markRead` recipient-scoped; `unreadCount`), all total (typed
  `Result`, infra→`transient`; unique violation → `notification.duplicate`
  which `createIfAbsent` converges on as a skip). Use-cases:
  - `NotifyRoundScored` / `NotifyGroupMemberJoined` / `NotifyReactionReceived` —
    a small set of **server-side creation commands** (NOT client-callable; no
    `Authorization.requireRole(user)` self-gate — these are triggered by the
    backend after a ratified event, taking already-resolved recipient/subject
    inputs, and produce idempotent `createIfAbsent` writes). Realized behind a
    single narrow `NotificationDispatcher`-style facade use-case `CreateNotification`
    that all three delegate to (one idempotent create path), so the trigger
    sites depend on one thing. **Tier-3 degradation (decision #4/ADR 0007
    §2.4):** a creation failure returns a typed `Result.err` confined to the
    notification call; the trigger site (ScoreRound/JoinGroup/ReactToRound) does
    NOT propagate it into the Tier-1 result — the notification is best-effort.
  - `ListMyNotifications` (recipient-only; the caller's own newest-first list,
    clamped `[1, maxLimit]`), `MarkNotificationRead` (recipient-only; marks the
    caller's own notification read, idempotent; a foreign/unknown id →
    `notification.not_found` with NO existence oracle — decision #4, mirror of
    the Ledger self-read), `GetUnreadCount` (recipient-only; the caller's unread
    total). The recipient is always the verified principal, never a body
    (Security ADR §2).
- **`contracts` notification DTOs** — versioned, snake_case, no leakage (mirror
  `social_dto.dart`): `NotificationDto` (id/recipient_id/kind wire-token/
  read/read_at/created_at + type-specific nullable round_id/group_id/actor_user_id,
  null fields omitted from JSON), `NotificationListDto` (recipient_id + ordered
  notifications + unread_count). NO points-write field, NO open-graph field
  (Axioms 2/5, ADR-001).
- **`infrastructure/notification`** — `PostgresNotificationRepository` over
  `0009_notification.sql` (`@named` binding only — Security ADR §2;
  SQLSTATE→typed mapping: `23505` `notifications_dedupe_uniq` →
  `notification.duplicate` (the `createIfAbsent` `ON CONFLICT DO NOTHING`
  converges on — a replay is a skip, returns `Ok(false)` created), `23503` FKs →
  `notification.recipient_not_found` etc.; malformed row → transient
  `notification.row_corrupt`). Recipient-scoped reads (`listForRecipient`
  `ORDER BY created_at DESC, id DESC LIMIT @limit`; `unreadCount`
  `WHERE read_at IS NULL`; `markRead` `UPDATE … WHERE id AND recipient_id
  RETURNING` so a foreign id updates nothing → the use-case reports not-found).
- **Migration `0009_notification.sql`** — `notification` schema;
  `notification.notification_kind` enum
  `{round_scored, group_member_joined, reaction_received}`;
  `notification.notifications` (id PK, `recipient_id` FK → `identity.users`
  `on delete cascade` — a deleted user's notifications go with them, Tier-3
  cascades freely per DB ADR §2.3; `kind` enum; nullable `round_id` FK →
  `competition.rounds` `on delete cascade`, `group_id` FK → `"group".groups`
  `on delete cascade`, `actor_user_id` FK → `identity.users` `on delete cascade`
  — all named explicitly for the adapter's 23503 map; `subject_ref` text
  (the deterministic dedupe string); `read_at` nullable timestamptz;
  `created_at`; unique `notifications_dedupe_uniq (recipient_id, kind,
  subject_ref)` = physical "one notification per recipient per distinct event"
  — the adapter's `ON CONFLICT` target; reuses `identity.set_updated_at`);
  index `notifications_recipient_stream_idx (recipient_id, created_at desc, id
  desc)` for the list read + a partial `notifications_recipient_unread_idx
  (recipient_id) where read_at is null` for the unread count. RLS =
  recipient-scoped self-read (`recipient_id = auth.uid()`) + self-update of ONLY
  the read state (client insert/delete revoked — backend service role owns
  creation; a permissive self-update policy is allowed for the read-flag toggle
  since marking-read is the one client-safe Tier-3 mutation, but write privileges
  are still revoked/granted narrowly and the app gate is primary — Axiom 6
  backstop), anon denied. NO points column (Axiom 5), NO group ref on any
  competition/round/prediction/leaderboard object (decision #1/#3). Forward-only,
  idempotent.
- **`apps/server`** — routes behind `bearerAuth` (`notifications/_middleware.dart`
  applies it to the `/notifications` subtree, mirror of `/participants`):
  `GET /notifications` (the caller's own list; optional `?limit=`),
  `GET /notifications/unread_count` (the caller's unread total),
  `POST /notifications/{id}/read` (mark the caller's own notification read).
  There is NO client route that CREATES a notification (decision #4 — creation
  is server-triggered only); the creation use-cases are wired into the
  CompositionRoot and invoked from the ScoreRound/JoinGroup/ReactToRound trigger
  edge as best-effort Tier-3 effects (a failure is logged/swallowed, never
  fails the Tier-1 operation). Mapper `notification_dto_mapper.dart` single-place
  shaping. CompositionRoot `bootstrap` wires real `PostgresNotificationRepository`
  + the create/read use-cases; `forTesting` gains loud `_absent*`/`_Unwired*`
  stand-ins. Route tests over an `InMemoryNotificationRepository` in the harness.

_Per-file delivery record is appended below as each layer completes; §4 carries
the live checklist._

**Delivery record (per-file) — Notifications:**
- `packages/domain/notification/` — **DONE 2026-07-12** (pure, imports only
  `shared` + domain-internal `identity` `UserId` / `competition` `RoundId` /
  `group` `GroupId`; `import_lint` ruleset unchanged):
  - `notification_id.dart` — `NotificationId extends EntityId`, `tryParse`
    (UUID-validated, `notification.notification_id_empty`/`_malformed`); distinct
    id type from `UserId`/`RoundId`/`GroupId`/`ReactionId`.
  - `notification_kind.dart` — `NotificationKind` closed set `{roundScored,
    groupMemberJoined, reactionReceived}` (decision #1, NO free text) with stable
    `wireValue` (`round_scored`/`group_member_joined`/`reaction_received`) +
    `tryParse` (`notification.kind_unknown`).
  - `notification_subject.dart` — `NotificationSubject` value object: the
    bounded, kind-discriminated reference payload (roundScored→roundId;
    groupMemberJoined→groupId+actorUserId; reactionReceived→groupId+roundId+
    actorUserId) via named factories + `fromStored`; deterministic `dedupeRef`
    (`round:<id>` / `group_join:<gid>:<uid>` / `reaction:<gid>:<rid>:<uid>`)
    keying the idempotency constraint (replay dedupes, distinct event does not);
    NO points field (Axiom 5), NO open-graph/free-text (decision #1).
    Value-comparable.
  - `notification.dart` — `Notification` aggregate root: `create` (unread,
    validated — subject-kind must match notification kind
    `notification.subject_kind_mismatch`, UTC `createdAt`
    `notification.created_at_not_utc`), `fromStored`, `markRead(nowUtc)` (sets
    `readAt`; **idempotent** — re-marking a read notification returns an equal
    value preserving the original timestamp; UTC-gated
    `notification.read_at_not_utc`). Recipient-scoped (`recipientId` — decision
    #4), NO points field (Axiom 5), NO open-graph edge (ADR-001). Only mutable
    state is the read flag. Value-comparable.
  - All four exported from `domain.dart`. Tests: `test/notification/
    notification_id_test.dart` (accept/empty/malformed/distinct-type),
    `notification_kind_test.dart` (closed 3-set, stable tokens, round-trip,
    unknown/null reject), `notification_subject_test.dart` (per-kind factories,
    deterministic + kind-specific + replay-stable + distinct-event dedupeRef,
    value equality, fromStored), `notification_test.dart` (create + subject-kind
    mismatch + non-UTC reject, markRead sets/idempotent-preserves/non-UTC reject,
    value equality over all fields incl. createdAt sensitivity).
- `packages/contracts/lib/src/notification_dto.dart` — **DONE 2026-07-12**
  (pure wire shapes, no dependency — Application ADR §3): `NotificationDto`
  (id/recipientId/kind/read/createdAt/readAt?/roundId?/groupId?/actorUserId?,
  versioned `schemaVersion`, `fromJson`/`toJson` with null subject fields
  omitted, value equality) and `NotificationListDto` (recipientId/
  notifications newest-first/unreadCount, versioned, `fromJson`/`toJson`,
  value equality). NO points field (Axiom 5), NO open-graph edge (ADR-001);
  kind carried as a stable wire token only. Exported from `contracts.dart`.
  **This record was missing from the delivery log at the same time §4 still
  showed the checklist item unchecked — corrected together 2026-07-13.**
- `packages/application/notification/` — **DONE 2026-07-13** (verified on disk +
  exported; imports domain/shared only, `import_lint` ruleset unchanged — a
  `notification` slice inside the existing `application` package, no new internal
  package):
  - `ports/notification_repository.dart` — `NotificationRepository`
    (`createIfAbsent` idempotent on the dedupe key `(recipientId, kind,
    subjectRef=NotificationSubject.dedupeRef)` → `Ok(created?)`;
    `listForRecipient` newest-first createdAt-desc/id-desc with a clamped
    `limit`; `findForRecipient` recipient-scoped → `Ok(null)` foreign/absent;
    `markRead` recipient-scoped → `Ok(true)` unread→read / `Ok(false)`
    already-read / `Ok(null)` foreign-or-absent; `unreadCount`
    `read_at IS NULL`). All total (typed `Result`, infra→`transient`; unique
    violation → `notification.duplicate` the create converges on as a skip).
  - `create_notification.dart` — `CreateNotification` server-side idempotent
    creation facade (NOT client-callable — decision #4; no self-role gate;
    generates id via `IdGenerator`, stamps UTC `createdAt` via `Clock`,
    `createIfAbsent`). The one create path the three trigger commands delegate
    to. Returns `Ok(true)` new / `Ok(false)` replay.
  - `notify_round_scored.dart` / `notify_group_member_joined.dart` /
    `notify_reaction_received.dart` — the three server-side trigger commands
    (decision #1), each delegating to `CreateNotification`.
    `NotifyGroupMemberJoined` targets the group OWNER (owner-only, no N² fan-out).
    `NotifyReactionReceived` suppresses a self-reaction (`recipientId ==
    actorUserId` → silent `Ok(false)`, never a self-notification). Tier-3
    (decision #4/ADR 0007 §2.4): a failure is a typed `Result.err` the trigger
    site treats as best-effort, never blocking the Tier-1 op.
  - `list_my_notifications.dart` — `ListMyNotifications` (recipient-only —
    decision #4, NO membership check; clamps `limit` to `[1, maxLimit=200]`,
    null/non-positive → `defaultLimit=50`).
  - `get_unread_count.dart` — `GetUnreadCount` (recipient-only badge count).
  - `mark_notification_read.dart` — `MarkNotificationRead` (recipient-only,
    idempotent; a foreign/unknown id → `notification.not_found`
    authorization refusal with NO existence oracle — mirror of the Ledger
    self-read; stamps read-at from `Clock`).
  - ALL 7 symbols + the port exported from `application.dart`. Tests under
    `test/notification/`: `fakes.dart` (`InMemoryNotificationRepository`
    idempotent create + recipient-scoped list/find/mark/count + transient-script
    + limit-recording; `principalUser`/`storedRoundScored` builders +
    `FakeIdGenerator`/`FakeClock`), `create_notification_test.dart` (6: create,
    dedupe replay, distinct-event, subject/kind-mismatch, malformed-id,
    transient), `notify_triggers_test.dart` (9 across the 3 commands: create +
    subject shape, dedupe replay ×3, owner-target, self-reaction suppression,
    transient), `list_my_notifications_test.dart` (10: recipient-scoped
    newest-first, empty-legit, limit clamp ×4 + GetUnreadCount own-only/zero/
    transient), `mark_notification_read_test.dart` (6: mark, idempotent-preserve,
    foreign not_found, unknown not_found, malformed-id, transient). No new
    external dependency; `import_lint` ruleset unchanged.
- `packages/infrastructure/lib/src/notification/postgres_notification_repository.dart`
  — **DONE 2026-07-13** (`PostgresNotificationRepository implements
  NotificationRepository`, total/no-throw — Application ADR §2): `createIfAbsent`
  is `INSERT ... ON CONFLICT ON CONSTRAINT notifications_dedupe_uniq DO NOTHING
  RETURNING id` (row → `Ok(true)`, no row → `Ok(false)`, never a second row);
  recipient-scoped `listForRecipient`/`findForRecipient`/`markRead`/`unreadCount`
  (a foreign id is invisible — no existence oracle); driver failure →
  `ErrorKind.transient`, malformed row → `notification.row_corrupt`; all values
  bound via `@named` params (Security ADR §2). Exported from
  `infrastructure.dart`. Assumes migration `0009_notification.sql`'s exact shape
  (`notification.notifications`, the `notifications_dedupe_uniq` constraint) —
  **that migration does not exist yet; this adapter is written ahead of it and
  cannot run until it lands.**
  **GAP (real, not documentation): every prior phase has a matching
  `packages/infrastructure/test/<domain>/` suite (`test/social`, `test/group`,
  `test/scoring`, etc.); this file has none. Added as its own §4 checklist line
  so it isn't silently absorbed into the generic "Tests at every layer" item.**
  **RESOLVED 2026-07-13 (see the two records below): the migration landed and
  the missing test suite was written — both verified on disk.**
- `supabase/migrations/0009_notification.sql` — **DONE 2026-07-13** (verified on
  disk). The physical schema the adapter above already assumes. Creates the
  `notification` schema; the closed `notification.notification_kind` enum with
  EXACTLY the three domain wire tokens (`round_scored`, `group_member_joined`,
  `reaction_received` — decision #1); and the `notification.notifications` table
  with columns `(id, recipient_id, kind, round_id, group_id, actor_user_id,
  subject_ref, read_at, created_at)` — matching the adapter's INSERT/SELECT/
  UPDATE column lists verbatim. Constraint names are the adapter contract (its
  `ON CONFLICT ON CONSTRAINT` target + 23505/23503 → typed-error map): the
  idempotency `notifications_dedupe_uniq unique (recipient_id, kind,
  subject_ref)` (→ `notification.duplicate`) and the four FKs
  `notifications_recipient_id_fkey`/`_round_id_fkey`/`_group_id_fkey`/
  `_actor_user_id_fkey` (→ identity.users / competition.rounds / "group".groups /
  identity.users, all ON DELETE CASCADE; → `notification.recipient_not_found` /
  `round_not_found` / `group_not_found` / `actor_not_found`). Two recipient-read
  indexes: `notifications_recipient_created_idx (recipient_id, created_at desc,
  id desc)` serving the newest-first list ORDER BY, and partial
  `notifications_recipient_unread_idx (recipient_id) WHERE read_at IS NULL`
  serving the unread count. RLS: recipient self-read `recipient_id = auth.uid()`
  (decision #4 — a simpler gate than Groups/Social's membership join, valid
  because identity.users.id IS the Supabase Auth subject UUID per 0001) + client
  write revocation, service role owns all writes (Axiom 6, Security ADR §2 / DB
  ADR §10). Carries NO points column (Axiom 5), NO free-text/open-graph edge
  (decision #1 / ADR-001); `read_at` is the ONLY mutable column so there is
  deliberately NO `updated_at`/`set_updated_at` trigger (unlike
  social.reactions / the group tables). Forward-only, expand-only, re-runnable
  (guarded `create … if not exists`, `drop policy if exists`).
- `packages/infrastructure/test/notification/` — **DONE 2026-07-13** (verified on
  disk). Closes the real test gap flagged above; mirrors `test/social/` exactly.
  - `postgres_notification_repository_test.dart` — hermetic (fake
    `PostgresConnection` recording SQL+params, replying with scripted `Result`s;
    no live DB). Drives every pure branch the adapter owns: `createIfAbsent`
    (RETURNING row → `Ok(true)`; empty conflict-skip → `Ok(false)`; wire-token/
    `subject_ref` dedupeRef/UTC binding across all three kinds; read_at binding;
    transient pass-through), `listForRecipient` (recipient+limit binding,
    `ORDER BY created_at DESC, id DESC`, three-kind mapping, empty, read-row
    mapping, corrupt-fails-list, transient), `findForRecipient` (id+recipient
    binding, mapping, `Ok(null)` on foreign/absent = no oracle, corrupt id/
    recipient/kind/created_at/read_at + each kind's missing required subject
    ref, transient), `markRead` (the two-query disambiguation: transition →
    `Ok(true)` single query; already-read owned → `Ok(false)` via the existence
    probe; foreign/absent → `Ok(null)`; transient on either query),
    `unreadCount` (recipient binding, int/BigInt/text coercion, zero-legit,
    empty-result-corrupt, non-numeric-corrupt, transient).
  - `postgres_notification_repository_integration_test.dart` — DB-gated
    (`@Tags(['integration'])`, skipped locally), matching every prior phase's
    integration peer. Captures the driver-only path a fake cannot exercise —
    `_reclassify`'s `ServerException` SQLSTATE→constraint→typed-error map (the
    five named constraints above), the real `ON CONFLICT DO NOTHING` single-row
    idempotency, the live recipient-scoped guarded mark, the enum type boundary,
    and the recipient self-read RLS backstop — to be run in CI's integration job
    against an ephemeral Postgres with migrations 0001–0009 applied.
- `apps/server` (Notifications routes + mapper + CompositionRoot wiring) —
  **DONE 2026-07-13 (verified on disk this session by direct inspection of every
  file in the layer).** `notification_dto_mapper.dart` (present & correct —
  `notificationToDto` + `notificationListJson`; kind as stable wire token, UTC
  ISO-8601 instants, no points field / open-graph edge, null subject fields
  omitted). Three recipient-facing route files under
  `apps/server/routes/notifications/` (`_middleware.dart` `bearerAuth`,
  `index.dart` GET list + separate whole-inbox unread_count, `unread_count/
  index.dart` GET, `[id]/read/index.dart` POST mark), all present. **The
  session-42 compile break is FIXED and CONFIRMED at the call site
  (notifications-review §6/N-1):** the private ctor's three `required` params
  (`listMyNotifications`/`getUnreadCount`/`markNotificationRead`) are all backed
  by fields, `bootstrap()` builds one `PostgresNotificationRepository(connection)`
  and passes all three use-cases to `CompositionRoot._(...)` with signatures
  matching verbatim, `forTesting` supplies matching optional params +
  `_absent*` stand-ins backed by `_UnwiredNotificationRepository` (full port,
  every method throws `StateError`), and no other `CompositionRoot._` /
  `.forTesting` call site is broken. No code change was required.
- **Route tests** `apps/server/test/routes/notifications_routes_test.dart`
  (458 L) — **DONE (verified on disk).** Real edge→use-case→domain→port wiring
  over `CompositionRoot.forTesting` + a harness `InMemoryNotificationRepository`
  (recipient-scoped, no existence oracle, scriptable transient, `lastLimit`
  probe) + `storedNotification` builder + `wireContext` `queryParameters` stub.
  Covers list (own-only, newest-first, empty-legit, `?limit=` clamp ×4: in-range
  / over-cap / non-integer / missing, 503, 405), unread_count (own-only excludes
  foreign, zero-legit, 503, 405), mark-read (transition 200 read:true, idempotent
  no-op 200 read:false preserving original `readAt`, foreign id → 401
  `notification.not_found`, unknown id → same code/no oracle, malformed id → 400,
  503, 405).
- **Six-way review** `docs/reviews/notifications-review.md` — **DONE 2026-07-13
  (this session):** GREEN. No High/Medium defect; findings table in §7 (N-1/N-2/
  N-3 verified-OK, P-note/S-verified/M-note info-only). **No code change was
  required** — every layer was verified already-correct on disk by direct
  inspection, and the previously recorded session-42 compile break was confirmed
  already-fixed and correct at the `CompositionRoot._(...)` call site.
  By-construction verification only (sandbox has no Dart toolchain — §2
  Environment note); "compiles & goes green" to be confirmed via
  `melos bootstrap && melos run verify` on a Dart-3.12+ machine, and the
  DB-gated integration test in CI against ephemeral Postgres with migrations
  0001–0009 applied. Exit criterion MET — **Notifications phase COMPLETE &
  RATIFIED.**

---

**Milestone (Admin Panel) — Decisions Ratified (product + architecture call,
2026-07-13, FIRST STEP mandate — decided BEFORE any code, mirroring how the four
Notifications decisions were ratified in this section before any Notifications
code was written; recorded here as explicit ratified decisions rather than
invented silently mid-build). Of the five open questions raised in §4, THREE are
ratified below by explicit logic anchored in already-accepted ADRs (no guessing),
and the architectural spine of the remaining two is ratified while a single
residual product sub-question in each is held OPEN in §4 (scope of user
sanctions; breadth/retention of the audit surface). No domain/application/
infrastructure/migration/route code is written until those two OPEN items are
answered — same discipline every prior phase followed.**

1. **Reuse vs. new surfaces (§4 Q2) — RATIFIED: admin actions REUSE the existing
   ratified use-cases under an admin-elevated caller wherever an equivalent
   already exists; a NEW use-case is authored ONLY where the capability has no
   ratified equivalent.** This is not a fresh product choice — it is what
   Application ADR 0002 (Clean-Architecture single-responsibility use-cases, one
   authoritative writer) and API ADR 0004 §2.2 already force: §2.2 already
   enumerates the admin/service command surface as the SAME commands the platform
   owns — "create competitions/seasons/rounds, add fixtures, and lock a round"
   (admin-scoped), "finalize a fixture result and issue a correction"
   (admin/service-role scoped), and ledger "manual adjustment and bonus …
   admin-only." Admin does NOT get a parallel copy of these; it invokes
   `CreateCompetition` / `StartSeason` / `OpenRound` / `LockRound` /
   `LinkFixtureToRound` / `RecordFixtureResult` / (ledger) `PostRoundToLedger`'s
   sibling adjust/bonus commands with `Authorization.requireRole(principal,
   PlatformRole.admin)` at the front of the pipeline. Duplicating a use-case with
   an "admin" prefix would violate the single-writer rule and the dependency
   discipline enforced by `tooling/import_lint`. A new use-case is justified ONLY
   for a capability with no ratified equivalent (see Q1 below: user suspension has
   a domain hook but no use-case; Group/Social moderation has neither).
2. **Access-control model (§4 Q3) — RATIFIED: "admin" is the EXISTING
   `PlatformRole.admin` on the already-shipped identity/JWT model, NOT a separate
   authentication path.** This is fully determined by code already on disk and by
   Security ADR 0006 §2.2/§2.3 — it requires zero invention:
   - `packages/domain/lib/src/identity/platform_role.dart` already defines the
     closed enum `PlatformRole { user, admin, service }` with `tryParse` /
     `fromClaimOrUser` mapping an untrusted JWT claim (defaulting to `user`).
   - `packages/domain/lib/src/identity/authenticated_user.dart` already defines
     `hasRole` with the ratified hierarchy **`service ⊇ admin ⊇ user`**.
   - `packages/application/lib/src/identity/authorization.dart` already exposes
     the pure, total `Authorization.requireRole(principal, PlatformRole.admin)`
     returning `ErrorKind.authorization` (`auth.insufficient_role`) — the exact
     role/permission layer Security ADR §2.3 mandates as the FIRST of the two
     mandatory authorization layers.
   An admin principal is therefore distinguished from a normal `AuthenticatedUser`
   at the route/`Authorization` layer by its `role` claim, verified server-side
   from the Supabase JWT exactly as every existing route does — no new auth path,
   no new middleware shape. (Operational MFA for admin accounts — Security ADR
   §2.2 — is an identity-provider configuration concern, ADR 0006 §6 "Deferred to
   Implementation," not a code surface this phase introduces.)
3. **Delivery surface for this phase (§4 Q5) — RATIFIED: BACKEND ROUTES ONLY
   (`apps/server`); NO admin UI this phase.** Roadmap ADR 0008 (§1) lists
   **Flutter App as phase 12, separate and last**, after Admin Panel (phase 11);
   Application ADR 0002 §2.14 keeps a strict client/server build split where
   integrity-critical, service-role write paths are compiled only into
   `apps/server` and never shipped to a client. An admin console is a client
   surface and therefore belongs to the Flutter phase, consuming this phase's
   routes. This phase delivers the six-layer backend (domain where a genuinely new
   capability needs it → contracts → application → infrastructure → migration →
   `apps/server` routes + route tests) and NOTHING client-facing, exactly like
   every prior backend phase.

**Architectural spine ratified for the two decisions with a residual OPEN product
sub-question (the sub-questions themselves are documented in §4, NOT answered
here — no code proceeds until they are):**

4. **Scope — reused-command core RATIFIED; user-sanction breadth OPEN (§4 Q1).**
   The portion of the candidate surface that maps onto already-ratified commands
   is IN SCOPE by decision #1 above (competition/season/round authoring, round
   lock, fixture-result finalize/correct, ledger adjust/bonus — all already
   admin-scoped in API ADR 0004 §2.2). The genuinely NEW capabilities have no
   ratified equivalent and are NOT self-decidable from the ADRs: **(a) suspend/
   ban a user** — the domain already ships the hook (`UserStatus.suspended`,
   "suspended by an administrator," with `canAct` gating), but NO use-case
   transitions a user into it, and the exact sanction vocabulary is a product
   call; **(b) moderate Groups/Social** (remove a reaction, dissolve a group,
   remove a member) — neither a domain hook nor a use-case exists, and Security
   ADR §2.6 frames moderation as a policy surface, not a settled command set.
   → **Held OPEN in §4 (needs product decision): which sanctions/moderation verbs
   are in v1.** Cross-user read-for-support (viewing another participant's ledger)
   is also flagged there, as it widens the recipient-only/self-read gate every
   prior read path enforced.
5. **Audit trail — MANDATORY-in-principle RATIFIED; storage breadth OPEN (§4
   Q4).** That every privileged admin action is attributably, immutably logged is
   NOT optional and is not a fresh product choice: Security ADR 0006 §2.2 makes
   admin/service the "narrowest, most-audited surface," §2.4 requires every
   ledger-touching action to carry an immutable, attributable trace (`created_by`,
   `source_ref` — already realized by `PointEntry.sourceRef`, e.g.
   `round_score:<roundId>:<participantId>` in `PostRoundToLedger`), and §4
   "Consequences" states the crown-jewel asset cannot be altered by anyone,
   including an admin, "without an immutable, attributable trace." So an admin
   audit record IS required. What is NOT self-decidable — and mirrors exactly how
   Notifications decision #3 needed a storage call — is the STORAGE SHAPE and
   BREADTH: is there ONE general append-only `admin.audit_log` Tier covering all
   admin actions (its own migration, like `0009_notification.sql` was for
   Notifications), and does it cover ALL admin actions or only the crown-jewel
   (ledger/result) ones the ADR names explicitly? That is a product/architect
   scoping decision. → **Held OPEN in §4 (needs product decision): audit storage
   breadth + retention.**

These ratifications (decisions #1/#2/#3/#5-spine) are final for this phase;
these two are RESOLVED (see the RATIFIED block in §4, STOP CONDITION LIFTED
2026-07-13) — kept here for historical record only, do not re-litigate.

---

**`packages/domain/admin/` + `packages/domain/identity/user.dart` amendment —
PARTIALLY DONE (auditor-verified on disk 2026-07-13; UNDOCUMENTED by the
session that wrote it — 7th occurrence of "code shipped, docs untouched" in
this project's history; corrected here):**

- `AuditEntry` (+ `AuditAction`, `AuditEntryId`) — **PRESENT & COMPLETE.**
  Pure, immutable, no mutation API (append-only by construction), mandatory
  non-blank/length-bounded reason, opaque `targetRef` (provenance not FK),
  no points field. Exported from `domain.dart`. Fully tested:
  `audit_entry_test.dart`, `audit_action_test.dart`, `audit_entry_id_test.dart`
  all present.
- `User.suspend()` / `User.reinstate()` — **PRESENT, but UNTESTED.** Added to
  the existing `User` entity (not a separate file). `suspend()` is idempotent,
  refuses a `service` principal (`identity.cannot_suspend_service`).
  `reinstate()` is the pure mirror, idempotent when already active. **Zero
  test coverage** — verified by grep across every `packages/domain/test/`
  file for `.suspend()`/`.reinstate()` calls: no matches. The existing
  `identity_test.dart` only covers `canAct` with a pre-set suspended status,
  NOT these two new transition methods.
- **RESOLVED (2026-07-13):** `User.suspend()`/`reinstate()` are now fully
  tested — 9 new cases added to `packages/domain/test/identity/
  identity_test.dart` (idempotency both directions, `service`-principal
  refusal both from active and already-suspended, the active↔suspended round
  trip, and the `canAct` interaction). Domain layer for this phase is
  genuinely closed. `packages/contracts/lib/src/admin_dto.dart` also
  DONE 2026-07-13 — see §4 for the precise next element.

**Milestone (Admin Panel) — delivery record (per-file), appended as each layer
completes:**
- `packages/domain/test/identity/identity_test.dart` — **DONE 2026-07-13
  (BLOCKER cleared).** Added three test groups covering the previously-untested
  `User.suspend()`/`reinstate()` transitions (verified by grep there were zero
  before): `group('User.suspend')` (active→suspended for user + admin;
  idempotent when already suspended returns an EQUAL value not an error;
  original value untouched — immutability; `service`-principal refusal
  `identity.cannot_suspend_service` as an `invariant`; the service check
  precedes the idempotency short-circuit even when already suspended),
  `group('User.reinstate')` (suspended→active; idempotent when already active;
  reinstate does NOT gate on role — a suspended admin reinstates), and
  `group('User suspend/reinstate round trip')` (active→suspend→reinstate returns
  a value equal to the start; `canAct` false while suspended, restored on
  reinstate). No production code changed — tests only, matching the on-disk
  `suspend()`/`reinstate()` contract exactly.
- `packages/contracts/lib/src/admin_dto.dart` — **DONE 2026-07-13** (versioned,
  snake_case, no leakage; depends on nothing — Application ADR §3):
  `SuspendUserRequestDto` (the ONLY client-supplied admin command body — the
  mandatory sanction `reason`; nullable on the wire only so a missing field is a
  use-case validation failure, never a silent empty sanction; reused verbatim by
  both suspend + reinstate — decision OPEN-A #1; NO points/target-id in body),
  `UserSanctionResultDto` (user_id + resulting `status` `active`/`suspended`,
  matching `UserStatus.name`; server-produced), `AuditEntryDto` (read projection
  of the domain `AuditEntry`: id/actor_id/action wire-token/target_ref/reason?/
  occurred_at — `reason` key OMITTED from JSON when null; action as a stable wire
  token matching `AuditAction.wireValue`, never a Dart enum name; NO points
  field — Axiom 5), `AuditLogDto` (read projection of the append-only
  `admin.audit_log`: newest-first `entries`, empty list legitimate). Exported
  from `contracts.dart` (alphabetical, before `competition_dto.dart`). Test
  `test/admin_dto_test.dart` (round-trip + snake_case keys, back-compat default
  schema_version, missing-reason→null, no-points-field, action-as-wire-token,
  reason-omitted-when-null + re-parse, order-significant equality for the log,
  empty-trail legitimate). No new external dependency.

---

**Session 46 auditor re-verification (2026-07-13, independent re-check against
a parallel/competing snapshot that had drifted back to claiming infrastructure/
routes "not started" and did not surface DEFECT AD-1 at all — that parallel
doc is WRONG and is discarded). Re-confirmed by direct content inspection,
not by trusting either prior doc:**
- DEFECT AD-1 is real: `composition_root.dart` L51–54 mark the four admin
  use-cases `required`; `bootstrap()`'s `return CompositionRoot._(...)`
  (L725–844) stops at `markNotificationRead` and never builds or passes
  `PostgresUserAdminRepository`/`PostgresAuditLogRepository`/`AuditRecorder`
  nor the four use-cases — production `bootstrap` does not compile. Only the
  `forTesting` `_absent*` throwing stand-ins reference these types (L167–171,
  L427–450); `idGenerator` (L632), `clock` (L633), `participantReader`
  (L661), `ledgerRepository` (L660) are all already in scope before L723, so
  the fix is additive-only.
- Ctor names re-verified against the actual files (not assumed):
  `SuspendUser({required UserAdminRepository users, required AuditRecorder auditRecorder})`,
  `ViewParticipantLedger({required ParticipantReader participantReader, required LedgerRepository ledgerRepository, required AuditRecorder auditRecorder})`,
  `ListAuditLog({required AuditLogRepository auditLog})` — all match the
  EXACT FIX block below verbatim.
- Mandatory-reason claim re-verified at the use-case level (not domain level —
  domain's `AuditEntry.create` only rejects a *blank* reason when one is
  supplied; it's `SuspendUser._requireReason` that makes it mandatory).
  `suspend_user_test.dart` has 15 tests incl. blank/null reason refusal.
- Migration `0010_admin.sql` re-confirmed: 256 lines, RLS deny-all, full
  privilege REVOKE, immutability trigger, named FK `audit_log_actor_id_fkey`.
- `infrastructure.dart` exports re-confirmed at L7–8 (not L8–9 as a prior doc
  said — trivial off-by-one, noted for accuracy only).
- Routes confirmed present: `admin/users/[id]/suspend`, `.../reinstate`,
  `admin/participants/[id]/ledger`, `admin/audit`, `_middleware.dart` (reuses
  `bearerAuth()`, authz inside use-cases).

No new defects found beyond AD-1. Proceeding to executor with the fix as the
first unchecked §4 item, unchanged from below.

**Admin Panel — FULL on-disk audit 2026-07-13 (auditor session, by direct
content inspection of EVERY admin file across all six layers — not name-only).
The code raced FAR ahead of this doc AGAIN: the previous version of this block
said infrastructure/admin/migration/routes had "not started," but ALL of them
are present on disk. This is the recurring "code shipped, docs untouched" drift
(10th occurrence). Corrected below to the true state, and one GENUINE code
defect (not documentation) was found — see DEFECT AD-1.**

**DONE & verified (content-inspected, sound design, no TODO/placeholder/mock):**
- `packages/domain/admin/` — `AuditEntry`/`AuditAction`/`AuditEntryId` +
  `User.suspend()`/`reinstate()`; fully tested (incl. the 9 suspend/reinstate
  cases). Domain layer CLOSED.
- `packages/contracts/lib/src/admin_dto.dart` (+ `admin_dto_test.dart`) —
  present, exported from `contracts.dart`.
- `packages/application/admin/` — `SuspendUser`+`ReinstateUser`
  (`suspend_user.dart`, both classes verified present at L34/L148), `ListAuditLog`,
  `ViewParticipantLedger` (audits BEFORE serving data, fails closed on a failed
  audit write — verified in-file), `AuditRecorder` (single audit-write path,
  propagates the error — NOT best-effort, correct for a crown-jewel action),
  ports `UserAdminRepository`/`AuditLogRepository`. All gate on
  `PlatformRole.admin` via `Authorization.requireRole`. All 6 symbols exported
  from `application.dart` (verified L7–L12).
- `packages/infrastructure/admin/` — `PostgresUserAdminRepository` +
  `PostgresAuditLogRepository`, both exported from `infrastructure.dart`
  (verified L8–L9). **On disk (contradicts the previous doc claim that this
  layer had not started).**
- `supabase/migrations/0010_admin.sql` — 256 lines, present & complete: the ONE
  `admin.audit_log` table + closed `admin.audit_action` enum, append-only
  (UPDATE/DELETE/TRUNCATE revoked + `admin.reject_audit_mutation` immutability
  trigger for EVERY role incl. service, mirroring `ledger.reject_entry_mutation`),
  RLS deny-all to every client role, named FK `audit_log_actor_id_fkey` for the
  adapter's 23503 map, NO points column. Forward-only, idempotent.
- `apps/server/routes/admin/` — `_middleware.dart` (`bearerAuth`, authz inside
  the use-cases), `users/[id]/suspend/index.dart`, `users/[id]/reinstate/index.dart`,
  `participants/[id]/ledger/index.dart`, `audit/index.dart`; plus
  `apps/server/lib/http/admin_dto_mapper.dart`. All present.
- CompositionRoot: the private ctor declares the four admin use-cases as
  `required` fields (L51–L54); `forTesting` supplies matching optional params +
  `_absent*` stand-ins backed by `_Unwired*` throwing repos + a throwing
  `AuditRecorder` (L167–L171, L421–L450). This half is CORRECT.

**🔴 DEFECT AD-1 (High — REAL code defect, breaks the production build; NOT a
doc drift). `apps/server/lib/composition/composition_root.dart`:**
- The private `CompositionRoot._({...})` marks `suspendUser`, `reinstateUser`,
  `listAuditLog`, `viewParticipantLedger` as **`required`** (L51–L54).
- But `bootstrap()`'s `return CompositionRoot._(...)` (L725–L844) passes
  arguments only up to `markNotificationRead:` (L840–L843) and **NEVER passes
  the four admin use-cases**, nor does `bootstrap` construct the real
  `PostgresUserAdminRepository` / `PostgresAuditLogRepository` / `AuditRecorder`.
- Consequence: the production `bootstrap` call site is **missing four required
  arguments → it does not compile.** `forTesting` compiles (its params are
  optional), so route tests can pass while the real server cannot be built.
  This is the same "last layer left half-written" hazard the protocol warns
  about, now realized as a hard compile break on the integrity-critical path.
- **EXACT FIX (for the executor — small, fully specified):** in `bootstrap`,
  after the notifications slice (≈L723) add the admin slice:
  ```dart
  // Admin slice: the ONE new stored surface is admin.audit_log (0010); the
  // user sanction toggles the existing identity.users.status. One audit-write
  // path (AuditRecorder) is shared by every audited admin use-case.
  final userAdminRepository = PostgresUserAdminRepository(connection);
  final auditLogRepository = PostgresAuditLogRepository(connection);
  final auditRecorder = AuditRecorder(
    auditLog: auditLogRepository,
    idGenerator: idGenerator,
    clock: clock,
  );
  ```
  then, inside the `CompositionRoot._(...)` argument list (after
  `markNotificationRead:`), add the four:
  ```dart
  suspendUser: SuspendUser(
    users: userAdminRepository, auditRecorder: auditRecorder),
  reinstateUser: ReinstateUser(
    users: userAdminRepository, auditRecorder: auditRecorder),
  listAuditLog: ListAuditLog(auditLog: auditLogRepository),
  viewParticipantLedger: ViewParticipantLedger(
    participantReader: participantReader,   // already built in bootstrap
    ledgerRepository: ledgerRepository,     // already built in bootstrap
    auditRecorder: auditRecorder),
  ```
  (Verify the exact ctor param NAMES against `suspend_user.dart` /
  `view_participant_ledger.dart` before writing — this doc records the names as
  read on disk this session: `SuspendUser({required UserAdminRepository users,
  required AuditRecorder auditRecorder})`; `ViewParticipantLedger({required
  ParticipantReader participantReader, required LedgerRepository ledgerRepository,
  required AuditRecorder auditRecorder})`.)

**STALE NOTE, corrected 2026-07-13 (auditor session 47) — this paragraph
originally listed all five test/review artifacts below as missing. By session
47 all four test files AND the route test were confirmed on disk with full
content review (see the EXECUTION CHECKLIST above, which is the authoritative
status — this paragraph is kept only as history, do not trust it over the
checklist):**
- ~~`list_audit_log_test.dart` / `view_participant_ledger_test.dart` missing~~ —
  done, verified (checklist above).
- ~~`packages/infrastructure/test/admin/` does not exist~~ — done, both hermetic
  and DB-gated suites verified (checklist above).
- ~~`admin_routes_test.dart` missing~~ — done, verified (checklist above).
- `docs/reviews/admin-panel-review.md` ~~**still does not exist**~~ — **DONE
  2026-07-13 (this session).** This paragraph is kept only as history; the review
  now exists and §2/§4 are updated. See the COMPLETE & RATIFIED block below.

**Milestone (Admin Panel) — COMPLETE & RATIFIED (green, 2026-07-13).**
Full Milestone-0 rigor. Delivered end-to-end across all six layers (domain
sanction hook + append-only audit aggregate → contracts → application use-cases
+ the single `AuditRecorder` write path → infrastructure adapters → migration
`0010_admin.sql` → `apps/server` routes + mapper + route tests + CompositionRoot
wiring) and reviewed six ways (`docs/reviews/admin-panel-review.md`, phase-exit
GREEN, same 0–8 structure as the notifications/social reviews). The review found
**no High or Medium defect open**: the one High, **DEFECT AD-1** (the production
`bootstrap()` compile break — the four admin use-cases were `required` but never
built/passed), was fixed the prior session and re-confirmed correct at the
`CompositionRoot._(...)` call site; one genuine **Low, AD-2**, was found AND
fixed in the review session (the dartdoc in `routes/admin/audit/index.dart` +
`routes/admin/_middleware.dart` named the non-admin refusal
`identity.forbidden_role`, but `Authorization.requireRole` returns
`auth.insufficient_role` — grep-confirmed the wrong token existed only in those
two comments; fixed in-place, behaviour already correct). All other findings are
info/verified-OK (M-1 the sanction persist-before-audit order — the safe
direction for an append-only record, documented; S-verified the RLS deny-all;
P-note the index-ordered audit read; M-note the constraint-name coupling).

**Exit criterion met:** the five ratified decisions are honoured PHYSICALLY and
verified against the code (not assumed) — (1) reuse existing ratified use-cases
under an admin-elevated caller, new use-cases only where none exists (the
sanction + the audited support read); (2) `PlatformRole.admin` is the ONLY authz
model, gated FIRST in every one of the four use-cases (verified in-file), no
separate auth path; (3) backend routes only, no UI; (OPEN-A) a reversible
suspend/reinstate pair with a mandatory reason, no Group/Social moderation, a
narrow read-only itself-audited cross-user ledger read; (OPEN-B) ONE general
append-only `admin.audit_log` covering ALL admin verbs, append-only in three
layers (port has no update/delete + client privilege REVOKE + the
`admin.reject_audit_mutation` trigger rejecting UPDATE/DELETE for every role
including the RLS-bypassing service role, mirroring `ledger.reject_entry_mutation`).
The audit-write is fail-closed for the cross-user support read (audit BEFORE
serve → a failed append refuses the read, 503, zero rows served/logged — proven
by both the application and route tests) and propagated (not best-effort) for the
sanctions. The adapter's SQLSTATE→typed map keys off the exact migration
constraint names (`audit_log_pkey`/`audit_log_actor_id_fkey`), and the
`admin.audit_action` enum tokens equal `AuditAction.wireValue` one-to-one
(verified by diff). The live route list was cross-checked route-by-route and
status-by-status against `admin_routes_test.dart` (687 L) — **no coverage gap**.
Axioms 2/5/6 honoured (server-only writes, no points column anywhere in the audit
surface, the DB backstops = deny-all RLS + privilege revocation + the
immutability trigger). No new external dependency (reuses `postgres 3.5.12`,
`dart_frog 1.2.6`, `mocktail`, `test ^1.26.0`); `tooling/import_lint` ruleset
unchanged (the `admin` slice lives inside the existing packages; the one new port
`UserAdminRepository` is internal to `application`). By-construction verification
only (sandbox has no Dart toolchain — §2 Environment note); "compiles & goes
green" to be confirmed via `melos bootstrap && melos run verify` on a Dart-3.12+
machine, and the DB-gated integration test in CI against ephemeral Postgres with
migrations 0001–0010 applied. Six-way review GREEN. **Admin Panel phase COMPLETE
& RATIFIED.**

**Milestone (Flutter App) — COMPLETE & RATIFIED (green, 2026-07-14).**
Full Milestone-0 rigor. The final roadmap phase (ADR 0008, phase 12/12).
Delivered end-to-end across the ratified **Core scope** — Auth + Competition
(browse) + Prediction (submit) + Leaderboards (view) — as `apps/mobile` (a single
responsive Flutter codebase for PWA + Android + iOS, decision #2) plus the
standalone `packages/api_client` transport, and reviewed six ways
(`docs/reviews/flutter-app-review.md`, phase-exit GREEN). The review found **no
High, Medium, or Low defect** — the code on disk already realizes the five
ratified decisions (§4 **Milestone (Flutter App) — Decisions Ratified**)
correctly across all four screens, so **no code change was required**. Every
finding is verified-OK/info (table in §7 of that file).

**Exit criterion met:** the Core client is delivered end-to-end and verified
against the code (not assumed) — (1) Core scope ONLY, no Ledger/Groups/Social/
Notifications/Admin screen or stub (grep-confirmed absent); (2) one responsive
`MaterialApp` codebase; (3) annotation-based Riverpod in every provider (18
`@riverpod`/`@Riverpod`; zero Bloc/GetX/manual `ChangeNotifier`); (4/5) all
networking through the standalone `packages/api_client` serializing `contracts`
DTOs against `apps/server`, NO direct Supabase client-side write, with the
`mobile -> {api_client, contracts, shared}` boundary enforced by
`tooling/import_lint` (ruleset already complete — no widening needed). The four
screens are cross-consistent: one `core/error/error_presenter.dart` for every
error DISPLAY (the only two raw-code reads are control-flow — 401→clear token —
and data-mapping — 404→`Ok(null)` — both §4-sanctioned, neither is display); one
shared `AsyncListView`/`AsyncObjectView` for the four async states (loading/
success/legitimate-empty/error), covered with equal discipline by each screen;
zero raw HTTP outside `api_client` (every `http.*` confined to the one
`core/network/http_client.dart` DI factory); zero forbidden import; zero TODO/
placeholder/mock across the whole `apps/mobile` tree. Axioms 2/4/5 honoured on
the client (server-only points — the submit body carries no `participant_id`/
`points`; one prediction row per `(participant, round)`, submit == amend; a
read-only server-computed leaderboard rendered in server order, never re-sorted).
Every library version-verified (§3, all compatible with the ratified Flutter pin
3.44.0 / Dart `^3.9.0`); tests (2,463 L incl. harnesses) cover every screen and
every state/error path over the REAL screens/providers/controllers with a
`MockClient` transport (the genuine `api_client` end-to-end, only the socket
faked). No new external dependency beyond the version-checked Flutter/Riverpod/
secure-storage libraries in §3. By-construction verification only (sandbox has no
Dart/Flutter toolchain — §2 Environment note); "compiles & goes green" to be
confirmed via `flutter pub get && dart run build_runner build` then `flutter
analyze` + `flutter test` on a Flutter 3.44.0 machine, and `melos run verify` /
`melos run import-lint` for the workspace boundary. Six-way review GREEN.
**Flutter App phase COMPLETE & RATIFIED — the roadmap is now COMPLETE, 12/12.**

---

### Build Verification Gate — حالة

- §4 Build Verification Gate: مكتملة.
- جميع مراحل التنفيذ الـ12 السابقة لا تُعاد فتحها.
- تحقق Web مكتمل بنجاح.
- تحقق Android غير متاح في بيئة Codespaces الحالية لعدم وجود Android SDK.
- تحقق iOS متخطّى لأن البيئة ليست macOS ولا تحتوي Xcode.

### Design refresh -- five screens (2026-09-15)

Additive only; no new dependency, no new internal package, no migration.

- **Leaderboard scopes** `الشهر / اليوم / الموسم` replace the placeholder
  `أصدقائي / النخبة` tabs (which only showed a "coming soon" snackbar).
  - *Day*: `GET /seasons/{id}/fixture-leaderboard?from=&to=` -- optional UTC
    window (from inclusive, to exclusive, both or neither, else `400
    leaderboard.invalid_window`). `GetSeasonFixtureLeaderboard` now takes
    `FixtureScheduleRepository` and keeps only the season fixtures kicking off
    inside the window; points are the stored fixture scores, only selected.
    A windowed board carries no movement arrows.
  - *Season*: the sporting season is September..August; points accumulate
    across its monthly contests and the top total is the season champion.
    `GET /leaderboard/season` -> `GetSportingSeasonLeaderboard` (domain
    `SportingSeason` / `SportingSeasonStanding` / `SportingSeasonLeaderboard`,
    port `SportingSeasonStandingsReader`, adapter
    `PostgresSportingSeasonStandingsReader` summing
    `leaderboard.season_fixture_standings` per user over months whose `MM/YYYY`
    label falls in the season). Contract `SportingSeasonLeaderboardDto`.
  - Hall of Fame is retired from the product; its code is left untouched.
- **My predictions**: filter `الكل / قادمة / مكتملة` (client-side view over the
  existing read; unknown kickoff appears under "all" only).
- **Matches**: day chips (weekday + date, relative badge), double button blue.
- **Home**: header, overview card, top matches of the day, pending card.
- **Account**: profile card with the current month's points / decided matches
  / accuracy from `GET /me/seasons`; admin dashboard row for `admin` only;
  records and groups moved under `الإعدادات`. No language row: the app locale
  is fixed to Arabic.

### Capacity on the free plans (2026-09-16)

- Monthly/day board: `GetSeasonFixtureLeaderboard` reads per-participant sums
  through the new port `FixtureTotalsReader`
  (`PostgresFixtureTotalsReader`, `GROUP BY participant_id` on
  `scoring.fixture_scores`) and ranks them with
  `FixtureLeaderboard.rankTotals` -- one row per player instead of one row
  per player per fixture. `FixtureLeaderboard.rank` stays for tests and the
  equivalence test pins both to the same board.
- Season board SQL now filters months first and joins
  participants -> fixture_scores by index instead of scanning the view.
- In-process TTL caches (`CachedFixtureTotalsReader` 30 s,
  `CachedSportingSeasonStandingsReader` 60 s); failures are never cached; a
  newly scored result can take up to the TTL to appear.
- `.github/workflows/db-backup.yml`: weekly (Tuesday 01:30 UTC) `supabase db dump` (roles, schema,
  data, auth data), tar + gpg AES-256, kept 90 days as an artifact (public
  repo: never committed). Secrets `SUPABASE_DB_URL` (session pooler) and
  `BACKUP_PASSPHRASE`. Fails -- and emails -- when the database reaches
  400 MB of the Free plan's 500 MB.

### Unattended operation (2026-09-16)

Reliability audit follow-up (report kept outside the repo).

- **Next monthly contest is created automatically.**
  `EnsureUpcomingMonthlySeasons` (application, no principal) follows the
  newest `MM/YYYY` season and creates the next month under the same
  competition once it starts within 7 days (same UTC window/label as
  `StartSeason`; additive only; at most 3 months per run; skips an existing
  label). Driven by `apps/server/lib/scheduler/monthly_season_scheduler.dart`
  (1 min after boot, then every 6 h). An empty season enrols nobody, so an
  early month is invisible until the admin adds its first fixture.
- **Supabase publishable keys.** `SupabaseAuthClient` sends the
  `Authorization: Bearer` header only for legacy JWT-shaped anon keys; a
  `sb_publishable_...` key goes in `apikey` only. Legacy anon/service_role
  keys are retired by Supabase at the end of 2026: set
  `NUKHBA_SUPABASE_ANON_KEY` on Northflank to the publishable key before
  then.
- **Backup schedule keep-alive.** `db-backup.yml` re-enables itself on every
  run (`actions: write`) so GitHub's 60-day inactivity rule for public repos
  cannot silently stop backups.
- **Migration 0047** sets `statement_timeout = 20s` on role `postgres` so a
  statement the server abandoned (Dart-side 10 s timeout) is also cancelled
  in Postgres and frees its pool connection. Apply in the SQL editor, then
  restart the Northflank service. Rollback:
  `alter role postgres reset statement_timeout;`.
- Still manual (product decision pending): daily fixtures and results entry.

### Admins cannot suspend admins (2026-09-16)

`SuspendUser` refuses a target whose role is `admin`
(`admin.cannot_suspend_admin`, invariant, Arabic message) before any write
or audit entry, so a backup admin cannot lock the owner out. Reinstate is
unchanged (still role-agnostic). Changing an admin account remains possible
only directly in the database.

### Highlightly team identities (2026-09-16)

Football data provider for automatic fixtures/results: **Highlightly**
(free plan: 100 requests/day, all leagues, current season; requests need an
explicit User-Agent -- Cloudflare rejects library defaults with 1010).
Provider league ids: Premier League 33973, Champions League 2486,
Bundesliga 67162, La Liga 119924, Serie A 115669, Roshan League 262041,
Europa League 3337, League Cup 41632 (manual for now: Ligue 1 52695,
DFB Pokal 69715, FA Cup 39079, Asian Cup 6741, AFCON 5890, AFCON
qualification 31420, Gulf Cup 22059).

Phase-1 selection rules: Premier League and Champions League -- every
match; League Cup -- only when both sides are Premier League clubs;
Bundesliga, La Liga, Serie A, Roshan League, Europa League -- any match of
one of the owner's listed clubs (see the owner's list in the session record).

`supabase/seed/highlightly_team_map_2026_27.sql` (hand-applied) maps 141
clubs in `football_data.external_identity_map` (`external_source =
'highlightly'`): 121 existing, 20 created (8 UCL, 12 UEL). Neom is
"Al Suqoor" at the provider. Migration 0048 adds `football_data.teams.league_id`
to the repository (already present in production; no-op there).

### Automatic fixtures and results (2026-09-16)

Phase 1 of the Highlightly sync (rules in
`apps/server/lib/provider_sync/phase_one_rules.dart`).

- **Application:** ports `FootballDataProvider` (`ProviderMatch`,
  `ProviderMatchStatus`) and `ProviderSyncStore` (identity map + pending
  results); `ProviderLeagueRule`, `ProviderSyncMode`, `riyadhDayOf`;
  use-cases `SyncProviderFixtures` (adds selected upcoming matches exactly
  like an admin: schedule with catalog names/ids/league, identity link,
  season link; skips unmapped teams, matches < 30 min away, and matches
  outside every monthly contest; a fixture of the same two teams already on
  the schedule within 12 h is adopted -- identity linked, nothing added --
  so hand-added matches also get automatic results) and
  `SyncProviderResults` (fixtures linked
  to the provider, no result, kicked off 110 min - 3 days ago; one provider
  call per league/Riyadh day, max 8 per run; postponed/cancelled are logged
  for an admin, never scored).
- **Infrastructure:** `HighlightlyFootballDataProvider` (explicit
  User-Agent; `timezone=Asia/Riyadh`; keeps 25 requests of the daily 100 in
  reserve via `x-ratelimit-requests-remaining`; `state.score.current` is the
  score after extra time, shoot-outs excluded) and
  `PostgresProviderSyncStore`.
- **Server:** `NUKHBA_HIGHLIGHTLY_API_KEY` + `NUKHBA_PROVIDER_SYNC`
  (`off` default | `shadow` logs only | `on` writes). Results are recorded
  through `RecordFixtureResult` + `ScoreFixture` under a service principal.
  `provider_sync_scheduler.dart`: fixtures 3 min after boot (today + 2 days),
  then daily (next 2 days); results every 20 min. Logs are prefixed
  `provider-sync [mode]`.
- Budget: ~16 fixture calls/day + result calls only for due groups.

### Two football data providers (2026-09-17)

Highlightly's free plan (100 requests/day) ran out during testing, so the
five football-data.org competitions moved there (free tier: 10 calls/minute,
no daily cap): Premier League `PL`, Champions League `CL`, Bundesliga `BL1`,
La Liga `PD`, Serie A `SA`. Highlightly keeps the Roshan League, Europa
League and League Cup.

- `ProviderLeagueRule.source` names the serving provider; the sync
  use-cases take `providers: {source: FootballDataProvider}`. A quota stop on
  one provider no longer stops the others. Results are chased per source; a
  fixture linked to two providers is recorded by the first that reports it
  finished.
- `FootballDataOrgProvider` (`X-Auth-Token`; calls spaced >= 6.5 s; a Riyadh
  day is asked for as its two UTC dates and filtered; penalty shoot-outs are
  removed via `regularTime + extraTime`, else `fullTime - penalties`, else no
  result).
- `supabase/seed/football_data_team_map_2026_27.sql` maps 96 clubs
  (`external_source = 'football-data'`) to the same catalog teams as their
  Highlightly ids. Env: `NUKHBA_FOOTBALL_DATA_API_KEY`; a provider without a
  key is skipped.

### Live scores in the fixtures feed (2026-09-17)

Option 1 (free): running scores for the five football-data.org
competitions only (the free tier's scores are delayed); Roshan and Europa
League cards keep the bare "مباشر" label so Highlightly's 100 daily requests
stay for results.

- `RefreshLiveScores` (application) polls, every 2 min, only competitions
  with a provider-linked fixture that kicked off < 150 min ago and has no
  result; writes `LiveScore`s to the `LiveScoreBoard` port
  (`InMemoryLiveScoreBoard`, forgets after 15 min). Display only: nothing is
  recorded or scored. `ProviderMatch` gained `currentHomeGoals`,
  `currentAwayGoals`, `minute`.
- `GET /feed/current-month-fixtures` attaches `live_home_goals`,
  `live_away_goals`, `live_minute`, `live_finished`
  (`CurrentMonthFixtureItemDto` schema 3; older clients ignore them).
- Mobile: a locked card shows `2 - 1` with the minute (or the final score
  with "بانتظار النتيجة"); the matches screen refreshes the feed every 2 min
  while a fixture is live.
- Upgrade path: Highlightly paid plan -> add `highlightly` to `liveSources`
  in `composition_root.dart`.

### Knockout rule: extra time and penalties (2026-09-17)

Adopted the UEFA Predict Six rule (also Superbru's): the result that
counts is the score at the end of open play -- after 90 minutes plus
stoppage time, or after 120 minutes when extra time is played. A match
decided by a penalty shoot-out counts as a draw at the end of extra time;
shoot-out goals never count. The provider adapters already record exactly
this (`FootballDataOrgProvider.finalScore`, Highlightly
`state.score.current`); admins entering a result by hand follow the same
rule (hint under the admin result form). Shown to users on the sign-in
rules card and on the new "كيف تلعب؟" page (Account -> الإعدادات).

### Sync query resilience (2026-09-17)

`provider-sync [on] live scores failed: db.query_timeout` came from the
pool's first statement after an idle stretch exceeding the 10 s statement
limit, which cost a whole poll. `PostgresProviderSyncStore` now retries once
after 500 ms (background jobs only; request paths keep the single-shot
behaviour), and migration 0049 indexes `competition.fixture_schedules
(kickoff_at)`, the range every sync query filters on.

### Result confirmation (2026-09-19)

Everton 1-0 Ipswich Town (2026-09-19): a second Everton goal was ruled out
for offside at 58', yet the sync recorded 2-0. The sync records what the
provider reports the first time it sees a match finished and never looks
again, and no code path counts goals itself -- the only writers of a result
are the sync and the admin `PUT /fixtures/{id}/result`.

`SyncProviderResults` now records a finished score only after the same score
has been seen unchanged for `confirmAfter` (15 minutes; two runs at least that
far apart). A changed score starts the wait again; a match that leaves
finished starts it again too. The wait is kept in memory per provider and
fixture, so a server restart starts it over. Shadow mode waits the same way.
Nothing else moves: the 2-minute live poll still starts a results check at
full time, admin-entered results are never touched, and a wrong figure that
was already recorded is corrected by hand (record the result, then post to
the ledger: compensating `correction` entries). Not covered: a provider that
never corrects its figure.

### Match details page (2026-10-19)

Asked for on the model of Sports Mole's match page: each finished match's
goals with their minutes, cards, the half-time score and the ground.
football-data.org's free tier has none of it (goal scorers and bookings
start at its €29 plan); Highlightly's free plan has it per match. The probe
of 2026-10-19 (script 117, read-only) found the five football-data.org
leagues on Highlightly (Premier League 33973, La Liga 119924, Serie A
115669, Bundesliga 67162, Ligue 1 52695; Champions League 2486, not playing
that day) and read Paris FC 4-3 Rennes FC with its 26 events, the VAR goal
ruled out at 51' among them, 14 requests of the 100 a day.

- **Read once** (`SyncMatchDetails`, every 30 minutes beside the provider
  sync, only in mode `on`): a fixture with a recorded result, 2h15 to 3
  days after kickoff, in a league of `matchDetailsLeagueIds`. A fixture from
  Highlightly carries its match id; any other is found in Highlightly's list
  of its league's matches that day: the one kicking off within 10 minutes
  of it, or, among several, the one that ended on the recorded score. The
  score is not asked of a single candidate, so a match a feed scored wrong
  is still found. No candidate: stored `found = false`, never asked again.
- **Quota**: one list call per league and day, one call per match, at most
  8 a run; both Highlightly adapters of this job stop with 40 requests left,
  for the schedules and the results.
- **Stored** in `football_data.match_details` (migration 0179), events
  already in the app's kinds (`HighlightlyMatchDetailsSource.kindOf`):
  Highlightly's «Penalty» is a penalty goal, «VAR Goal Cancelled» a goal
  ruled out, «VAR Penalty» kept but not shown. The half-time score is worked
  out from the goals up to 45+; left out when an own goal falls in the
  first half, since providers differ on whose side they file it.
- **Shown**: `GET /fixtures/{id}/details`; «تفاصيل المباراة» on a finished
  match's card opens `MatchDetailsPage`: league and round, the score home
  side first in the reader's direction (`orientedScoreLabel`), half time,
  ground, referee, then each goal and card with its minute on its side, the
  ruled-out goal struck through. Substitutions are left out.
  Each score (full and half time) is a `TextDirection.ltr` text, as
  everywhere `orientedScoreLabel` is used: left to the Arabic paragraph
  the two digits swapped places: the first build drew Brighton's 5 (5-0
  against Crystal Palace) under Palace's crest (2026-10-19).
- **Laid out like Sports Mole** (script 120, 2026-10-19): one card with the
  league, the round on its own line, the date, the sides around the score,
  half time, «انتهت» and the ground; under a rule each side's goals and
  cards in its own column under its crest, in the provider's order, each
  line the player, the minute and the mark, the mark towards the middle.
  A penalty reads «(ج)», an own goal «(في مرماه)», a goal ruled out by the
  VAR is struck through with «(ألغاه الفيديو)». No assists and no referee,
  as on Sports Mole. When the card is under 220px wide divided by the
  reader's text scale, the away list goes under the home list, each under
  its side's name.
- **Read sooner, and never silently** (script 121, 2026-10-19): an hour
  after 118 went out not one row was written. The first read now comes 5
  minutes after boot (`matchDetailsFirstRunDelay`) instead of a whole
  30-minute tick, which every restart put off again; the newest matches
  are read first, the ones players open; and every run with work logs
  `provider-sync [on] match details: pending=N requests=R saved=S
  not_found=F` with why each passed-over fixture was passed over (no
  provider league, a match not over).
- **A wrapped name keeps its minute** (script 122, 2026-10-19): the first
  page showed «Juan Antonio Iglesias Sanchez» on two lines with its 69'
  at the column's far edge, since a wrapped text took the whole column.
  The name is now as wide as its longest line
  (`TextWidthBasis.longestLine`).


- Display only: nothing reads it to score, rank or record a result.

### Live score correction (2026-10-18)

Paris FC - Rennes (Ligue 1, 2026-10-18): Rennes' second goal was ruled out
by VAR at 51', yet the feed (football-data.org) still reported 2-2 at 62',
so the match card showed 2-2 and the live points graded it. Nothing in the
app counts goals: `RefreshLiveScores` copies the provider's figure every 2
minutes. This is the case the result confirmation above leaves uncovered
(a provider that never corrects its figure). Chosen by the owner (option 3):
an admin corrects the running score himself, and that correction decides
the final result too.

- **Where**: النتائج والاحتساب -> «النتائج المباشرة» lists the real matches
  with a running score and no result; a tap opens the score to correct, or
  to give back to the provider («إرجاع نتيجة المزوّد»).
- **Route**: `PUT /fixtures/{id}/live-score` `{home_goals, away_goals}` and
  `DELETE` (admin-only, `AdminCorrectLiveScore`); `409
  football_data.not_live` while the provider reports no running score.
- **How it lies over the feed**: the poll writes the provider's figure to
  `InMemoryLiveScoreBoard`; players read `CorrectedLiveScoreBoard`, which
  applies `LiveScoreCorrection.applyTo`. A correction remembers the
  provider's figure it was made against: while the feed still says that (or
  already says the corrected score) the corrected score stands, settled; if
  the feed goes back on a goal by itself its own figure stands; a goal the
  feed reports later is added on top of the correction, not settled.
- **Final result**: `SyncProviderResults` records the corrected score after
  the usual 15 minutes. A correction that is not settled is put to the
  admins once per provider figure (`provider_sync.correction_unsettled`) and
  recorded only when an admin corrects again, records the result by hand,
  or the match is late (6 hours), when the shown score is recorded.
- **Kept in memory** like the running scores (30 hours): a server restart
  during a match forgets the correction, which is then made again. No
  audit entry: `admin.audit_log` actions are a fixed set, and the recorded
  result an admin enters by hand stays audited as before.

### Club list that failed to load (2026-10-19)

The add-fixture form read every club («النصر», «الهلال», «ميلان»...) as
«ليس في قائمة الأندية» and kept «أضف النادي إلى القائمة» off. The data was
sound (373 clubs, 18 on the Roshan League, 9 KB) and closing the app fixed
it: `GET /teams` had failed once while the server was slow after a restart,
Riverpod's retries ran out, and `teamCatalogProvider` stayed in error while
the matches screen held it. The form showed nothing about it.

`TeamCatalogStatus` (admin/widgets) now sits above the team fields of the
add and edit forms: «جارٍ تحميل قائمة الأندية…» while it loads, «تعذّر تحميل
قائمة الأندية» with the error and «إعادة المحاولة» when it failed, and
nothing once it is in. A form opened on a failed list asks for it again by
itself. «ليس في قائمة الأندية» shows only once the list is in, since before
that it is not known; saving stays blocked either way.

### Streak bonus (P1-4, 2026-09-19)

Gamification adds no second points store. A streak bonus is a `streak_bonus`
entry in `ledger.fixture_point_entries`, the append-only ledger that already
holds fixture points (`user_points_summary`, P0-4, was cancelled).

- **Ladder**: a run of 7 match days pays 5 points, 14 pays 10, 30 pays 20
  (`StreakBonusPolicy`, domain).
- **Once per participant per rung**: `source_ref = streak:<threshold>`, and a
  partial unique index on `(participant_id, source_ref)` where
  `entry_kind = 'streak_bonus'` (migration 0057) refuses a second one. A
  participant belongs to one season, so this is once per rung per season.
- **Eligibility is the CURRENT run, never the longest.** A rung is due when
  `current >= threshold` and it has not been paid; `longest` is a record to
  show, never a source of points. Accepted cost: a user who completes the
  deciding day early and breaks the run before the next first-time submission
  loses that rung.
- **When**: `SubmitFixturePrediction`, on the first-time submission that
  completes a Riyadh match day (`AwardStreakBonus`, application). Tier-3: a
  failure never fails the prediction, and `ledger.already_posted` (a lost
  race on the index) counts as paid. The run is read through `GetMyStreak`,
  so the bonus counts it exactly as `GET /me/streak` shows it.
- **Where it hangs**: the entry is stored against the fixture whose
  prediction completed the day, so it counts in that fixture's day and month
  boards. It is not part of that fixture's score: `PostFixtureToLedger`
  ignores `streak_bonus` when it sums a fixture's entries.
- **Boards**: the displayed standings never read the ledger, so three
  aggregates add the bonus explicitly: `PostgresFixtureTotalsReader` (day and
  month board), `PostgresSportingSeasonStandingsReader` (sporting-season
  board) and the view `leaderboard.season_fixture_standings` (migration 0058;
  rank snapshots and the personal season record). `hall_of_fame_standings` and
  `season_standings_with_movement` are round-era views over
  `ledger.point_entries`, unreachable since fixtures moved to seasons, and
  were left alone.
- **Migrations**: 0056 adds the enum value (its own transaction: Postgres
  refuses to use a new enum value in the transaction that added it, SQLSTATE
  55P04), 0057 adds the non-negative check and the unique index, 0058
  replaces the standings view. Apply 0058 to the live database before
  deploying the server code that reads it.
- **Open**: at the time of writing the mobile ledger screen shows the raw
  `streak_bonus` kind token; a label is not part of P1-4.

Binding rules for the whole gamification plan (decided 2026-09-19):

- `rule_version = 1`; no retroactive change to predictions made before
  2026-09-05.
- The Riyadh day (city time: neither UTC nor the user's own offset) is the
  boundary of both the daily challenge and the streak.
- The per-user UTC offset (migration 0055) is used only to time
  notifications (quiet hours).
- A day is complete when the participant has predicted every match of that
  day; it does not become incomplete if a match is added later, and a day
  without matches does not count.

### Settled match days (P1-5, 2026-09-20)

The streak calendar used to derive match days live from the current fixture
schedule, so a fixture that was moved, added or removed re-wrote days that
were already over (a postponed match hid its old day and shortened every
streak that ran through it). A Riyadh day that has ended is now settled once
and frozen.

- **Table**: `gamification.settled_days` (migration 0059), one row per Riyadh
  day, including days with no fixture (`fixture_count = 0`), so the newest
  row is the watermark "settled through here". Append-only, server-only.
- **Job**: `SettleMatchDays` (application), run hourly by
  `startMatchDaySettlementScheduler` (it respects `NUKHBA_SCHEDULERS=off`).
  It settles every day after the watermark through the last day that ended at
  least 3 hours ago (Riyadh), at most 120 days per run; the first run starts
  at the earliest scheduled fixture. Idempotent (`ON CONFLICT (day) DO
  NOTHING`), so a missed run is made good by the next one.
- **Calendar**: `PostgresStreakRepository` reads settled days with
  `fixture_count > 0` as frozen and derives only the days after the
  watermark live. With an empty table, or if the job stops, it behaves
  exactly as before.
- **A moved fixture** does not change a settled day: the day stays a match
  day with its frozen count, and the new day is a live match day until it is
  settled in turn. Completion events are untouched.
- **Not in scope**: a streak-freeze token (a day the user may skip). The
  "freeze" of P1-5 is the freezing of days, decided 2026-09-20.
- **Order**: apply 0059 to the live database BEFORE deploying the server code,
  because the calendar query reads the table.

### Match days are per season (P1-5 correction, 2026-09-20)

0059 settled one row per Riyadh day for the whole platform, and the calendar
read it that way: any season playing made the day a match day for every user.
A participant row is created only when a user joins a season, so a user in one
season lost the streak on days only other seasons played -- days they could
not have played. `GET /me/streak` would have shown it the moment P1-6 put the
number on a screen.

- **Table**: `gamification.settled_day_seasons` (migration 0060) -- one row
  per settled day per season that played in it, with that season's frozen
  fixture count. Only days that had fixtures; append-only and server-only,
  like 0059.
- **Watermark unchanged**: `settled_days` still carries every ended day,
  including empty ones, and is still what "settled through here" means.
- **One statement**: `PostgresMatchDaySettlementStore.settle` writes both
  tables in one transaction through a data-modifying CTE, so they cannot
  disagree. Both are `ON CONFLICT DO NOTHING`, so the job stays idempotent.
- **Calendar**: `PostgresStreakRepository` joins both the frozen and the live
  branch to the reader's ACTIVE participations
  (`competition.participants.status = 'active'`).
- **Scope of the day**: a Riyadh day, unchanged. What changed is whose day it
  is. The daily challenge already worked this way -- it was raised per season
  (`DailyChallengeRepository.progressOn`) -- so the calendar now agrees with
  the event that fills it.
- **Backfill**: 0060 rebuilds the per-season rows for the days 0059 already
  settled, from the current schedule. Those days were frozen from that same
  schedule the day before, so this is a faithful replay, not a re-derivation
  of old history.
- **Known gap, not closed here**: the completion event's dedupe key is
  `daily_challenge_completed:<user>:<date>`, with no season in it, so
  covering one season's fixtures marks the whole day complete for a user who
  is in several. Deciding that is P1-6 work, not this correction.
- **Order**: apply 0060 to the live database BEFORE deploying the server
  code, because both the calendar and the settlement job read the table.

### GET /me/daily-challenge (P1-6, 2026-09-20)

The read half of the challenge the write path already computes.
`SubmitFixturePrediction` asks `DailyChallengeRepository.progressOn`
after a prediction lands, to decide whether to raise
`daily_challenge_completed`; `GetMyDailyChallenge` asks the same port the
same question on demand, so the card and the event cannot disagree.

- **Route**: `GET /me/daily-challenge`, behind the `/me` bearer
  middleware. Answers `{day, total, predicted, complete}`
  (`MyDailyChallengeDto`). `day` is a `YYYY-MM-DD` Riyadh date, not an
  instant: the boundary is the server's, and a timestamp would invite the
  client to re-derive it in its own zone.
- **Scope**: the caller's ACTIVE seasons, summed -- the same scoping
  migration 0060 gave the streak calendar. One extra round trip per
  active season resolves the participant; the platform runs one monthly
  season at a time, so that is one.
- **No fixture list**: the client already has the day's fixtures from the
  season feed. A card that draws "2 of 3" does not need them twice.
- **An empty day**: `total: 0, complete: false`. A rest day is a
  legitimate answer, never an error, and is never an achievement --
  the same rule `DailyChallengeProgress.isComplete` applies on the write
  path.
- **No migration**: this task adds no table and no column. Deployable on
  its own.
- **Decided, not changed**: the completion event's dedupe key stays
  `daily_challenge_completed:<user>:<date>`, with no season in it. It is
  raised per season, so a user in two seasons at once could mark a day
  complete by covering one of them -- but seasons here are monthly and
  sequential, never concurrent, so the case does not arise. Re-open it
  the day two seasons overlap; changing the key of an append-only stream
  without a live reason is not free.

### The daily challenge on screen (P1-7, 2026-09-20)

`GET /me/daily-challenge` (P1-6) and `GET /me/streak` (P1-2) reach the home
page as one card, `DailyChallengeCard`
(`apps/mobile/lib/features/gamification/`), mounted under the greeting and
above the overview card.

- **One card, not two.** The old `_StreakLine` in `home_screen.dart` is gone:
  a bare run of days without the day it belongs to said nothing, and two
  gamification lines competing for the same corner said it twice. The streak
  is now a badge on the card's title row.
- **The home page, not the matches screen.** The matches screen is where the
  day is played; repeating its own fixture count above it would be the same
  list twice. The home page is the summary, and it already carries the
  greeting, the overview and the pending-predictions card.
- **Silent by default.** Nothing while it loads, nothing when either request
  fails, and nothing on a rest day with no run to show (`total == 0 &&
  current == 0`). A home page does not tell someone they have nothing.
- **Fetched per mount, not through a provider.** Both numbers move only when a
  prediction lands, and the page's pull-to-refresh rebuilds the card. No
  `build_runner` step is added for this.
- **No plural in the badge.** `streakBadgeLabel` reads "the streak: 12" with no
  counted noun, because Arabic changes the noun past ten and a number in a
  badge is understood without one. The progress line is "{predicted} of
  {total}" for the same reason.
- **l10n**: `dailyChallengeTitle`, `dailyChallengeProgress`,
  `dailyChallengeCta`, `dailyChallengeComplete`, `dailyChallengeEmpty`,
  `streakBadgeLabel`, `streakLongestLabel` in both ARBs. The generated
  `app_localizations*.dart` are committed, so they are edited in the same
  change.
- **No migration, no server change.** Deployable with the app alone.

### Experiment assignment (P1-8, 2026-09-20)

The machinery that splits a population, over the two tables migration 0054
already created. **No migration, no route, and -- deliberately -- no call
site yet.**

- **Three pieces.** `VariantAllocator` (domain, pure) decides an arm from
  `flag_key:user_id` alone; `ExperimentRepository` (application port) reads
  the flag and reads or stores the assignment;
  `PostgresExperimentRepository` (infrastructure) speaks to 0054's tables.
  `ResolveExperimentVariant` joins them and is wired into the composition
  root.
- **The stored row is the truth.** `(user_id, flag_key)` is the primary key,
  so a user keeps the arm they were first given. The allocator only decides
  the arm of a user who has no row. Changing the hash, the arm order or the
  weights re-buckets only the unassigned; an experiment's population may
  grow, it is never re-drawn.
- **Deterministic, not random.** FNV-1a over `flag_key:user_id`, because
  `hashCode` is not stable across processes and an allocation that moves
  between restarts is not an allocation. Two servers racing on the same first
  exposure therefore compute the same answer, and the single `INSERT ... ON
  CONFLICT DO NOTHING ... UNION ALL SELECT` statement makes the loser read
  the winner's row instead of raising 23505.
- **It cannot fail.** `ResolveExperimentVariant` returns a bare `String`, not
  a `Result` -- the one use-case in the codebase that does. A flag that is
  off, a flag that does not exist and a database that did not answer all mean
  the same thing downstream: behave as yesterday. Each answers `control`, and
  nothing is written.
- **The flag is read first**, so a stopped experiment writes no assignment:
  the assignments are the record of who was measured.
- **Why no experiment yet.** The streak bonus was rejected as the first
  split: its points are real, the ledger is append-only, and a monthly
  competition with a prize cannot have two users' standings decided by a coin
  flip that cannot be undone. Reminder timing was rejected for now because
  the KPIs that would read it (`challenge_completion_rate`,
  `streak_participation`, deferred in 0054) do not exist yet, and a split
  nobody can measure is a split not worth running.
- **Starting one** is a flag row and a call site, no deploy of new layers:

      insert into gamification.feature_flags (flag_key, description, enabled)
      values ('<key>', '<what it gates>', false);
      -- then flip enabled to true when the call site is live.

  A flag is retired with `enabled = false`, never by deleting the row: the
  assignments that measured it must survive it.

### Quiet-hours routing (P3-2c, 2026-09-21)

Two pushes are still worth reading in the morning: the exact-hit
announcement (`NotifyFixtureWinners`) and the admin broadcast
(`PublishAnnouncement`). When the reader is in their quiet hours, both now
go into `notification.notification_queue` (0064) instead of ringing in the
night. **No migration**: 0055 (`utc_offset_minutes`) and 0064 are already on
the live DB.

- **The inbox row is not delayed, only the push.** Both use-cases write the
  in-app notification at once, exactly as before; the queue holds the push
  alone. `NotifyFixtureWinners` counts a queued push as delivered.
- **When it goes out.** `QuietHours.endsAt` (domain) answers the next 08:00
  on the reader's own clock as a UTC instant, always after the moment asked
  about. A reader who never reported a clock falls back to Riyadh, the same
  fallback `QuietHours.covers` uses.
- **The readers carry the clock.** `ScoreNoticeTarget.utcOffsetMinutes` and
  `AnnouncementRecipient.utcOffsetMinutes`, read from `identity.users` by
  `PostgresScoreAnnouncementRepository` and `PostgresAnnouncementRepository`.
  Nothing else reads the offset: it is still not a day boundary.
- **`NotificationQueue.enqueue`.** The caller generates the row id and the
  adapter inserts with `ON CONFLICT (id) DO NOTHING`, so a retried caller
  never queues a push twice. It stops at the first failure.
- **Best effort, like the send.** A failed enqueue loses that one push; it
  never fails the scoring of a fixture or the publish of an announcement.
- **One queue.** The composition root builds a single
  `PostgresNotificationQueue` and hands it to both notifiers and to
  `FlushNotificationQueue`.
- **Unchanged.** The daily prediction reminder is still skipped in quiet
  hours, not queued (P3-2a): after 08:00 it would arrive after its kickoff.
  An announcement recipient with no device on file is not queued.
- **Still open in P3-2:** the weekly cap (docs/gamification-audit.md s4).

### Weekly reminder cap (P3-2, 2026-09-22)

The last piece of P3-2. **No migration, no route, no client change.**

- **The rule.** A user receives at most `SendPredictionReminders.weeklyCap`
  (5) daily prediction reminders per Riyadh week, Monday 00:00 to Sunday
  23:59 -- the week of the weekly league (0061).
- **What counts.** The daily reminder only. The exact-hit push is a reward
  and an admin announcement is a deliberate human decision; neither is
  capped and neither counts toward the cap.
- **At the cap the reminder is skipped**, not queued and not marked in
  `reminder_sends`, exactly like an opted-out user or one in quiet hours.
- **No new table.** `reminder_sends` (0040) already holds one row per user
  per reminded day, so `PredictionReminderRepository.sentCountsSince` counts
  its rows from the week's Monday. The cap is policy in Dart; SQL only
  counts.
- **Order in the sweep:** pending targets, then opt-outs and quiet hours,
  then the cap, so only users who would otherwise be sent to are counted.
- **Fail closed.** If the counts cannot be read the sweep sends nothing and
  the next tick retries, as with the opt-outs.
- **Kept as built, decided 2026-09-22** against the plan's "6, every type,
  user-adjustable": the daily reminder is today the only push that is not a
  reward (exact hit) or a human decision (announcement), so a budget shared
  with those would let an admin broadcast silence the reminder. When plan
  P3-4 adds the first new proactive type (pre-match, streak saver,
  overtaken), the cap becomes one weekly budget shared by the reminder and
  those types. A user-set cap may only lower it, never raise it.

### Favorite teams (plan P3-1, 2026-09-22)

The teams a player follows: the audience of the pre-match push (plan
P3-4a, batch 2). Migration 0065 (`identity.user_favorite_teams`).

- **At most three, each once**, `FavoriteTeams.max` in the domain. Not a SQL
  constraint: the server is the only writer.
- **`GET` / `PUT /me/favorite-teams`**, body `{ "team_ids": [...] }`. PUT
  sends the whole set every time (an empty list clears it) and answers what
  was stored. A team id missing from the catalog trips the FK and answers
  400 `identity.favorite_team_unknown`.
- **Order is kept**: the adapter stamps each row with `clock_timestamp()`,
  so the read comes back in the order chosen.
- **The page** is `FavoriteTeamsScreen`, reached from the account page's
  notifications card. Each tap writes; a failed write leaves the selection
  and shows the save-failed message, like the notification switches.
- **Dead tokens** (P3-2b gap closed in the same batch): the deferred-push
  sweep now deletes the tokens FCM reports invalid, as the reminder sweep
  already did, through `NotificationQueue.forgetTokens`.

### Proactive pushes: the gate and the pre-match push (plan P3-3, P3-4a, 2026-09-22)

Migration 0066: `pre_match`, `streak_saver`, `overtaken` switches on
`notification_preferences` (all default on), and
`notification.proactive_sends`, one row per (user, kind, ref).
**0066 must be on the live DB before this server is deployed**: the
reminder sweep's budget query reads `proactive_sends`.

- **`NotificationGate` (domain) is the one rule** for proactive pushes: the
  type switch, the quiet hours on the reader's clock, and a weekly budget of
  5 per Riyadh week shared by every proactive type. Rewards (exact hit) and
  announcements are not proactive and never pass it.
- **The budget is shared from now on.** `PushBudgetReader.sentCountsSince`
  counts `reminder_sends` plus `proactive_sends` from the week's Monday;
  `PostgresPredictionReminderRepository` implements it for both sweeps, and
  `SendPredictionReminders.weeklyCap` is `NotificationGate.weeklyBudget`.
- **Pre-match push (`SendPreMatchReminders`)**, every 10 minutes: fixtures
  kicking off 90 to 120 minutes from now; followers (0065) of either side
  who are active participants of a season owning the fixture, have not
  predicted it, were not pushed about it, and own a device. Each push is
  recorded right after it is sent; a failed record stops the sweep.
- **Switches.** `PUT /me/notification-preferences` accepts either switch
  and keeps the one left out, so an old client never resets `pre_match`.
  The settings page shows both.
- **Still to come (batch 3):** `streak_saver` and `overtaken` use the same
  gate, table and budget; their columns already exist.

### Streak saver and overtaken pushes (plan P3-4b, P3-4c, 2026-09-22)

Both go through `NotificationGate` and the shared weekly budget of 5, and
record what they send in `proactive_sends` (0066). Migration 0067 adds
`gamification.weekly_league_rank_marks`. **0067 must be on the live DB
before this server is deployed.**

- **Streak saver (`SendStreakSavers`, every 10 minutes).** A day is lost the
  moment its first unpredicted fixture kicks off; the saver fires when that
  kickoff is 45 to 75 minutes away, for a player whose run -- counted as
  `GET /me/streak` counts it -- is at least 2. At most one per player per
  Riyadh day. No freeze was added: the saver is the answer to "one miss
  breaks it" (decided 2026-09-19).
- **Overtaken (`SendOvertakenPushes`, every 30 minutes).** Each sweep ranks
  every group of the open week with `WeeklyLeaguePolicy.order`, compares
  with the marks of the previous sweep (0067), saves the new marks first,
  and `OvertakeDetector` (domain) names who passed whom: the nearest member
  now above who was below before. At most one per member per group, so one
  per week. A pass during the quiet hours is not told.
- **Switches.** `streak_saver` and `overtaken` join
  `PUT /me/notification-preferences` (any subset, the rest kept) and the
  settings page.
- **Still to come (batch 3b):** deep links from a push to its screen, and
  the in-app "overtaken" card (P2-7).

### Deep links from a push (batch 3b, 2026-09-22)

Every push now carries `data.link` in its FCM payload: `fixtures` (daily
reminder, pre-match, streak saver), `league` (overtaken) or `inbox` (exact
hit, announcement, and a push deferred out of the quiet hours). The names
are `PushLink` in the domain and `PushLinks` in the app; the two sets must
stay equal. `PushSender.send` takes the link as an optional argument.

The app listens once, from `NukhbaaShell`: the push that launched it
(`getInitialMessage`) and every later tap (`onMessageOpenedApp`). A link
selects its tab; `inbox` also opens the inbox over the home tab. A link the
build does not know opens the app as a plain tap. No new dependency.

**P2-7's "overtaken" card moves to batches 4-5:** the server has to keep who
passed whom (a column on 0067's marks) before the league screen can show it.

### Learn from your predictions (plan P4-1..P4-4, 2026-09-22)

`GET /me/insights` answers the caller's accuracy this Riyadh month against
every player's, accuracy per league with the best and worst named (5
decided each at least), followed teams against the rest (3 each at least),
the longest right run, the last 8 weeks, and last week's recap with its
best prediction. **No migration, no table, no weekly job.**

- **Derived on every read** from `scoring.fixture_scores` (decided grades
  only), for the reason there is no streak table: a stored insight or recap
  would be a second truth, wrong after a corrected result. The plan's
  `user_prediction_insights` and `weekly_recaps` tables and their weekly
  job are dropped for that reason (decided 2026-09-22).
- **One endpoint** instead of the plan's three: the three read the same
  rows and the screen shows them together.
- `PredictionInsights` (domain) holds every rule; `GetMyInsights` only picks
  the window (the earlier of the month's first day and the oldest of the
  8 weeks, Riyadh days) and the community tally of the month.
- A percent is null when nothing was decided: never a division by zero,
  never a "0%" for someone who has not played.
- **Not in the recap:** the rank change and the badges of the week (the
  plan's `rank_delta`, `badges_unlocked`); both have their own screens.
- **Next (batch 5):** the screen (P4-5), the P2-7 overtaken card, the P1-7
  celebration.

### The insights screen, the overtaken card, the celebration (plan P4-5, P2-7, P1-7, 2026-09-22)

- **Insights page (P4-5)**, `InsightsScreen`, from the account page: the
  month's accuracy against everyone's, 8 weekly bars, last week's recap and
  best call, and the patterns (best/worst league, followed teams against the
  rest, longest right run). Every number is the server's (`GET /me/insights`);
  a percent the server left null shows as a dash.
- **Overtaken card (P2-7).** Migration 0068 keeps who passed a member on
  their rank mark (`passed_by`, `passed_at`); the overtaken sweep writes it
  whether or not a push goes out. `GetMyWeeklyLeague` reads it through the
  optional `OvertakenNoticeReader` and names the passer only while they
  still rank above the reader; `GET /me/weekly-league` carries
  `overtaken_by` (a display name) only when set. Best effort: a failed read
  never costs the table. **0068 must be on the live DB before deploying.**
- **Celebration (P1-7).** The daily-challenge card's icon lands with a
  short elastic pop when the day is complete. No new dependency.
- **Still to do (batch 6):** measurement (P2-8, P3-8, P4-6) and closing the
  plan.

### Measurement and the close of the gamification plan (plan P2-8, P3-8, P4-6, 2026-09-22)

Migration 0069: `notification.push_opens` (one row per tap on a push, via
`POST /me/push-opened`, sent by the app from `NukhbaaShell._openLink`) and
read-only views, server-only like 0054 and 0062:

| View | Plan | What it answers |
|---|---|---|
| `gamification.user_active_days` | - | distinct (user, Riyadh day) with any event |
| `gamification.kpi_weekly_engagement` | P2-8 | per week, league members vs others: active, active 3+ days, rate |
| `gamification.kpi_league_retention` | P2-8 | members holding a seat the next week |
| `notification.kpi_push_funnel` | P3-8 | per day and kind: sent, opened, back within the day or the next |
| `notification.kpi_push_opt_outs` | P3-8 | users with a device, and each switch turned off |
| `gamification.kpi_retention` | P4-6 | by first active day: active on day 14, in week 4 |
| `gamification.kpi_accuracy_trend` | P4-6 | every player's accuracy per month |

"Opened" is a tap with the push's link on the day it was sent; "back
within 24 hours" is activity that day or the next. Both are day-grained on
purpose: the sends are recorded by day. **0069 must be on the live DB
before deploying.**

**The plan is closed.** What was built differently from the plan, and why,
is recorded in the sections above and summarised in
`docs/gamification-audit.md` section 10. A/B experiments (P1-8's machinery)
are ready and deliberately not running: read these views for a few weeks
first, then decide what to test.

### Frame smoothness from every device (2026-09-24)

Migration 0070: schema `ops` ("how the app runs on devices, not what
players do") and `ops.frame_reports`, one row per app session: frames
drawn, slow (build or raster past one refresh interval of that display --
16.7 ms at 60 Hz, 8.3 ms at 120 Hz), frozen (past 700 ms, a subset of
slow), the slowest, the build's short sha, platform and refresh rate. No
screen names, content or device identifiers; rows go with their user.
Server-only like 0069; CHECK constraints mirror `RecordFrameReport`'s
validation, which refuses a report that cannot be true.

- `POST /me/frame-report` (`RecordFrameReport`, player) keeps one report.
- `GET /admin/frame-stats?days=` (`AdminGetFrameStats`, admin; default 7
  days, at most 30) returns totals overall and for the five newest builds.

Batch 48 is the server; the app's collector and the admin dashboard card
follow in batch 49. **0070 must be on the live DB before deploying.**

Migration 0071 (batch 50) adds `device_model` (nullable; `samsung
SM-A105F`), read through `device_info_plus` -- already a direct dependency
of the in-app updater, so nothing was added to pubspec. The app cleans the
name to `^[0-9A-Za-z ._()+-]{1,60}$`, which the use-case and a CHECK both
enforce; the web sends none. `GET /admin/frame-stats` gains `devices`: the
five least smooth models, each only once **three distinct players** report
it, so no row describes one person's phone. **0071 must be on the live DB
before deploying.**

The web build (`deploy-pages.yml`) injects `NUKHBA_BUILD_SHA` too -- the
first seven characters of the commit it checked out, as the APK does --
so web sessions report as well; before batch 51 they carried no sha and
the reporter, by design, sent nothing. The update gate returns early on
the web, so the sha changes nothing there. On the admin card a figure
with its unit sits in a left-to-right isolate (U+2066 ... U+2069) so it
reads `0%` and `77 ms` inside the Arabic sentence, and a build or device
name is placed at the start of its row, clear of the figures.

### Design-system consistency (batch 52, 2026-09-24)

- Every font size comes from the type scale: a `AppTypography.textTheme`
  role or a named step of `AppFontSize` (9..26). The 57 bare `fontSize:`
  numbers became `AppFontSize.sN` of the same value -- nothing moved on
  screen, the match card included -- and
  `test/core/design/font_size_scale_test.dart` rejects a new bare number.
- `LeaderboardBoard` speaks through `AppLocalizations` (`board*` keys): the
  headers, the summary, the gap and leader lines, the spoken row labels,
  and Arabic points agreement as an ICU plural (`boardPoints`: one, two,
  few 3-10, many 11+) replacing the hand-written `_arabicPoints`. The
  Arabic strings are the ones the board showed before.

### Reading order and screen reader: home, my predictions, account (batch 53)

- Home reads in the order of what to do: the predictions still open (the
  one primary action) first, then the matches they are about, then the
  day's challenge, then the season overview (was: challenge, overview,
  matches, open predictions last). Each card is one `MergeSemantics` node.
- A prediction card leads with its kickoff and verdict (the status badge,
  with points once graded) on one line, then the call, then when it was
  made (the status used to trail the submission time). One node per card.
- Account: the avatar button is named (`avatarChange`); each stat is read
  with its label. Its order (profile, actions, settings, sign-out) already
  fit and is unchanged.

### Back from the background: no "could not reach the server" (batch 54)

Reported 2026-09-24: leaving the app for another and coming back showed
the matches tab's full-screen "تعذّر الاتصال بالخادم" with a retry button.
Two causes, both fixed. (1) `ApiTransport` had no retry, and the first
request after resuming dies on the pooled keep-alive socket the server's
proxy closed meanwhile: a GET that fails as `network_unreachable` is now
sent once more, at once, on a fresh connection (never a POST, never after
a timeout). (2) The matches screen rendered `feed.when` without
`skipError`, so one failed refresh -- the minute tick fires as soon as
the app resumes -- replaced the list with the error; it now keeps the
list and shows the error only when there is nothing to show.

### The final score on a finished prediction (batch 55)

Requested 2026-09-24. Scoring is untouched. `GET .../fixtures/{id}/scores`
now also carries `result_home_goals` / `result_away_goals` -- the recorded
final score scoring compared the predictions against -- once a result is
recorded (`GetFixtureResult`, read only, over `FixtureResultRepository`;
best effort: a failed read drops only the result). A finished card in
"my predictions" shows it on a line under the call: "انتهت", the final
score under the predicted one, and the verdict with the server's points
(❌ none, ✅ points, 🔥 a double that scored). That line then carries the
verdict, so the first line keeps the kickoff alone.

### Frame smoothness: a build reads once per platform (batch 56)

Requested 2026-09-24. The admin card mixed the web with the phones: on the
live data a build's 10.3% slow frames were all Android while the web
builds beside it sat at 2%, and the per-build lines could not tell them
apart. `GET /admin/frame-stats` now returns one row per build **and
platform** (`builds[].platform`, omitted on the overall row), for the five
newest builds -- the limit counts builds, so a build's platforms never
crowd another build out. The card writes `sha · platform`. The overall
line above is unchanged (every platform together). No migration: the
column already exists.

### Streak bonus counts in the weekly league only (batch 57, 2026-09-27)

Decision: gamification rewards never touch the monthly board or the
sporting-season board. The `streak_bonus` entries stay in
`ledger.fixture_point_entries` exactly as written (append-only, nothing
deleted); only the readers change:

| Board | Reader | Streak bonus |
|---|---|---|
| Month and day | `PostgresFixtureTotalsReader` | no |
| Sporting season | `PostgresSportingSeasonStandingsReader` | no |
| Rank arrows, personal record | `leaderboard.season_fixture_standings` (0072) | no |
| Weekly league | `PostgresWeeklyLeagueStandingsReader` | yes |

Migration 0072 redefines the view without the bonus (same columns). The
first daily rank snapshot after it may show a one-day move for a player
whose bonus left the total. **0072 must be on the live DB before
deploying.**

### Invitations: the database layer and the SQL test job (batch 58, 2026-09-27)

Decisions: invitations live inside gamification, never in the ledger.
Invitation points only break ties -- the month by that month's points, the
sporting season by the season total -- and never add to prediction points.

Migration 0073 (inert until `gamification.feature_flags` row `referrals` is
switched on):

| Object | What it holds |
|---|---|
| `gamification.referral_codes` | one fixed 8-character code per user, never changed |
| `gamification.referrals` | who invited whom; `invitee_id` is the primary key (one inviter, forever), CHECK no self-invitation, trigger: claim within 24 h of the invitee's account and the inviter older than the invitee |
| `gamification.referral_install_marks` | hashed installs an inviter was seen with |
| `referral_held` / `referral_qualified` / `referral_rejected` / `referral_revoked` in `gamification.events` | the life cycle; dedupe key `<type>:<invitee_id>`, so one payment per invitee; a guard trigger refuses any referral event without a real invitation |
| `gamification.referral_month_points` | paid, not revoked, counted in the monthly contest that holds the payment, capped at 20 |
| `gamification.referral_season_points` | the capped monthly points summed per sporting season (Sept-Aug) |

Functions (server-only): `ensure_referral_code`, `claim_referral`,
`mark_referral_install`, `qualify_referrals` (pays or holds; safe to
re-run), `review_referral` (admin: approve / reject / revoke, reason
mandatory). An invitation qualifies when the invitee's account is
confirmed, it holds a monthly participation, sent a prediction and that
prediction was graded on a decided fixture. It is HELD for an admin, never
paid or rejected automatically, on a shared network or install with
another invitee of the same inviter, the inviter's own install, or more
than ten claims for one inviter within 24 hours. IP addresses and install
ids are stored only as salted SHA-256 hashes.

CI: `.github/workflows/db-tests.yml` applies `supabase/tests/supabase_stubs.sql`
and every migration to an ephemeral Postgres 16, then runs
`supabase/tests/*_test.sql` (0072: 2 checks, 0073: 61 checks). **0073 must
be on the live DB before the invitations server (batch 59) is deployed.**

### Invitations: the server (batch 59, 2026-09-27)

Every rule stays in the 0073 functions; the Dart layers carry values.

| Route | Use-case | Who |
|---|---|---|
| `GET /me/referral?install=` | `GetMyReferral` | player: fixed code, month and season points, invited, pending; remembers the install id (hashed) |
| `POST /me/referral/claim` | `ClaimReferral` | player: `{code, install_id}` -> `status`; ensures the platform row first; the address is the last `X-Forwarded-For` hop |
| `GET /admin/referrals?limit=` | `AdminListHeldReferrals` | admin: held invitations, oldest first |
| `POST /admin/referrals/{inviteeId}` | `AdminReviewReferral` | admin: `{decision: approve|reject|revoke, reason}` |

`QualifyReferrals` runs every 30 minutes in-process
(`referral_qualification_scheduler.dart`, first run 4 minutes after boot);
a repeat writes nothing. Adapter: `PostgresReferralRepository`. Every claim
and decision outcome is `200` with its `status`; malformed input is `400`,
a non-admin on the admin routes `401`. **0073 must be on the live DB
before this server is deployed.**

### Invitations break ties on the month and the season (batch 60, 2026-09-27)

The order on the monthly board, the sporting-season board, the rank arrows
and the personal record:

1. prediction points, most first;
2. invitation points, most first -- the month's (`referral_month_points`,
   capped at 20) on the monthly board, the season's total
   (`referral_season_points`) on the season board; never added to the points;
3. exact scorelines, most first;
4. level on all three: the same rank ("1224").

A day board (a window) ranks without invitation points
(`FixtureLeaderboard.rankTotals(breakTiesByReferrals: false)`). The totals
and season readers carry `referral_points`; the DTOs gain `referral_points`
(`FixtureLeaderboardEntryDto` v5, `SportingSeasonEntryDto` v2). Migration
0074 redefines `capture_season_rank_snapshots` with the same order and adds
a partial index for paid invitations. Step 3 applies as soon as this is
deployed, even while no one has invitation points yet: two players level on
points are no longer level unless their exact scorelines are equal too.
**0074 must be on the live DB before this server is deployed.**

### Invitations in the app (batch 61, 2026-09-27)

- **Invitation page** (`InviteFriendsScreen`, from the account page, row
  `account.invite`): the fixed code, "copy link"
  (`https://adbrhman.github.io/nukhbaa/?ref=CODE`) and "copy code", the
  month's points out of 20, the season's points, invited and pending
  counts, how they count, and a field to name one's inviter within 24 hours.
- **Registration**: an optional code field (`signIn.referralField`); a web
  link with `?ref=` opens the registration tab with the code filled in. The
  claim is sent right after the account exists
  (`SessionController.register(referralCode:)`), and never fails the
  sign-up. A first Google sign-in has the same field on the name screen
  (`nameSetup.referralField`).
- **Install id** (`core/auth/install_id.dart`): a random id in the secure
  store, sent with `GET /me/referral` and the claim; the server keeps it
  hashed, as one signal for review.
- **Rules page**: the tie-break order (`rules.tieBreak`).

Held invitations are reviewed by an admin through
`POST /admin/referrals/{inviteeId}` or, until the dashboard has a page for
it, in the Supabase SQL editor:
`select gamification.review_referral('<invitee uuid>', 'approve', '<admin uuid>', '<reason>');`
(`reject` / `revoke` likewise). The list: `GET /admin/referrals`.

### Invitations: idle invitees and the admin controls (batch 62, 2026-09-27)

- **Idle invitee** (migration 0075, `gamification.expire_idle_referrals`,
  called at the end of `qualify_referrals`, same 30-minute sweep and same
  switch): a paid invitation whose invitee sent no prediction for 7 days
  since the later of the payment and the last prediction is revoked
  (`referral_revoked`, reason `inactive_7_days`). Until migration 0114 the
  invitee's account was also SUSPENDED; since 0114 (batch 150, audit M-21)
  it is left active and only the point is taken back.
- **`gamification.referral_invitations`** (view): one row per invitation
  with its state (`pending`, `held`, `paid`, `revoked`, `rejected`), the
  hold reasons, the revoke reason, the invitee's status and last prediction.
- **`GET /admin/referral-overview`** (`AdminGetReferralOverview`): the
  switch, totals per state, the inviters (100) and the newest invitations
  (300). **`PUT /admin/referral-switch`** (`AdminSetReferralsEnabled`):
  `{enabled}`; off stops claims, payments and revocations, and keeps every
  point already paid. Decisions stay on `POST /admin/referrals/{inviteeId}`.

**0075 must be on the live DB before this server is deployed.** The admin
page in the app follows in batch 63.

### Invitations: the admin page (batch 63, 2026-09-27)

Admin hub section **نظام الدعوات** (`AdminSection.referrals`, group
"المستخدمون والتفاعل", `ReferralAdminSection`):

- the on/off switch (`admin.referrals.switch`, `PUT /admin/referral-switch`);
- counts per state (held, pending, paid, revoked, rejected);
- every invitation with its state, dates, last prediction, hold reason,
  revoke reason (`inactive_7_days` = idle 7 days) and a "suspended" mark,
  filterable by state; held ones can be approved or rejected, paid ones
  revoked, each with a mandatory reason (`POST /admin/referrals/{inviteeId}`);
- every inviter: invited, paid, pending, held, refused, and this month's
  invitation points out of 20.

A suspended idle account is reinstated from the existing users section.

### Everyone's predictions after kickoff (batch 64, 2026-09-28)

`GET /seasons/{id}/fixtures/{fixtureId}/predictions` (`ListFixturePredictions`)
returns every member's prediction for one fixture with the player's name --
only from kickoff on. The gate is `FixtureLock` over the fixture's schedule and
the server clock, the same instant that closes submission, so no prediction is
ever visible while any prediction can still change. Before kickoff, or with no
registered kickoff: `409 prediction.fixture_not_started`; a non-member:
`prediction.not_a_participant`.

In the app, a started match card shows **توقعات الجميع** in the slot the
double button held before kickoff (the card keeps its layout). It opens the
day's table (batch 65, `FixturePredictionsBoardPage`): one row per player, one
column per match of that device-local day that has kicked off (upcoming ones
are never requested), names fixed on the reading side, columns scrolling
sideways, the whole table scrolling down, the viewer's row first and a name
search. Each cell is the predicted score with its verdict from the server's
scores: points -> ✅ (⚡🔥 on a double), graded without points -> ❌, not graded
yet -> nothing (⚡ on a double).

### Retention on the admin dashboard (batch 67, 2026-09-28)

`GET /admin/retention?weeks=` (`AdminGetRetention`, admin; default 8 weeks,
at most 26, the week in progress included) reads the views of migration
0069 through `RetentionReader` / `PostgresRetentionReader`. Nothing new in
the database; **0069 must be on the live DB**.

- Per week (`kpi_weekly_engagement`, `kpi_league_retention`): players
  active, the share active on 3+ days, the same inside the weekly league
  against everyone else (P2-8), and the share of league seats held the
  next week. That last one is null until the next week has ended: a seat
  is taken the first time a player is seen in the week, so a half-counted
  week would read as a drop.
- Per week of first active day (`user_active_days`, first day over the
  whole history): back on day 1, day 7, day 14 (0069's d14) and in week 4
  (days 21 to 27, 0069's w4). A horizon counts only the players whose day
  has ended; the card shows a dash while nobody can be judged.

Every week of the window is present, zeros included. The dashboard card
(`AdminRetentionCard`, «هل يعود اللاعبون؟») sits under the user counts:
this week's players, last week's 3+ share and day 7 pooled over the
window, then both tables, scrolling sideways on a phone. The SQL was run
against the 0069 views on sample data (Riyadh midnight, partial weeks,
young cohorts) before shipping. No new dependency.

### The new logo (batch 69, 2026-09-29)

The owner's flat mark (the letter nun and an N around a goal, the dot the
ball) replaces the crown-and-ball logo of 2026-09-28: it stays legible at
launcher and notification sizes, where the old one turned to a blur. Brand
blue #1978D1, the mark in white.

- Launcher (`assets/branding/nukhbaa_icon_v7/`, same paths, so the CI steps
  are unchanged): the adaptive background is the brand blue, the foreground
  the white mark inside the 66dp safe circle; the pre-Android-8 icons are a
  rounded blue tile.
- Web: `icon192/512` are full-bleed blue with the mark inside the maskable
  80% circle (the same files serve as the maskable icons); the favicon is a
  small rounded tile. The committed `web/icons` and `web/favicon.png` match.
- `assets/branding/nukhbaa_logo.png` (sign-in header and the share card) is
  the blue tile; both screens round its corners themselves.

No code change, no new dependency.

### Share a hit (batch 66, 2026-09-28)

A finished prediction that earned points (My Predictions) shows **شارك
إصابتك**. It opens a preview of a picture card -- the Nukhba logo, the match
and league, the call against the final score, the points (⚡🔥 on a double)
and the viewer's place on the month's board -- then captures that exact card
(`RepaintBoundary`, pixel ratio 3) and hands it with a text to the system
share sheet. The text carries the viewer's invitation link
(`inviteLinkFor`), so a share feeds the invitation system. Every number is
the server's (scores read, `fixtureLeaderboardProvider`); a failed board or
referral read only leaves the rank or the link out. New dependency, approved
2026-09-28: `share_plus`.

### The player's experience pass (batch 68, 2026-09-29)

No server change, no migration, no new dependency.

- **Back button**: on any tab but home, Android back returns to the home
  tab (`PopScope` in `NukhbaaShell`); from home it leaves the app as before.
- **Last month's predictions**: `historyFixturesByIdProvider`
  (`prediction_lookup_providers.dart`) adds, for a prediction whose fixture
  is not in the current-month feed, the fixtures of the prediction's own
  season (`GET /seasons/{id}/fixtures`, one cached read per season). On the
  first of a month the previous month's predictions keep their teams, their
  kickoff and their place under "مكتملة". A card whose names are still
  unknown shows the bare call, never the fixture id.
- **Pull to refresh** on My Predictions, the month / day / season boards
  (`AsyncListView.onRefresh`; a reload keeps the rows on screen) and the
  matches tab's two empty states.
- **Matches tab**: the nearest day with matches is measured from the real
  today on every build; an app left open past midnight opened on the day
  before.
- **Match card** (layout and scoring unchanged): after kickoff the middle
  slot keeps the player's own call under the status ("توقعك 2 - 1", a bolt
  for the double; key `currentMonthFixtures.myCall.<id>`); a save that
  failed on the connection offers "إعادة المحاولة"; a second double on the
  same day (`prediction.daily_double_exceeded`) turns the toggle off, says
  why in a snackbar and saves the scoreline alone.
- **Daily challenge card** reads again whenever the caller's predictions
  change (a save, the home pull to refresh) instead of once per session.
- **Sign-out** asks first (`signOutConfirmMessage`).
- New l10n keys: `matchCardYourCall`, `signOutConfirmMessage`.

### The champion of the month (batch 70, 2026-09-29)

Decided 2026-09-29: when a month has ended and its results are in, an admin
crowns its champion from a preview; when two players are level on every
tie-break the admin decides between one and two champions. The admin adds
the champion's picture from the dashboard. The app celebrates for 48 hours
at the top of the leaderboard (the picture faint behind, crown, light and
confetti, the picture in a gold frame, name, points and accuracy, then the
rest of the board); afterwards the crown stays beside the name and in the
records. This batch is the server; the app follows in batch 71.

Migration 0077 (`competition.month_champions`, server-only, additive): one
row per champion, two at most per month, crowned once (one `crowned_at`),
with the final figures frozen (points, exact, decided, invitation points)
and an optional inline picture (like 0033: 512 KB, JPEG / PNG / WEBP).
Triggers refuse a champion who did not play the month, a third champion, a
second crowning, any change but the picture, and every delete.
`supabase/tests/0077_month_champions_test.sql`: 11 checks.

| Route | Use-case | Who |
|---|---|---|
| `GET /admin/champions/{seasonId}` | `AdminGetChampionCandidates` | admin: over or not, fixtures without a result, already crowned, the top of the final board (everyone first included) |
| `POST /admin/champions/{seasonId}` | `AdminCrownMonthChampions` | admin: `{user_ids, force}`; 409 `champion.month_not_over` / `already_crowned` / `fixtures_unscored` (unless `force`) / `not_first` |
| `POST /admin/champions/{seasonId}/photos/{userId}` | `AdminSetChampionPhoto` | admin: the image bytes, `Content-Type` named |
| `GET /champions` | `ListMonthChampions` | player: every champion, newest first, with `celebrate_until` (crowned + 48 h), `photo_url`, `avatar_url` |
| `GET /champions/{seasonId}/photos/{userId}` | `ReadChampionPhoto` | player: the picture bytes (404 without one) |

The final board is built exactly like the live monthly board
(`MonthFinalBoard`: the stored fixture totals of the month's fixtures,
`FixtureLeaderboard.rankTotals`, invitation points then exact scorelines
breaking ties), read uncached. A fixture counts as unscored while
`scoring.fixture_results` has no result for it. Adapter:
`PostgresMonthChampionRepository`. **0077 must be on the live DB before
this server is deployed.**

### The champion of the month in the app (batch 71, 2026-09-29)

The app side of batch 70. No server change, no migration, no new
dependency.

- **Leaderboard** (`leaderboards_screen.dart`): while `now <
  celebrate_until` of the newest crowning (`celebratingChampions`), the tab
  draws, back to front: the champion's picture faint behind the header
  (`ChampionBackdrop`), then `ChampionSpotlight` -- a drawn crown
  (`ChampionCrown`, no emoji font), a gold light and one light shower of
  confetti (never loops, skipped when the system turns animations off), the
  picture in a gold frame (`ChampionFramedPhoto`), the name, points and
  accuracy -- then the usual pills and board. Two champions sit side by
  side. The spotlight folds to one line (a screen under 600 dp starts
  folded). The picture is the celebration picture, else the profile
  picture, else the first letter; bytes through `avatarBytesProvider`.
- **After 48 hours** the celebration disappears; a crown beside the title
  opens the **champions' record** (`ChampionsRecordScreen`: every crowned
  month, newest first). A crown also sits beside a champion's name on the
  boards keyed by user -- the season and the weekly league
  (`BoardEntry.champion`, `championUserIdsProvider`); a monthly board's
  lines carry no user id, so it cannot tell.
- `monthChampionsProvider` (`GET /champions`) is kept alive; the month
  board's pull to refresh reloads it.
- **Admin** (`ChampionAdminSection`, hub group "النقاط والترتيب"): pick the
  month, see whether it is over and how many fixtures have no result, the
  top of the final board as the server ranked it; tick the player ranked
  first (or two, level), add the champion's picture (gallery, 640 px; the
  type read from the bytes so a cut-out PNG keeps its transparency; 512 KB
  checked before sending), preview exactly what the players will see, then
  crown (confirmation; `force` when fixtures lack a result). The pictures go
  up after the crowning; one that fails is added again from the crowned
  month ("تغيير الصورة").
- New l10n keys: `championCrownLabel`, `championTitleOne`,
  `championTitleTwo`, `championsRecordTitle`, `championsRecordEmpty`,
  `championsLoadFailed`, `championSpotlightCollapse`,
  `championSpotlightExpand`.

### The web build reaches players (batch 72, 2026-09-29)

The APK updated itself; the web mirror (`nukhbaa-web` on Northflank) was
redeployed with every build but players kept the old one. Checked
2026-09-29: the mirror served `web build 74b72cd`, and its
`flutter_service_worker.js` is Flutter's self-unregistering cleanup worker
(no fetch handler, no cache), so the stale copy came from two places:

- `deploy/web-mirror/nginx.conf` sent `Cache-Control: public, max-age=600`
  for everything, and the file names never change between builds
  (`main.dart.js`, `flutter_bootstrap.js`). Now `no-cache`: the browser
  revalidates every file (304 when unchanged). The workflow copies this
  file into `web-dist`, so the next deploy carries it. GitHub Pages keeps
  its own fixed headers.
- `UpdateGate` returned at once on the web, so a page left open or added to
  the home screen never learned of a new build. Now, on the web, it
  compares its `NUKHBA_BUILD_SHA` with the newest release
  (`GET /app/latest-build`, tag `build-<sha>`) and offers "تحديث الآن",
  which reloads the page (`reloadPage`, `core/platform/browser_url*.dart`).
  Asked on opening and again when the player returns after 30 minutes;
  one release is offered again only after 30 minutes, because the release
  is published a few minutes before the web build is live.

No server change, no migration, no new dependency.

### The month turns over (batch 73, server, 2026-09-29)

Requested 2026-09-29: at 00:00 Riyadh on the 1st the app moves to the new
month by itself, every player starts it at zero, the previous month stays
in the records, and the champion's celebration runs for the first 48 hours
of the new month, above the new month's board.

What already held: months are created a week ahead by
`EnsureUpcomingMonthlySeasons` (`monthly_season_scheduler.dart`), they run
00:00 to 00:00 Riyadh (0076), and a month's board sums only its own
fixtures, so the new month starts empty without anything being reset or
deleted.

- **Enrolment on turnover:** `GET /me/active-seasons` now runs the same
  `EnrolInOpenSeasons` as `GET /me` before it reads. `/me` runs once when
  the app opens, so an app left open across midnight asked for its seasons
  after the old month closed and got none. (A month with no fixture yet
  enrols nobody, as before.)
- **Celebration window:** `celebrate_until` is now the month's end + 48 h
  (`ListMonthChampions.celebrateUntil`, `MonthChampion.monthEndAt` read as
  `seasons.end_at`), no longer the crowning + 48 h: a crowning made at 00:30
  or at 09:00 on the 1st both end at 00:00 Riyadh on the 3rd.
- **Prize:** migration 0078 adds `competition.month_champions.prize` (text,
  1-80 characters after trimming, nullable) and adds it to the frozen
  columns of `month_champions_guard_change`. `POST /admin/champions/{id}`
  takes an optional `prize` (trimmed; blank is none; longer than 80 is 400
  `champion.prize_too_long`); `GET /champions` returns it.
  `supabase/tests/0078_champion_prize_test.sql`: 6 checks. **0078 must be
  on the live DB before this server is deployed** (the list reads
  `c.prize`).

### The month turns over in the app (batch 74, 2026-09-29)

The app side of batch 73. No server change, no migration, no new
dependency.

- **Turnover:** `RiyadhDayTurnover` (`core/time/`), started by the shell,
  fires 5 s after 00:00 Riyadh (21:00 UTC, whatever the device zone), once
  more 2 minutes later (a device clock running ahead), and on a return to
  the app after a midnight passed. The shell then invalidates
  `activeSeasonsProvider`, `currentMonthFixturesProvider`,
  `monthChampionsProvider` and `myFixturePredictionsProvider`: the
  leaderboard lands in the new month (its read enrols the player, batch 73)
  and the celebration starts without a restart.
- **Zero at the start:** a month's board sums only its own fixtures, so the
  new month is empty until its first scored match; the month board then
  says so (`leaderboardMonthStarting`), and so does the screen when the new
  month has no fixture yet -- replacing the misleading "join a season"
  prompt. The previous month stays in the records.
- **The hero** (design of 2026-09-29, `champion_spotlight.dart`, rewritten
  whole): brand navy and gold in both themes; ribbons, light and one
  confetti shower; the picture in a gold frame inside a laurel wreath, the
  crown above and the place "1" below; "بطل شهر سبتمبر 2026"
  (`championMonthName`), the name, points and accuracy, "مبروك التتويج",
  "بطل سبتمبر" and the prize. It leads the month's board and scrolls with it
  (`header` on `LeaderboardBoard`, `FixtureStandingsBoard`,
  `AsyncListView`), above the new month's standings; it shows for the
  first 48 hours of the new month (the server's `celebrate_until`).
- **Share:** the champion alone sees "شارك تتويجك"; it sends the hero as a
  picture (`ChampionShareCard`, `share_plus`) with the invitation link.
- **Admin:** a prize field (optional, 80 characters, frozen with the
  crowning) and "تجربة الاحتفال", which opens the real
  `LeaderboardsScreen` with `previewChampions` -- the rehearsal, before the
  month is even over; nothing is sent.
- New l10n keys: `championCongrats`, `championCongratsLine`,
  `championPrize`, `championShareButton`, `championShareMessage`,
  `leaderboardMonthStarting`; `championTitleOne/Two` (ar) now read
  "بطل شهر {month}" with the month by name.

### Hidden and test fixtures; the admin menu by domain (migration 0098, 2026-10-07)

Requested 2026-10-07: the admin menu lists administrative domains, never
single actions, and a fixture can be a test fixture, hidden at once and
shown again, alone or in bulk, with filters. Protection lives on the
server.

- **Data** (0098, additive): `competition.fixture_schedules.hidden_at`
  (null while visible) and `is_test` (fixed at registration). Triggers, the
  backstop: no prediction written on a hidden fixture; a test fixture
  predicted by admins only; no `scoring.fixture_scores` row for a hidden or
  test fixture; no `ledger.fixture_point_entries` row for a test fixture;
  `is_test` cannot change. The rescore sweep
  (`scoring.fixtures_with_unscored_predictions`) leaves both out. Audit
  actions `fixture_hidden` / `fixture_shown`.
  `supabase/tests/0098_fixture_visibility_test.sql`: 15 checks. **0098 must
  be on the live DB before this server is deployed** (the schedule reads
  select the new columns).
- **One rule** (`FixtureVisibility`, application): a player never reads,
  predicts or sees revealed predictions of a hidden or test fixture
  (`prediction.fixture_unavailable`); an admin sees test fixtures, flagged,
  and hidden ones only in the admin list. Applied in the month feed,
  `GET /seasons/{id}/fixtures` (`?include_hidden=true` honoured for admins
  only), `SubmitFixturePrediction` (a test prediction feeds no
  gamification), `ListFixturePredictions`, `ListMyFixturePredictions` (a
  hidden fixture's prediction waits out of sight), `ScoreFixture` (hidden
  and test: no score, no push) and `PostFixtureToLedger` (test: nothing).
  The day sets (daily challenge, settled days, streak, reminders, pre-match,
  streak saver) leave both out; the champion's unscored count ignores test
  fixtures; provider sync never matches a test fixture.
- **Command:** `POST /admin/fixture-visibility` `{fixture_ids, hidden}`
  (`AdminSetFixturesHidden`, up to 200 ids, one audit entry per changed
  fixture; `PostgresFixtureVisibilityStore` drops the schedule cache).
  `POST /fixtures` takes `is_test`.
- **Admin menu:** نظرة عامة / المسابقات والمباريات (المسابقات الشهرية،
  المباريات، التوقعات، النتائج والاحتساب، المباريات المحتسبة) / النقاط
  والترتيب (الترتيب والأبطال، سجل النقاط) / المستخدمون والتفاعل
  (المستخدمون، أسماء المستخدمين، نظام الدعوات) / الإشعارات والتواصل (إرسال
  إشعار) / التدقيق والأمان (سجل التدقيق، سجل الأخطاء). Domains with
  nothing built yet (groups, duels, reactions, notification log,
  gamification, analytics pages, sync/ops) have no entry.
- **المباريات** (`FixturesAdminSection`) replaces the separate add, edit
  and delete sections: the month's list (hidden ones included,
  `adminSeasonFixturesProvider`), filters الكل | ظاهرة | مخفية | تجريبية,
  per row edit / hide-show (immediate) / delete (confirmed), select all in
  the current view and hide or show the selection after a confirmation. The
  add form gains "مباراة تجريبية"; the admin's match card shows
  "مباراة تجريبية". No new dependency, no l10n key.

### The live card and the slow frames (2026-10-07)

Requested 2026-10-07: the matches card during a match after the supplied
design, and the slow frames on the admin card fixed (5.3% overall, 21.1%
on a Redmi Note 9, slowest frame 335 167 ms).

- **After kickoff** the card is `_StartedBody` (`fotmob_match_card.dart`):
  the league, then the minute and a status chip (مباشر red, بانتظار النتيجة,
  انتهت); the two sides as name and crest around the score in a framed box
  (running score, or the recorded result); a strip with the two names and
  the player's call between them (توقعك 2 - 1, the bolt, points once
  graded; لم تتوقّع without one); the split of everyone's calls; the
  "توقعات الجميع" button. Before kickoff the card is unchanged.
- **Large text.** When the framed score (measured at the reader's text
  size) leaves either side less than a crest and the start of its name,
  the score drops under the two sides (`_ScoreRow`); the status chip is
  capped at half the header and ends in an ellipsis. The UI audit had
  caught the score squeezing each side to 4px at x2.0.
- **The split** is three-way over every call, draws included, adding up to
  100 (largest remainder): the tally reader counts draws,
  `FixtureOutcomeTally.outcomeShares`, and the feed item carries
  `home_outcome_share`, `draw_outcome_share`, `away_outcome_share` and
  `total_predictions` (written only when known; an older server sends
  none and the card falls back to the two decisive shares). Shown from
  `minShareSample` calls up. The decisive shares keep their meaning.
- **Frames.** Three things drew frames nobody needed, each a full repaint:
  the live chip's dot pulsed forever (now steady); the shell's
  IndexedStack keeps hidden tabs' tickers running (`Visibility.maintain`),
  so the pulse and the bell kept drawing over whatever tab was open --
  hidden tabs now sit under `TickerMode(enabled: false)`, and the bell
  blinks only while its tab is visible; every crest had a blurred halo,
  redrawn on every scrolled frame (removed). The reporter no longer
  counts a timing over 10 s (`FrameReporter.suspendedAfter`): that is the
  app suspended mid-frame, not a frame -- the source of the 335 167 ms.
  The effect is read on the admin card by build, once the release is out.
- No migration, no new dependency, no l10n key.

### The admin menu by the admin's day; analytics (2026-10-07)

Requested 2026-10-07 (the owner, reviewing the panel on the phone): a
cleaner panel, with no group that holds a single entry. This replaces the
menu line of the entry above; the domain rule stands (one entry per domain,
never per action; nothing listed that is not built).

- **Menu** (`_adminNavGroups`, `admin_shell.dart`): الرئيسية alone at the
  top with no group title (the title is now nullable) / المباريات والنتائج
  (المباريات، النتائج والاحتساب، المباريات المحتسبة) / المسابقات والترتيب
  (المسابقات الشهرية، الترتيب والأبطال، التوقعات) / اللاعبون والتواصل
  (المستخدمون، أسماء المستخدمين، نظام الدعوات، سجل النقاط، إرسال إشعار) /
  النظام (التحليلات، سجل التدقيق، سجل الأخطاء).
- **التحليلات** (`AdminSection.analytics`, `AdminAnalyticsSection`): the
  retention card («هل يعود اللاعبون؟», batch 67) and the smoothness card
  («سلاسة التطبيق», 2026-09-24) moved off the dashboard unchanged, each with
  its own provider and states. The dashboard keeps what needs a decision
  today; its rework is the next batch.
- Tests: `admin_analytics_section_test.dart` (through the real hub on a view
  tall enough that the lazy lists build to their end); the dashboard test
  now asserts the cards are gone, after proving the list was built to its
  last item; UI-37 reads the first titled group.
- No migration, no new dependency, no l10n key, no server change.

### The admin home: what needs a decision first (2026-10-07)

Requested 2026-10-07 (the owner, reviewing the panel on the phone): the
home page was a pile of equal cards with raw codes, ids and UTC instants.
`AdminHomeSection` (`admin_home_section.dart`) replaces
`AdminDashboardSection` (file and test removed), top to bottom:

- **يحتاج تدخلك**: one row per thing waiting, each with its count and
  opening its section -- matches over with no result (past `liveWindow` or
  reported finished, no recorded result; the month feed, so hidden and test
  fixtures never count), invitations `held` (`GET /admin/referral-overview`)
  and errors in the "new" list (`GET /admin/errors`). The last two come
  from `adminAttentionProvider` (plain provider, both reads in parallel); a
  failed read is null and shows «تعذّر التحقق من ...», never a false zero.
  Nothing waiting reads «لا شيء ينتظرك الآن».
- **مباريات اليوم**: the Riyadh day's fixtures (`RiyadhDayTurnover.riyadhDayOf`,
  migration 0076), kickoff through `formatTimeOfDay`, state in words
  (قادمة / مباشرة / بانتظار النتيجة / انتهت 2-1).
- **نبض اللعبة**: players (user-stats aggregate), played this week
  (`GET /admin/retention`, the week in progress), suspended, matches left
  this month; each opens its section. "Active" meaning "not suspended" is
  gone: it contradicted the weekly figure.
- **آخر الإجراءات**: each audit entry as a sentence (`auditActionLabel`,
  the domain's wire tokens; an unknown token reads «إجراء إداري»), with the
  match's name when it points at one of the month, and its time. No id or
  token is shown.
- Removed: the duplicated title, «مركز العمليات» and its refresh button
  that did nothing, «إجراءات سريعة» (the menu says the same), the month's
  list with raw `...000Z` instants. Forward buttons use `ForwardChevron`;
  the reversed `arrow_back` was the only arrow in the admin panel.
- The section takes an optional clock (`now`), the pattern of
  `RiyadhDayTurnover`; `admin_home_section_test.dart` runs at a fixed
  15:00 Riyadh. `fixture_predictions_reveal_test.dart` failed in a run at
  00:03: its two started matches fell on either side of midnight. Its
  helper now keeps both in one local day. The other tests that place
  kickoffs relative to now use a single kickoff, so the day cannot split.
- Every ListTile on a card sits in a transparent Material (the panel's
  rule; a card's colour hides its ink). The open buttons carry their key
  on the button, not on the full-width Align, and let the label wrap: the
  survey's phone at text x2 overflowed by 80px. The survey draws the home
  with empty data, so a test draws every row at 360px and text x2.
- No migration, no new dependency, no l10n key, no server change.

### The admin home: the month and its crowning (2026-10-08)

- **مسابقة الشهر** (`AdminMonthCard`, `widgets/admin_month_card.dart`), between
  today's matches and the pulse: the month running now (its own `startAt`
  and `endAt` from `GET /months`), the time it has left, and the top of its
  live board from `GET /admin/champions/{id}` -- the players' monthly
  ranking, top five, every tie for first kept (`MonthFinalBoard`). Opens
  «الترتيب والأبطال».
- **يحتاج تدخلك** gains «أشهر انتهت بلا تتويج»: ended months, among the last
  three, with players on their board and no champion. A month with nobody
  on its board has no one to crown and is not counted.
- `adminMonthPulseProvider` (plain provider, `admin_providers.dart`) reads
  the months, then the boards in parallel; its choices are the pure
  `adminMonthsAt` and `uncrownedMonths`, tested on their own. A failed read
  shows «تعذّر تحميل ترتيب الشهر» on the card and adds «التتويج» to
  «تعذّر التحقق من ...».
- Tests: `admin_home_month_test.dart`, through the real home section with a
  fixed clock, including a 360px phone at text x2. UI-34 (known defects)
  now scrolls to the metric cards on its real phone: the new card pushed
  them below the fold, where a lazy list does not build them.
- No migration, no new dependency, no l10n key, no server change.

### The admin menu counts what waits (2026-10-08)

- Beside four menu entries, a count when something waits there: النتائج
  والاحتساب (matches over with no result), نظام الدعوات (invitations
  held), سجل الأخطاء (new errors), الترتيب والأبطال (ended months with
  players and no champion). `adminNavCounts` builds them from the very
  sources and functions of the home page's «يحتاج تدخلك»
  (`fixturesAwaitingResult`, `adminAttentionProvider`,
  `adminMonthPulseProvider`), so the two never disagree; a source not
  loaded or failed adds no count (the home page says the failure).
- `AdminNavList` stays a plain widget with an optional `counts` (its test
  builds it with no ProviderScope); the phone drawer and the desktop
  sidebar read `adminNavCountsProvider` through a `Consumer`.
- Removed from `AdminDashboardSnapshot`: `activeUsers`, `todayFixtures`
  (it counted the device's local day, not Riyadh's) and `upcomingFixtures`,
  unused since the old dashboard went.
- Tests: `admin_nav_counts_test.dart`, through the real hub on the desktop
  sidebar and the phone drawer, checking the counts against the home rows.
- No migration, no new dependency, no l10n key, no server change.

### Matches waiting for a result; test fixtures (2026-10-08)

- Correction to the home-page entry of 2026-10-07: the admin's month feed
  DOES carry test fixtures (`SeasonFixtureCardDto.isTest`, migration 0098),
  and a test fixture is never scored by design, so it was counted as
  "over with no result" forever (the owner's «أبها × الأهلي»).
  `fixturesAwaitingResult` now leaves test fixtures out, and so do «مباريات
  اليوم» and «مباريات متبقية هذا الشهر». The menu count follows, being
  built on the same function.
- **بانتظار النتيجة** (`AdminAwaitingResults`) atop النتائج والاحتساب: the
  same list the home page counts, each match filling the form (league,
  month, match) on a tap.
- The season picker names a month as the app does everywhere
  (`monthLabelFromStored`: «شهر 10», not «10/2026»).
- Deleting a predicted or scored match: the server still refuses
  (`competition.fixture_has_predictions`,
  `competition.fixture_result_already_recorded`; no deletion of predictions
  or points, 2026-09-09), but the admin now reads why and what to do
  instead: «… فلا يمكن حذفها. أخفِها بدلاً من ذلك.» A test fixture that
  admins predicted is hidden, not deleted.
- Tests: `admin_results_awaiting_test.dart`, through the real results
  screen with only the HTTP answers faked (`buildAdminHarness`).
- No migration, no new dependency, no l10n key, no server change.

### The monthly competition's name (migration 0099, 2026-10-08)

- The one competition that holds every monthly season was named «شهر 9»
  when it was created in September, so every admin screen read it as
  September while it holds 09/2026, 10/2026, 11/2026... Requested
  2026-10-08: renamed «المسابقة الشهرية». The name is display only (no code
  matches on it); id, seasons, fixtures, predictions, points and champions
  are untouched.
- 0099 (modify-only, safe to re-run): `competition.rename_competition(from,
  to)` renames exactly one competition so named; none is a no-op (a fresh
  database, or already renamed), more than one raises rather than guess.
  Revoked from public, anon and authenticated. The migration calls it once
  and records itself.
- `supabase/tests/0099_rename_monthly_competition_test.sql`: 8 checks (one
  renamed, another kept, months untouched, a second run changes nothing, two
  same-named competitions stop the rename, no client may call it). Run with
  the stubs and all 99 migrations on PostgreSQL 16 before sending: 28 of 28
  SQL tests pass.
- **Apply 0099 in the Supabase SQL editor after the push**; until then the
  migration-drift check reports it missing.
- Do not create a second competition for months: each month is a season of
  this one, and a new competition would split fixtures and points.

### The monthly head-to-head league (migration 0100, 2026-10-10)

Proposed by the players' group (captain Sulaiman), decided 2026-10-09/10 and
checked against September's real data (simulation: 105 players, 19 rounds;
division 1 decided by predictions in 92% of matches, division 4 in 2%, hence
the activity rule below). It replaces the weekly league on screen from
November 2026; the weekly tables stay. The rules document lives outside the
repository (Claude doc "دوري المواجهات الشهري — القواعد النهائية").

- **Divisions** (`H2hDivision`): 20 / 20 / 20 / the rest (the fourth in
  even groups of up to 20). Drawn on the month's first night from the
  `next_division` of last month's `h2h_league_finished` events, plus new
  players at the end. Only a player who predicted on 5 days of the month
  before is drawn (`H2hLeaguePolicy.minActiveDays`). The first public month
  is November 2026, seeded from October's points.
- **Rounds**: a day an admin approves, numbered in date order, at most 19 a
  month. A day of 6+ fixtures is regular (the system approves it 24 h
  before its first kickoff when no admin did); a day of exactly 5 is a fill
  round, admin only. A round's fixtures are every fixture of the day, frozen
  at its first kickoff (`h2h_round_fixtures`); a fixture moved off the day,
  hidden or never scored is void for both sides. Only the last round may be
  withdrawn, and only before it locks.
- **A round**: fixed circle-method pairing by slot. More points wins, equal
  draws; the one who predicted beats the one who did not; both absent both
  lose; an empty seat plays the group average.
- **Table**: 3/1/0, prediction points, head-to-head among the tied, exact
  scorelines, seat, user id.
- **Month end**: up to 3 cross each boundary (never more than half a
  division), the fourth's group winners first; inactive members are not
  drawn and the divisions above the fourth are refilled to 20 from below.
  No ledger points.
- **Pilot**: flag `h2h_pilot` (0054); users with variant `pilot` play a
  hidden trial month (`h2h_months.is_pilot`) whose results decide nothing.
- 0100 (additive): `h2h_months`, `h2h_leagues`, `h2h_league_members`,
  `h2h_rounds`, `h2h_round_locks`, `h2h_round_fixtures`,
  `h2h_month_closures`; append-only, server-only; triggers keep slots in
  their group, rounds in order and withdrawals to the last unlocked round.
- `supabase/tests/0100_h2h_leagues_test.sql`: 24 checks. Run with the stubs
  and all 100 migrations on PostgreSQL 16 before sending: every SQL test
  passes.
- **Apply 0100 in the Supabase SQL editor after the push.**
- **Batch 2 (application, 2026-10-10)**: ports `H2hLeagueStore`,
  `H2hRoundStore`, `H2hDrawSource`, `H2hSheetReader`; use-cases
  `DrawH2hMonth` (seed or carry, once per month, waits for last month's
  close), `StartH2hPilot` (admin, before November), `ApproveH2hRound` /
  `WithdrawH2hRound` / `ListH2hRounds` (admin), `RunH2hRounds` (scheduler:
  auto-approve regular days 24 h ahead, lock at first kickoff),
  `CloseH2hMonth` (events after grace and settlement; a pilot month closes
  without events), `GetMyH2hLeague` (table over settled rounds, live match,
  upcoming opponents, zones). Names reuse `WeeklyLeagueProfileReader`.
- **Batch 3 (Postgres, 2026-10-10)**: `PostgresH2hLeagueStore` (draw in one
  transaction that starts with the month row, so a month is seated once),
  `PostgresH2hRoundStore` (a day = visible, non-test, season fixtures by
  Riyadh date; lock freezes fixtures then the lock row; the 0100 refusals map
  to `h2h.round_*` invariant codes), `PostgresH2hDrawSource` (active days,
  carried finishes, pilot order), `PostgresH2hSheetReader` (round points over
  the frozen fixtures still on the round day; settled = every fixture has a
  result and no pending score; void = none left).
  `supabase/tests/0100_h2h_queries_test.sql` PREPAREs the adapters' SQL text
  for text and checks it on a seeded month (25 checks); all 30 SQL tests
  pass on PostgreSQL 16 with all 100 migrations.
- **Batch 4 (server, 2026-10-10)**: contracts `h2h_league_dto.dart`
  (`MyH2hLeagueDto` with standings, rounds and zones; `H2hRoundsOverviewDto`;
  `H2hApproveRoundRequestDto`; `H2hPilotStartedDto`), mapper
  `apps/server/lib/http/h2h_league_dto_mapper.dart` (form = the last five
  settled results; a live round carries its score so far; a void or
  upcoming round carries none). Routes: `GET /me/h2h-league`;
  `GET /admin/h2h/rounds?day=` (the month's rounds and the days that may be
  approved next), `POST /admin/h2h/rounds {"day"}` (201 with the round),
  `DELETE /admin/h2h/rounds/{id}` (204), `POST /admin/h2h/pilot`
  (`{"seated"}`). Scheduler `h2h_league_scheduler.dart` every 5 minutes:
  `RunH2hRounds`, then `CloseH2hMonth`, then `DrawH2hMonth`; a failed job
  is reported and does not stop the next. All eight use-cases are wired in
  `CompositionRoot` (one `_UnwiredH2h` stand-in for the test roots).
- **Batch 5 (mobile tab, 2026-10-10)**: the bottom bar reads home,
  leaders, المواجهات, matches, account (each item keeps its page index, so
  push links and screen names are unchanged; page 2 is now `H2hScreen`).
  `apps/mobile/lib/features/h2h/`: `myH2hLeagueProvider`
  (`AuthApi.myH2hLeague`), `h2h_texts.dart` (Arabic words, like the duels),
  `H2hScreen` (not started / draw pending / not in draw with the rules; the
  open month: division banner, the featured match -- live, else next, else
  last -- the group table with zone bars and form, and every round).
  "توقعاتي" opens from a home card above the daily challenge as a pushed
  page (`ScreenNames.predictions`); screen name `h2h` added on both sides.
- **Batch 6 (admin, 2026-10-10)**: admin hub section "دوري المواجهات"
  (`AdminSection.h2hLeague`, `h2h_admin_section.dart`): this month or the
  next (the next is derived from the server's month, never the device
  clock), the draw, the approved rounds with a withdraw button on the last
  one not started, the candidate days with an approve button (a five-match
  day is marked as a fill round), and before the launch the pilot button
  behind a confirmation. `AdminApi.h2hRounds/approveH2hRound/
  withdrawH2hRound/startH2hPilot`. Server: `DELETE /admin/h2h/rounds/{id}`
  answers `{"withdrawn": true}` (the client decodes every answer as JSON),
  and `H2hRoundsOverviewDto` carries `starts_on`.
- **Migration 0101 (admin controls, 2026-10-10)**: `h2h_settings` (one row:
  `auto_approve`, `auto_approve_lead_hours` 1..24, `min_active_days` 1..28;
  the defaults are the rules of 0100), `h2h_day_exclusions` (days the
  system must not approve by itself), `h2h_admin_actions` (append-only
  log of every admin action). Ports `H2hControlStore`,
  `H2hMonthReportReader`; adapters `PostgresH2hControlStore` (a late seat
  is a plain insert that 0100's constraints police: `h2h.seat_taken`,
  `h2h.player_seated`, `h2h.seat_outside_group`, `h2h.player_unknown`)
  and `PostgresH2hMonthReportReader`. Tests
  `0101_h2h_admin_controls_test.sql` (12 checks) and
  `0101_h2h_control_queries_test.sql` (16 checks, the adapters' SQL text).
  **Apply 0101 in the Supabase SQL editor before pushing the server batch
  that reads it (92).** Nothing reads these tables yet.
- **Batch 91 (admin desk, application, 2026-10-11)**: `AdminH2hControls`
  (`admin_h2h_controls.dart`): `view` (the settings, the month's days
  from today on -- not started, or excluded -- with the round each one
  already is, and the last 30 lines of the admin log with the admins'
  names), `saveSettings` (lead 1..24 h, active days 1..28, else
  `h2h.settings_out_of_range`), `setDayExcluded` (a past day is
  `h2h.day_past`; only a change is logged), `addSeat` (month drawn and
  open, the group its own, the slot inside it, the player not seated:
  `h2h.month_not_drawn`, `h2h.month_closed`, `h2h.group_unknown`,
  `h2h.seat_outside_group`, `h2h.player_seated`), `report` (the 0101
  month report) and `runJobs` (rounds, close, draw now, as the
  scheduler does; logged as `jobs_run`). `H2hAdminDesk` holds these and
  the three admin readings of batch 89 for the composition root.
  `DrawH2hMonth` and `CloseH2hMonth` take optional controls and read
  `min_active_days` from `h2h_settings` (the policy's five without
  them).
- **Batch 92 (admin desk, server, 2026-10-11)**: contracts
  `h2h_admin_controls_dto.dart` (`H2hSettingsDto` with its bounds,
  `H2hSettingsRequestDto`, `H2hControlDayDto`, `H2hAdminActionDto`,
  `H2hControlsDto`, `H2hDayExclusionRequestDto`, `H2hSeatRequestDto`,
  `H2hMonthReportDto`, `H2hJobsRunDto`) and `free_slots` on
  `H2hAdminGroupDto` (additive); mapper
  `apps/server/lib/http/h2h_admin_dto_mapper.dart`. Routes (admin
  only, the gate in the use-cases): `GET /admin/h2h/groups?day=`,
  `GET /admin/h2h/groups/{id}/rounds/{n}?day=` (names and stored points,
  no pick), `GET /admin/h2h/players/{id}` (the player's month as
  `/me/h2h-league` reads it for them), `GET /admin/h2h/controls?day=`,
  `PUT /admin/h2h/settings`, `POST /admin/h2h/exclusions`
  (`{"changed"}`), `POST /admin/h2h/seats` (201 `{"seated": true}`),
  `GET /admin/h2h/report?day=`, `POST /admin/h2h/jobs`.
  `CompositionRoot.h2hAdminDesk` wires them; the scheduler's
  `CloseH2hMonth` and `DrawH2hMonth` now read `min_active_days` from
  `h2h_settings` (default 5: no change until an admin changes it).
  Reads 0101 (applied).
- **Batch 93 (admin dashboard, mobile, 2026-10-11)**: `AdminApi`
  `h2hGroups`, `h2hGroupRound`, `h2hPlayer`, `h2hControls`,
  `saveH2hSettings`, `setH2hDayExcluded`, `addH2hSeat`, `h2hReport`,
  `runH2hJobs`. The admin hub's "دوري المواجهات" section is now five
  tabs over one header (title, tab chips, this/next month chips but on
  the player tab): الجولات (batch 6, unchanged), المجموعات (each group's
  table with zone bars, a round's matches by names and points, and a
  late seat: find the player by name or email, pick an empty seat),
  لاعب (a player's month as they see it), الإعدادات (automatic approval,
  lead hours, active days with the server's bounds; each upcoming day of
  the month with a switch to keep it from automatic approval -- a day
  that is already a round has none; run the jobs now behind a
  confirmation) and التقرير والسجل (the 0101 month report and the admin
  log in Arabic). `h2h_admin_tabs.dart` holds the four new tabs and
  their providers; the new refusal codes read in Arabic in
  `h2hAdminErrorMessage`.

### The predictions board in one request (2026-10-11)

- **Batch 94 (predictions board in one request, server, 2026-10-11)**:
  measured first: on 2026-10-10 at 22:10 UTC the board of a day with
  21 started matches sent 3 requests per match (predictions, scores,
  reactions); the server's CPU peaked, probe latency reached 5.5 s,
  and the error log holds `db.query_timeout` on the three routes
  (`connections in use 8/8, waiting 54..148`) while Supabase showed
  CPU ~3 %, IOPS 6 and 18 of 60 connections -- the server, not the
  database, was saturated. `GET /seasons/{id}/predictions-board?
  fixtures=a,b,...` (`GetPredictionsBoard`, 1..40 ids, a repeated id
  once) answers the whole board: every fixture through the same
  `ListFixturePredictions` gate, 3 at a time; scores
  (`listBySeasonFixtures`) and results (`findByFixtures`) in one
  query each; reactions 3 at a time (unreadable ones leave the
  column without them). A refused fixture is a column with its
  `error_code` and `retryable` (true only for a transient failure);
  a failed batched read is the usual 503. Contracts
  `PredictionsBoardDto` / `PredictionsBoardColumnDto` reuse the three
  per-fixture shapes. The per-fixture routes stay for the other
  screens. No migration.
- **Batch 95 (predictions board in one request, mobile, 2026-10-11)**:
  `PredictionApi.predictionsBoard` and `predictionsBoardProvider`
  (`predictions_board_providers.dart`): the board page reads the day
  with one request per season (`predictionsBoardKeys`, 40 fixtures at
  most each) instead of predictions + scores + reactions per started
  match; a failure of the whole read with a transient code is asked
  again after 2, 4 and 6 s, a refusal is shown at once. A column that
  could not be read keeps its red mark, now with the reason in Arabic
  (`predictionsBoardErrorText`) and a tap that reads the board again
  (`fixturePredictions.retry.<fixtureId>`). Once one of a match's
  predictions is tapped, that match's reactions follow the sheet's own
  `predictionReactionsProvider`, so a reaction still shows at once.
  The widget-test harness answers the board from the per-match
  handlers (`composePredictionsBoard`) without adding them to
  `captured`.

### Adding groups to a drawn month (2026-10-11)

- **Batch 96 (extra groups, server, 2026-10-11)**: the October pilot
  was drawn with one group of twenty (first division); 72 players
  without a seat had predicted on five days or more of October by
  the 11th. Decided with the owner: the players who play the most get
  a seat first, and the new groups take the next places of the
  ladder. `POST /admin/h2h/extra-groups {"groups": 1..10}`
  (`AddH2hGroups`): the players with no seat in the month open now who
  predicted on the settings' `min_active_days` of it, most days
  first, then points, exact scorelines, user id
  (`PostgresH2hGroupExtension.waitingSql`), dealt twenty to a group by
  `H2hLeaguePolicy.extend`: each division above the open one with no
  group yet, top down, then new groups of the open division; a single
  player left at the end waits. Groups and seats are ordinary 0100
  rows written in one transaction (0100's constraints refuse a place
  or a player taken twice: `h2h.group_taken`, `h2h.player_seated`);
  `h2h_months.seated_count` keeps the seats of the draw itself. A
  month not drawn or judged, fewer than two waiting, or a count
  outside 1..10 is refused. Rounds belong to the month and the
  schedule to the slot, so a group added late plays every round of
  the month, the ones already played included, from its members' own
  predictions. Migration 0102 widens 0101's admin-log check with
  `groups_added` (logging is best-effort: before 0102 the groups are
  still added, the log line is lost).
- **Batch 97 (extra groups, mobile, 2026-10-11)**:
  `AdminApi.addH2hGroups`; the dashboard's settings tab has an
  "مجموعات إضافية" card: a count from 1 to 10, a confirmation (the
  addition cannot be undone), then the groups, seats and players
  still waiting read back. The log names `groups_added` and its
  groups and seats; the new refusals are in Arabic.

### AFC Champions League Elite in the catalog (2026-10-11)

- **Batch 98 (catalog, 2026-10-11)**: migration 0103 adds
  `دوري أبطال آسيا للنخبة` (short `ACLE`, `is_continental`, so the
  admin picker offers the whole catalog) and the 32 clubs of the
  2026-27 league stage (en.wikipedia.org, checked 2026-10-11): the
  Saudi five (saudi seed) and Al Ain (0050) reused, 26 created with
  Arabic names, `league_id` and crest NULL (initials until a crest is
  added), all mapped under the identity source `acl_elite`; a club
  already in the catalog by name is reused. East clubs are included
  so a West-East tie shows both names. Decided with the owner: the
  West matches, entered by an admin -- no provider rule. Applied by
  hand in the SQL Editor like every migration.
- **Batch 99 (league mark, mobile, 2026-10-11)**: the trophy of the
  owner's AFC Champions League Elite logo (cropped from the full
  mark, 374x512, palette PNG) as
  `assets/league_logos/afc-champions-league-elite.png`, resolved by
  `competitionLogoAsset` for `دوري أبطال آسيا للنخبة`,
  `دوري أبطال آسيا` and `AFC Champions League Elite`.
- **Batch 100 (crests, mobile, 2026-10-11)**: six crests the owner
  supplied (256x256, transparent) for clubs of 0103: فيسيل كوبي،
  السد، تراكتور، الغرافة، جوهور دار التعظيم، شنغهاي بورت. Nine more
  he sent (Machida, Ulsan, Chengdu, Al-Duhail, Sanfrecce, Melbourne
  City, Shanghai Shenhua, FC Seoul, Nasaf) are not in the 2026-27
  league stage and were not added; Ulsan already had a crest.
- **Batch 101 (crest fix, mobile, 2026-10-11)**: `newcastle.png` and
  `coventry-city.png` under `assets/team_logos/` were ~61 KB of
  unreadable bytes (no PNG signature), so both clubs showed initials
  though their names resolved; replaced with the 512x512 PNGs from
  the owner's Premier League 2026-27 set. `logo_files_valid_test`
  now fails on any bundled crest or league mark without the PNG
  signature; `bayer-leverkusen.png` is the one known broken file
  left, listed there until its crest arrives.

### The admin's matches by day; a league's clubs first (2026-10-11)

- **Batch 102 (mobile, 2026-10-11)**, requested by the owner from three
  screenshots. (1) Before kickoff the card reads 0% on both sides under
  `minShareSample` decisive calls, instead of leaving the place empty;
  after kickoff the split stays hidden under the sample. The gate itself
  dates from 2026-10-07, so a "100%" on a live card means at least five
  decisive calls, all for one side (draws are not in that share). (2) The
  admin's matches list puts each Riyadh day under its own header
  (`adminFixtureDayOf`, `admin.matches.day.<yyyy-mm-dd>`, the day's count),
  newest day first, like the edit form's fixture dropdown already did.
  (3) Both match forms offer a league's clubs first and alone
  (`teamPickerLeagueOptions`, `team_picker_league_scope.dart`): a national
  league its clubs by `league_id`; a continental one -- whose clubs keep
  their own league row, 0103 -- the rows filed under it plus the clubs
  already on its matches in the month (by id, else by exact name), and
  the whole catalog only when none of those matches what is typed. The
  edit form takes the fixture's own league when none is picked (matched
  by name: the browse read carries no league id). No migration, no new
  dependency, no l10n key. Crests: 20 of 0103's 32 clubs still show
  initials; the West ones (الوصل، شباب الأهلي، الشمال، استقلال طهران،
  نفتشي فرغانة، باختاكور، القوة الجوية) wait for the owner's PNGs.
- **Batch 103 (crests, mobile, 2026-10-11)**: six of those crests the
  owner supplied, 256x256 transparent PNGs (three sent at 512 resized
  and reduced to a palette): الوصل `al-wasl`، شباب الأهلي
  `shabab-al-ahli`، الشمال `al-shamal`، باختاكور `pakhtakor`، نفتشي
  فرغانة `neftchi-fergana`، القوة الجوية `al-quwa-al-jawiya`, each in
  `_arabicTeamLogoAliases` and `_monthlyLogoSlugs`. Esteghlal
  (استقلال طهران) is the West club still on initials.

### A match card reads its scores after the result (2026-10-11)

- **Batch 104 (mobile, 2026-10-11)**: measured first: the error log's
  samples (`ops.error_samples`) of 2026-10-11 on the scores route
  (AGMU, U9H3, XT7E) read 'waited 8.8-9.6 s for a connection, ran
  0.5-1.4 s; connections in use 8/8, waiting 71..99' (build e3e3153,
  after batches 94-95): the queue, not the SQL. The matches screen
  still sent one `GET .../fixtures/{id}/scores` per started card with a
  call, again every 2 minutes while the grade was pending, so a day of
  12 matches polled through every match's play. `FotmobMatchCard` now
  reads the scores only once the feed item carries the recorded result
  (`resultHomeGoals`/`resultAwayGoals`): no grade exists before it. The
  feed itself refreshes every 2 minutes while a match is live, so the
  grade follows the result as before. The other score readers (history,
  the predict sheet, the prediction screen) are unchanged. No server
  change, no migration.

### The big derbies (2026-10-12)

- **Batch 105 (catalog, 2026-10-12)**: migration 0104 adds
  `ديربيات كبرى` (short `DRB`, `is_continental`, so the admin
  picker offers the whole catalog) and the 31 clubs of fifteen derbies
  whose league the app does not carry: Cairo, Casablanca, Tunis,
  Omdurman, Algiers, Amman, Baghdad, Tehran, Buenos Aires, Rio, Glasgow,
  Istanbul (three clubs), Athens, the Netherlands and Lisbon. Clubs of
  0050 and 0103 are reused through their identities, clubs of the
  2026-27 seeds by their Arabic name; the 14 new ones have `league_id`
  and crest NULL (initials until a crest is added). All are mapped under
  the identity source `big_derbies`. Decided with the owner: one derby
  at a time, entered by an admin -- no provider rule -- so the matches
  tab carries the derby and not the rest of its league. Applied by hand
  in the SQL Editor like every migration. Crests for the new clubs are a
  later batch, from the owner's PNGs.
- **Batch 106 (crests, mobile, 2026-10-12)**: the owner supplied the
  crests of the 14 new derby clubs and of Esteghlal (PNG, 256-600 px;
  Al-Merrikh on white and Al-Hilal Omdurman on a checkerboard, both cut
  out here), made 256x256 transparent palette PNGs: zamalek,
  raja-casablanca, club-africain, al-hilal-omdurman, al-merrikh,
  mc-alger, usm-alger, al-faisaly-amman (the Jordanian club; the Saudi
  al-faisaly keeps its own), al-wehdat, al-zawraa, persepolis,
  esteghlal, rangers, panathinaikos, ajax; each in
  `_arabicTeamLogoAliases` and `_monthlyLogoSlugs`. The catalog name
  of Besiktas (from the provider map) gets an alias to the bundled
  `besiktas` crest. `acl_elite_crests_test` now checks initials on a
  club still without a crest (Gamba Osaka); `big_derbies_crests_test`
  is new. Every club of 0104 now shows a crest.

### Super cups and the CAF Champions League (2026-10-12)

- **Batch 107 (catalog, 2026-10-12)**: migration 0105 adds three super
  cups beside the Spanish one of 0045 -- Italian, French, German, each its
  own competition (decided with the owner) -- and the CAF Champions
  League, all `is_continental` (the admin picker offers the whole
  catalog), entered by an admin. The super cups need no club. The CAF
  group stage is not drawn yet (second round 13-25 October 2026), so
  the big contenders the catalog lacked are created under the identity
  source `caf_cl` (Pyramids, RS Berkane, Orlando Pirates, Young
  Africans, Simba; crest NULL); the others were there already (0050,
  0104). Competition marks and the five crests are a later batch, from
  the owner's PNGs. Applied by hand in the SQL Editor.
- **Batch 108 (marks and crests, mobile, 2026-10-12)**: the owner's
  PNGs. Six competition marks under `assets/league_logos/`, each cut
  to its emblem (the wordmark below is unreadable on the 14 px plate):
  supercopa-de-espana, supercoppa-italiana, trophee-des-champions,
  dfl-supercup, caf-champions-league (the trophy), fa-cup; each in
  `kLeagueLogoAssetsByName` under its catalog name (0045, 0105) and its
  English one. Six crests at 256x256: the five CAF clubs of 0105
  (pyramids, rs-berkane, orlando-pirates, young-africans, simba) and
  `bayer-leverkusen.png`, the last unreadable file, replaced, so
  `logo_files_valid_test` waits for no crest any more. New test
  `cup_marks_and_caf_crests_test`.
- **Script 127 (catalog, Conference League, 2026-10-20)**: migration
  0180 adds دوري المؤتمر الأوروبي (short `UECL`, `is_continental`, so the
  admin picker offers the whole catalog), entered by an admin, not by
  the provider sync (decided with the owner); no club is created. Its
  mark, `assets/league_logos/conference-league.png`, is cut from the
  owner's screenshot (trophy and green arcs, 153x162, transparent) and
  sits in `kLeagueLogoAssetsByName` under the catalog name and two
  English ones; `logo_url` stays NULL. New tests
  `0180_conference_league_test.sql` and `conference_league_logo_test`
  (the real matches screen). Numbered 0180, after the 0170-0179
  series. Applied by hand in the SQL Editor.
- **Script 130 (catalog, Conference League clubs, 2026-10-20)**:
  migration 0181 records the 36 clubs of the owner's crest pack under
  the identity source `uecl`, reusing a club by its identity, then by
  `competition.team_name_key` of its name or another spelling (Ajax and
  Panathinaikos of 0104, and Brighton, Atalanta, Monaco, Freiburg,
  Getafe of the seeds, are the same rows); 29 are created with no
  league and no crest row. 29 crests (128 px palette PNGs from the pack)
  under `assets/team_logos/`; the seven clubs already bundled keep
  their crest. `team_logo_assets.dart`: the Arabic names and other
  spellings, eleven English provider spellings, the 29 slugs, and a
  `MonthlyCompetitionLogoGroup` for the admin crest gallery. New tests
  `0181_conference_league_clubs_test.sql` and
  `conference_league_crests_test` (the real matches screen). Applied by
  hand in the SQL Editor.
- **Batch 109 (landing page at nukhbaa.app, 2026-10-12)**: the site root
  of the web mirror served only `302 /nukhbaa/`, so a shared link had no
  favicon and no preview card. `deploy/web-mirror/landing/` (index.html,
  favicon.ico/-32/-48, icon-192/-512, apple-touch-icon, og.png 1200x630,
  site.webmanifest, IBM Plex Sans Arabic subset as woff) is copied by
  `deploy-pages.yml` into the root of `web-dist`; `nginx.conf` serves it
  at `/` instead of the redirect. The app stays under `/nukhbaa/`. The
  download button resolves the newest release's arm64-v8a APK through
  `api.github.com` (falls back to the releases page). The app's own
  `web/index.html` gains the same og: tags, so invite links show the
  card. GitHub Pages is unchanged (it never served the root).
- **Batch 110 (social links on the landing page, 2026-10-12)**: the
  links of the owner's links.nukhbaa.app page (WhatsApp channel, X,
  Instagram, Snapchat, Facebook; handle nukhbaa_app) added to
  `deploy/web-mirror/landing/index.html` under "تابعنا", and as
  `sameAs` of the Organization in its JSON-LD, so nukhbaa.app can
  replace links.nukhbaa.app in profile bios. links.nukhbaa.app is not
  in this repository; its APK button pointed at build-07340aa.
- **Batch 111 (compact link preview, 2026-10-12)**: the owner wants the
  small logo beside the title, not the wide 1200x630 card. og:image is
  now the square `icon-512.png` (512x512) and `twitter:card` is
  `summary`, in the landing page and in the app's `web/index.html`;
  WhatsApp, Telegram, Facebook and X show a square image as a small
  thumbnail. `og.png` stays in the landing folder, unused.
- **Batch 113 (two link previews, 2026-10-12)**: the owner picks the
  preview per post. `https://nukhbaa.app` (and the app's
  `web/index.html`, so invite links) carries the wide card (og.png
  1200x630, summary_large_image); `https://nukhbaa.app/s` carries the
  small square logo (icon-512.png, summary). `landing/s/index.html`
  holds only the tags (og:url is /s/ itself, so Facebook does not
  re-scrape the root) and a script that sends a visitor to `/`;
  crawlers do not run it. Undoes batch 111's tags if it ran, adds
  TikTok (https://www.tiktok.com/@nukhbaa.app) if batch 112 did not. `deploy-pages.yml` now
  copies the landing folder with `cp -R landing/.`, since `cp landing/*`
  fails on the s/ folder.
- **Batch 114 (smaller image for /s, 2026-10-12)**: tested on WhatsApp,
  /s still showed the 512x512 logo as a large image; WhatsApp draws
  the small side thumbnail only for a small og:image. /s now points at
  a new `icon-200.png` (200x200, the smallest Facebook accepts).
- **Batch 115 (source chips on announcements, mobile, 2026-10-12)**:
  the owner wants an announcement's link to end with the small site
  mark, as a chat assistant shows its sources. Under the body of a
  notification, every distinct https address of the body is a chip:
  the app's logo (`assets/branding/nukhbaa_logo.png`, already bundled)
  and the host for nukhbaa.app and its sub-domains, a link icon and
  the host for any other site; a tap opens it through
  `notificationLinkOpenerProvider`, as the link in the text does. The
  address is cut as `_LinkifiedBody` cuts it; http is never a chip.
  `notifications_screen.dart`; four new tests in
  `notifications_screen_test.dart`. No server change, no migration.
- **Batch 116 (notification icon, Android, 2026-10-12)**: a push showed
  a grey letter in the shade where the app's mark belongs: no small
  icon was set, so Android fell back to the launcher icon. Five white
  silhouettes of the mark (`assets/branding/notification/`,
  ic_stat_nukhbaa 24/36/48/72/96 px, mdpi..xxxhdpi, not bundled in the
  Flutter assets) are copied by build-verification.yml into the
  generated `res/drawable-*`, with `nukhbaa_notification` = #1978D1, and
  the manifest gets FCM's `default_notification_icon` and
  `default_notification_color`. CI only; no Dart, server or migration
  change. Takes effect with the next APK.
- **Batch 117 ("N matches still to predict" push, 2026-10-12)**: the
  daily reminder (0040) reaches only a player who predicted none of the
  day's matches. A player who predicted some and left others open now
  gets one push a day, 75-105 minutes before the first match they left
  open: "تبقى لديك N مباريات لم تتوقعها اليوم" (Arabic count forms for 1, 2, 3-10,
  11+), N = that day's unpredicted matches not yet kicked off. Owner's
  decisions: an hour and a half before; OUTSIDE the weekly budget of 5
  (so its own table, migration 0106 `notification.incomplete_day_sends`,
  PK (user_id, send_date), which the budget query does not count). It
  obeys the `prediction_reminder` switch and the quiet hours.
  `SendIncompleteDayReminders`, `IncompleteDayReminderRepository`,
  `PostgresIncompleteDayReminderRepository` (SQL checked on a seeded
  Postgres 16), `incomplete_day_scheduler.dart` (10-minute tick),
  composition root and main.dart wiring. A player with a run of 2+ may
  still get the streak saver (45-75 min) the same day. Apply 0106 in the
  SQL Editor BEFORE pushing.
- **Batch 118 (one push per phone, 2026-10-12)**: five players (two of
  them admins) had the Android app and also a browser token (`web`) on
  file, so every push arrived twice; the browser copy showed a grey "N"
  (the app's own copy already shows the mark, batch 116).
  `PostgresDeviceTokenRepository.upsert` is now one statement: a native
  (`android`/`ios`) registration deletes the player's `web` tokens, and a
  `web` registration from a player who has a native token is not kept
  (and is removed if that token was on file). Web-only players (the
  iPhone players) are unaffected. No migration; the existing extra
  tokens go the next time each player opens the app. SQL checked on a
  seeded Postgres 16.

- **Batch 109 (read coalescing, server, 2026-10-12)**: measured first:
  after batch 104 reached the server, `ops.error_samples` still held a
  burst on build 2b9f587 at 2026-10-11 20:41 UTC -- scores (AGMU),
  predictions (FP3B) and U9H3 within eleven seconds, 'still waiting
  for a connection; connections in use 8/8, waiting 150..180'. The
  queries were not slow: the reads were all for the same fixture at the
  same moment (a match ended), and every cache in front of them was
  either missing or had just been dropped by the write (scores evicted
  on scoring, schedules cleared on each sync), so each request ran its
  own query. `ReadCoalescer` (`infrastructure/src/common`) lets the
  requests that arrive while an answer is loading share that load; the
  cache generation is in the key, so a read after a write never joins a
  load begun before it. Used by `CachedFixtureScoreRepository` (and its
  board batch, not cached), `CachedFixtureScheduleRepository`,
  `CachedFixturePredictionTallyReader`, `CachedTeamRepository` and the
  two leaderboard readers. New read-only decorators, wired into the
  read use-cases only (`GetFixtureScores`, `GetFixtureResult`,
  `ListFixturePredictions` and its reveal, `GetPredictionsBoard`):
  `CachedFixtureResultReads` (a fixture's result and the board's,
  'no result yet' included, 20 s) and `CachedFixturePredictionReads`
  (the season link, 60 s; a kicked-off fixture's predictions, 20 s).
  Scoring, the admin forms and submitting a prediction keep the plain
  repositories, so they see every write at once; a result recorded
  elsewhere takes up to 20 s to show on the players' screens. A scores
  request now costs one query of its own (the caller's participation).
  The pool size (8) is unchanged: nothing measured shows what Supabase
  allows. No migration, no client change.

- **Batch 110 (password reset by code, 2026-10-13)**: a player's reset
  e-mail link opened the web build, which stayed on its splash screen,
  so the password could not be changed. The reset now stays in the
  app: the e-mail also carries GoTrue's one-time code (`{{ .Token }}` in
  the Reset Password template, set by hand in the Supabase dashboard),
  the player types it, and `POST /auth/password-reset/verify`
  (`{email, code}`) trades it through GoTrue `POST /verify`
  (`type: recovery`) for the recovery token that
  `/auth/password-reset/update` already takes. Port
  `AuthGateway.verifyRecoveryCode`, use-case `VerifyRecoveryCode`; a
  wrong, used or expired code is `auth.recovery_code_invalid` (Arabic
  message), a code that is not 6..10 digits `auth.recovery_code_format`
  before GoTrue is asked; five codes per address in 15 minutes
  (`AuthAttempt.passwordResetCode`). Mobile: after 'send the code' the
  screen asks for the code (digits only), then opens the new-password
  step; a new code can be asked for after 60 s (GoTrue's own cooldown),
  and the e-mail can be changed. Words in
  `features/auth/password_reset_texts.dart` (generated l10n untouched).
  The web link keeps working. No migration; needs a new APK.

- **Batch 111 (update before sign-in, direct APK link, 2026-10-13)**:
  a player who cannot sign in (the forgotten-password case batch 110
  fixes) never saw the update row, which lived on the account tab only,
  and the links page sent players to the GitHub release page (English,
  six files). The sign-in screen now shows the same 'update available'
  row (`signIn.update`, `pendingUpdateProvider`, set by `UpdateGate` at
  launch -- `/app/latest-build` is public). The release job also
  publishes the arm64-v8a APK as `nukhbaa.apk`, copied after
  `checksums.json` so `/app/latest-build` and the in-app updater never
  see it; the links page (`links.nukhbaa.app`, Netlify Drop, outside
  this repo) links to `releases/latest/download/nukhbaa.apk`. 32-bit
  (armeabi-v7a) phones still take their file from the release page.
  No migration; needs a new APK for the sign-in row.

- **Batch 112 (kickoff follows the provider, 2026-10-13, audit C-03)**:
  every lock, reveal and results window follows `kickoff_at`, and the
  fixtures sync wrote it once and never again -- a match brought forward
  stayed open while it was played, one put back locked early and missed
  its result. `SyncProviderFixtures` now compares a known fixture's
  stored kickoff with the provider's (scheduled, live or finished) and,
  when they differ by a minute or more, moves it while the STORED kickoff
  is still ahead, the new one is in the same monthly contest (the
  freeze rule of `CorrectFixtureSchedule`) and the provider's two teams
  are the catalog ids on file -- so a match linked to the wrong fixture
  (audit C-04) never drags that fixture's kickoff. A provider kickoff already
  past is written as it is, which locks the fixture at once. Anything
  else (stored kickoff passed, another month, other teams) is left for an admin and
  named in the sync notes. `ScoreFixture` grades a prediction stamped at
  or after the stored kickoff `incorrect` for zero points once the result
  is in: the lock refuses such a prediction, so one exists only when the
  kickoff was brought forward after it was sent (by the sync or by an
  admin). `incorrect`, not `missed`: `fixture_scores` allows no `missed`
  and every reader already knows `incorrect`. The periodic fixtures sync
  now runs every 12 hours and includes today (Highlightly, capped at two
  days, sees today and tomorrow: 12 requests a day instead of 6). No
  migration, no client change.

- **Batch 119 (stricter fixture adoption, 2026-10-13, audit C-04)**:
  before adding a provider match the fixtures sync adopts a hand-added
  fixture of the same match, and `findExistingFixture` accepted one team
  plus a name contained in another within three hours: Al Ahli (Saudi)
  took a hand-added Al Ahly (Egypt) card and was never added, and Inter
  could take Milan's, two links on one card, so one result could land on
  the other. `_existingSql` now: never adopts a fixture already linked to
  a provider match; compares a side that has a team on file by that team
  only (a different id is a different club, whatever the name); compares
  only a side typed by hand by its normalised name (equal, or contained,
  three letters at least); needs both sides, except one side certain by
  its team with the other typed by hand and no team on file, within
  three hours; and prefers both teams on file, then both sides agreeing,
  then the nearest kickoff. SQL test
  `supabase/tests/provider_sync_existing_fixture_query_test.sql` (the
  adapter's text, parameters as arguments; the old query fails five of
  its nine checks). No migration, no client change. A read-only check for
  links made before this fix is in the batch's delivery note.

- **Batch 120 (season boards read the fixture store, 2026-10-13, audit
  C-01)**: the "season points" tab (`PostgresLeaderboardRepository.
  _selectSeasonStandingsSql`) and a group's season board
  (`PostgresGroupRepository._selectGroupSeasonStandingsSql`) still read
  `leaderboard.season_standings(_with_movement)`, which sum the round-era
  `ledger.point_entries`, empty since fixtures moved to seasons: every
  player showed 0 points beside real accuracy and movement. Both now read
  every non-suspended participant of the season LEFT-joined to
  `leaderboard.season_fixture_standings` (the monthly board's store; 0
  when nothing is scored), the group one restricted to the group's
  members; the season one takes `previous_rank` from the latest
  `season_rank_snapshots` row and `settled_count` = `decided_count`. The
  old views stay (other objects may read them); nothing in the app reads
  them now. SQL test `supabase/tests/season_and_group_standings_queries_
  test.sql` (the adapters' text; the old views read 0 on its data). Still
  open from C-01: the admin "points ledger" lookup reads the round-era
  ledger too. No migration, no client change.

- **Batch 121 (GoTrue busy is not a rejection, 2026-10-13, audit C-02)**:
  `SupabaseAuthClient` answered every non-2xx from GoTrue as
  `validation auth.rejected` (400), so a refresh that met GoTrue's rate
  limit (429; every player shares this server's one address) or a 5xx
  read, in the app, as a refused token -- and the app signed the player
  out. `_rejection` now keeps `auth.rejected` for a 4xx and makes 429
  (`auth.rate_limited`), 408 and 5xx (`auth.upstream_error`) `transient`,
  answered 503, which the app's `SessionRefresher` already treats as
  "keep the session, retry". Applies to login, register, refresh, Google,
  the reset code and the reset/update actions; a reset code GoTrue could
  not check is no longer called wrong. Still open from C-02 (they need
  the owner's Supabase settings): IP forwarding (`Sb-Forwarded-For` with
  a secret key) so each player has their own GoTrue quota, and a per-IP
  limit on `/auth/refresh` and `/auth/google`. No migration, no client
  change.

- **Batch 122 (open on the remembered profile, 2026-10-13, audit M-04)**:
  measured first: `ops.error_groups` held `api_client.timeout` for 23
  Android and 15 web players since 2026-10-03 (363 times), the samples
  all at launch, four or five routes failing in the same second from one
  device -- a weak link, not the server (no server error beside them;
  responses are already gzip-compressed by the Northflank edge, so audit
  M-33 does not hold). A launch waited for `GET /me` behind a bare
  spinner, up to the 35 s timeout. `TokenStore` now also keeps the profile
  `/me` last confirmed (`nukhba.profile`, secure storage, erased with the
  tokens on sign-out); `SessionController._restore` opens on it at once
  and asks `/me` in the background: a refused token still ends the
  session, a confirmed one refreshes the profile, a failed network leaves
  the player in the app. Only a launch with nothing remembered (the first
  after this update) waits, and its splash now says what it waits for.
  Needs a new APK.

- **Batch 123 (a push nobody got is not "sent", 2026-10-13, audit M-28)**:
  `FcmPushSender.send` answered `Ok` whatever happened to each message,
  so a 429, a 5xx or a network failure on every device looked delivered:
  the reminder, pre-match, streak-saver, incomplete-day and overtaken
  sweeps marked it sent and never tried again -- a short FCM outage cost
  a day's reminders with nothing in any log. Now, when no message
  reached FCM and at least one failed for a reason that may pass, it is
  `transient push.not_delivered`: those sweeps already skip marking on an
  error, so the next tick tries again (the daily reminder, sent in one
  call, retries as a whole). One device reached is still `Ok` (the other
  is kept); every device gone is still `Ok` with them all retired; a
  403 SENDER_ID_MISMATCH (a token of another Firebase project) is now
  retired instead of retried. Still open from M-28: the quiet-hours queue
  stays at-most-once by design (0064), and the server has no graceful
  shutdown. No migration, no client change.

- **Batch 124 (release guards, 2026-10-13, audit M-38 and M-37)**: two
  gaps in the release path, CI only. (1) `build-verification.yml` falls
  back to a placeholder API (`https://api.nukhba.example`) so a pull
  request compiles; nothing stopped `publish_latest_apk` from releasing
  such a build as the latest APK, and an app pointing nowhere never sees
  the fix (its update check uses that API). The job now starts with the
  same "Require API base URL" guard Deploy Web has. (2)
  `release-server.yml` took "no migration-drift run for this commit" as
  a pass, so a push that did not touch `supabase/migrations` could move
  `server-release` to a server needing a migration the live database
  lacked. It now compares the commit's migrations with
  `ops.applied_migrations` itself before moving the branch (read-only,
  the same SELECT, the `SUPABASE_DB_URL` secret migration-drift uses);
  a missing migration leaves the server where it was, and after applying
  it the owner runs Release Server by hand. No Dart, no migration, no APK.

- **Batch 125 (hidden fixtures off every board, 2026-10-13, audit M-23)**:
  decided 2026-10-13: hiding a fixture (0098) cancels it for as long as it
  stays hidden -- its points leave every board, and showing it again
  brings them back unchanged (nothing is deleted). Until now it was out of
  the head-to-head rounds, the streak and the daily challenge but still in
  the monthly, weekly and season boards and the crown, so a board could
  be decided by a fixture nobody could see. Migration 0107 redefines
  `leaderboard.season_fixture_standings` (same columns) without hidden or
  test fixtures -- it feeds the season tab, a group's season board, the
  personal record and the daily rank snapshot. The readers that do not go
  through it apply the same filter: `PostgresFixtureTotalsReader` (monthly
  board, group month board, live standing, the crown's totals),
  `PostgresSportingSeasonStandingsReader`, `PostgresWeeklyLeague
  StandingsReader` (with the streak bonus of a hidden fixture), and
  `PostgresDuelRecordReader`; the crown's "unscored fixtures" count no
  longer waits for a hidden fixture's result. SQL test
  `supabase/tests/0107_hidden_fixtures_off_boards_test.sql`; the copy in
  `duel_wins_query_test.sql` follows the adapter. NOTE: apply 0107 in the
  SQL Editor before pushing. No APK.
- **Batch 126 (accepting a duel never changes the double, 2026-10-13,
  audit M-12)**: the accept sheet sent the score and double it showed, and
  it showed 0-0 without a double until the caller's saved predictions had
  loaded -- a sheet opened offline or straight from a code could overwrite
  the saved score and clear the day's double. Server: `SubmitFixturePrediction`
  takes `keepStoredDouble`; with it `isDouble` is ignored, an amend keeps
  the saved prediction's double, a first prediction is never a double, and
  the daily-double count is not consulted. `AcceptDuelChallenge` always
  passes it and no longer takes `isDouble`; the route ignores the
  `is_double` older apps still send. App: the sheet's steppers and accept
  button stay disabled until the saved predictions load, a failed load says
  so with a retry, and a line says the score sent becomes the caller's
  prediction. Needs an APK for the app half; the server half protects
  every installed app once released.
- **Batch 127 (the rules say only the exact score scores, 2026-10-13,
  audit M-07 and L-58)**: the ruleset is exact score 3, right outcome 0,
  wrong 0, the double x2 (`ConfiguredRulesetProvider` v3), but the rules
  said "التوقع الصحيح: 3 نقاط", which players read as "I called the winner",
  and the history badge showed "اتجاه صحيح · 0 نقطة". Texts only, no scoring
  change: `rulesCorrectPrediction` names the exact score with an example,
  `rulesWrongPrediction` says any other prediction is 0 even with the right
  outcome, `rulesDoubleMatch` says the double doubles the exact score's 3
  into 6, `historyGradeExact` / `historyGradeOutcome` read "أصبت النتيجة" /
  "أصبت الاتجاه لا النتيجة". `RulesScreen` adds the three rules it left
  out: one double per Riyadh day (`DailyDoublePolicy`), the prediction
  locks at kickoff (`FixtureLock`), and each month starts from zero while
  the sporting season (September-August) adds its months up. The sign-in
  rules card reads the same keys. L-58: the protocol no longer restores the
  whole `lib/l10n/` folder (it holds the ARB sources); a text batch
  regenerates with `flutter gen-l10n` and stages the ARB files with the
  generated ones. Needs an APK.
- **Batch 128 (the admin area is named "إدارة النخبة", 2026-10-14)**: the
  owner renamed the account tab's entry to the admin area from "لوحة تحكم
  المشرف" to "إدارة النخبة" (`adminDashboard`; English "Nukhba admin"). It is the
  only place that name appears: inside the area the app bar shows the
  open section ("الرئيسية", ...), unchanged. Text only; needs an APK.
- **Batch 129 (every player gets a place of his own, 2026-10-14)**: three
  players on 45 points all showed tenth -- the month board shared a place
  among players level on points, invitation points and exact scorelines.
  Decided: two more tie-breaks follow, the right outcomes with the wrong
  score (`correct_outcome`), then the earlier join of the contest
  (`competition.participants.joined_at`; for the sporting season the first
  join of any of its months). Players share a place only when level on all
  five, which real players never are. `FixtureLeaderboard` (month, day,
  group month board, crown, "ترتيبك الآن") and `SportingSeasonLeaderboard`
  order this way; `PostgresFixtureTotalsReader` and
  `PostgresSportingSeasonStandingsReader` read `outcome_count` and the
  join time. Migration 0108 adds `outcome_count` to
  `leaderboard.season_fixture_standings`, ranks the daily snapshot by the
  same five keys, and re-orders each season's latest snapshot among players
  level on its points, so no arrow points down the day it ships. The rules
  page states the whole chain. Not changed: the round-era
  `SeasonLeaderboard` (the match card's season board and a group's season
  board), still points then join time. NOTE: apply 0108 in the SQL Editor
  before pushing; the rules text needs an APK, the places change with the
  server.
- **Batch 130 (invitations and group codes, 2026-10-14, audit M-13, M-08,
  M-22)**: M-13 -- an invitation link opened the web app, where an
  invitation never counts (0086: the app only). `inviteLinkFor` now opens
  the site's landing page (`https://<host>/?ref=CODE`, the host serving the
  web app under `/nukhbaa/`; GitHub Pages keeps the web link, it has no
  landing page of ours). The landing page shows the code with a copy
  button, says to paste it into the Android app at sign-up within 24
  hours, and passes `?ref=` on to the web app. The rules on the invitation
  page read the month's cap from `summary.monthCap` and say where an
  invitation counts. The owner's 0086 rule stands: an iPhone user plays on
  the web but his invitation does not count. M-08 -- a group code typed in
  lower case or with a space joins (`JoinGroupByInvite` trims and
  upper-cases; the field starts in capitals), and `group.invite_code_*` /
  `group.invite_invalid` read as Arabic sentences. M-22 -- migration 0109:
  `gamification.normalized_email` folds an address (lower case, '+' tag
  dropped, Gmail dots dropped), and `claim_referral` refuses
  `duplicate_account` when another account has the same folded mailbox;
  `ReferralClaimOutcome.duplicateAccount`, with the reason shown in the app.
  The crown stays the admin's choice. NOTE: apply 0109 in the SQL Editor
  before pushing; the app texts need an APK, the landing page ships with
  Deploy Web.
- **Batch 131 (what sign-in tells a player, 2026-10-14, audit M-17, M-01,
  M-09, M-02, L-01, L-10)**: M-17 -- `SupabaseAuthClient` keeps the code
  `auth.rejected` (callers branch on it) but turns GoTrue's refusal into an
  Arabic sentence by its `error_code` or, for older versions, its message:
  wrong email or password, email not confirmed, email taken, weak password,
  same password, bad address, sign-ups off, banned. An unknown refusal keeps
  GoTrue's message. The app shows an Arabic server message as it is, so
  every installed app reads them once the server ships. M-01 -- register
  and login answer `auth.confirmation_required` in Arabic; the app draws it
  as news (success colours, key `signIn.infoBanner`), moves the form to
  signing in and keeps the email. M-09 -- `ErrorPresenter` says "session
  over" only for a refused credential (the transport's own rule: `auth.*`
  but `auth.insufficient_role`, `identity.user_id_*`, no envelope); a
  refused action reads "لا تملك صلاحية هذا الإجراء"; `request.rate_limited`
  and `auth.rate_limited` say to wait. M-02 -- `isPasswordResetUrl` needs
  `type=recovery` beside `access_token`, so a sign-up confirmation link
  opens the app. L-10 -- after a web reset the address bar returns to the
  app's page (`/nukhbaa/`), not the landing page at the root
  (`core/platform/reset_url.dart`, pure and tested). L-01 -- a new password
  needs 8 characters on registration as on the reset screen; signing in
  accepts any, for older passwords. No migration; the server half ships
  with the server, the app half needs an APK.
- **Batch 132 (sign-in safety, 2026-10-14, audit M-16, M-03, L-02)**:
  M-16 -- the sign-in, sign-up and reset-e-mail limits were counted per
  e-mail alone, so anyone who knew a rival's address could lock him out of
  signing in and out of a reset by failing on purpose. `limitAuthAttempt`
  now counts per e-mail AND network address (`clientAddress`), with a
  wider allowance per address (sign-in 100, sign-up 30 / 10 min, reset 30
  / 15 min) for one caller trying many accounts; a successful sign-in
  forgets its failures (`forgiveAuthAttempts`, `RateLimiter.reset`). The
  reset code stays per e-mail, so it cannot be guessed from many networks.
  M-03 -- the defaults no longer point at github.io, blocked in Yemen: the
  reset redirect is `https://nukhbaa.app/nukhbaa/reset-password` and the
  invitation web base `https://nukhbaa.app/nukhbaa/` (so the link is the
  landing page, batch 130). L-02 -- `main` creates one `SecureTokenStore`
  and gives it to the error reporter and, through `SessionScope`'s root
  overrides, to every session; a second store had cached the first token
  it read. Protocol: the owner approved (2026-10-14) a runner that runs
  several batch scripts in order and commits each one locally once its
  checks pass; pushing stays his. No migration; the server half ships
  with the server, the app half needs an APK.
- **Batch 133 (streak rungs once, results audited, 2026-10-14, audit M-24,
  M-25)**: M-24 -- a participant is one month and a run crosses months, so
  a run carried into a new month was paid all its rungs again on its first
  completed day there (5+10+20 in one weekly-league week). `AwardStreakBonus`
  now pays a rung only when the run reached it on a match day of the same
  month as the day being paid (`matchDay`, the completed fixture's Riyadh
  day from `SubmitFixturePrediction`); the month before paid it or missed it
  for good. `GetMyStreak.currentRun` gives the run's days, newest first, by
  the same rule as the count. M-25 -- `RecordFixtureResult` writes
  `fixture_result_recorded` to `admin.audit_log` with the admin and the
  score (`2-1`, or `1-1 -> 2-1` for a correction); the provider sync (the
  service principal, not a user) is not audited. Still not audited:
  referral switch, champion photo, season and competition creation, H2H
  pilot start (they need new enum values). L-25 and L-27 are left for a
  later batch. No migration; server only.
- **Batch 134 (one ranking everywhere, 2026-10-14)**: the month board
  ranks by points, invitation points, exact calls, right outcomes, then the
  earlier join (batch 129), but the same month read from the match card
  ("نقاط الموسم", `SeasonLeaderboard`), a group's season board and the
  personal record still shared places on points alone. `SeasonLeaderboard`
  now orders by the same five keys and shares a place only when level on
  all of them; `LeaderboardEntry` carries `referralPoints` and
  `outcomeCount`; `PostgresLeaderboardRepository` (season board, and the
  personal record's `rank()`) and `PostgresGroupRepository` (group season
  board, which now also reads exact and decided counts) read them;
  `season_and_group_standings_queries_test.sql` follows the adapters. The
  points badge on the season fixtures screen (and the unused predict sheet)
  follows the points: a right outcome's 0 is no longer green. L-16: "نقاطي"
  showed the gap to the leader twice; the second tile now counts the exact
  calls ("أصبت النتيجة"). Left for later: L-30 (the live "if it ended now"
  place counts other seasons' and suspended players' gains) and L-35 (the
  insights call a right outcome "صحيحة"). No migration; the boards change
  with the server, the screens need an APK.
- **Batch 135 (sign-out unbinds the phone, the account shows its e-mail,
  2026-10-14, audit M-05 part, L-19)**: M-05 -- signing out left the
  phone's push token bound to the player, so a shared phone kept receiving
  his pushes (duels by name, "so-and-so passed you"). Sign-out now asks the
  server, while the session still holds, to unbind this device:
  `POST /me/device-token/remove` (`RegisterDeviceToken.unregister`,
  `DeviceTokenRepository.remove`, which deletes only the caller's own row);
  `PushTokenService` remembers the token it registered (else asks Firebase),
  bounded and best effort. Not done: revoking the refresh token in Supabase
  (the fingerprint sign-in keeps it on purpose after a sign-out) and
  deleting an account (waits for the owner's choice between anonymising
  and deleting). L-19 -- the account screen shows the account's e-mail in
  every build; id, role and status stay debug-only. No migration; the
  server half ships with the server, the app half needs an APK.

- **Batch 136 (the remediation plan in the repo, 2026-10-14)**: the plan
  for the 2026-10-13 audit lived only outside the repo, so a second Claude
  account could not see it. `docs/remediation-plan.md` now holds every
  finding (103 ids) with its status, owner and batch, the split between
  account (a) (batches 136-199, migrations 0110-0149) and account (b)
  (batches 201-299, migrations 0150-0169), the shared rules (read the
  latest main, touch only your own findings, one script at a time, each
  batch updates its rows), the owner's open decisions (M-05 deletion,
  M-21, L-24, L-59) and the manual items. The audit report itself stays
  out of the repo (public repo, open security findings); the owner
  attaches it. `docs/next-task.md` points to the plan. Docs only.

- **Batch 137 (the audit's verification notes, 2026-10-14, audit C-03, M-37,
  C-02)**: the re-check of the audit at 62f9bc2 (report section 0.3) found
  three things the plan did not hold. C-03 -- a kickoff brought forward
  that the fixtures sync saw only after the STORED kickoff passed was
  dropped without a word, so predictions sent while the match was played
  kept their points. An earlier kickoff never re-opens the lock, so it is
  now followed at any time: `FollowProviderKickoff` (the kickoff logic,
  moved out of `SyncProviderFixtures`) moves it (teams on file, same
  monthly contest) and, when the fixture already has a result,
  `RescoreEarlierKickoff` scores and posts it again through the rescore
  sweep's `FixtureRescorer` (`ScoreFixture` gives the late predictions 0,
  the ledger gets a correction, nobody is pushed twice). A kickoff put back
  after the stored one passed still moves nothing. `SyncProviderResults`
  asks the same follower just before it records a result, the last time
  the provider's kickoff is seen: a change announced too late for the
  12-hourly fixtures sync is caught there. The admin's correction
  (`CorrectFixtureSchedule`) also takes an earlier kickoff after the
  stored one passed and rescores (`competition.rescore_failed` if that
  fails; the move stands); a later one is still
  `competition.kickoff_frozen`. Every case left for an admin (teams not on
  file, put back after the stored kickoff, another month, a failed move or
  rescore, a postponed or cancelled match) is a `ProviderSyncAttention` in
  the report, and the scheduler files each in the error log
  (`reportNeedsAdmin`: critical, one entry per match and kind), so the
  admins get a push the first time and «يحتاج تدخلك» counts it; shadow
  runs only print. M-37 -- `publish_latest_apk` and Deploy Web run Release
  Server's migration check (batch 124) before publishing; a missing
  migration fails the job (apply it, then re-run the failed jobs). C-02 --
  `/auth/refresh` (100 per network address in 10 min) and `/auth/google`
  (30) are counted per address (`limitAuthCall`), and the reset code also
  per address (30 in 15 min), since each spends the server's one GoTrue
  quota; a 429 is transient in the app, so it never signs anyone out. IP
  forwarding stays the owner's Supabase setting. The plan gains batch 137,
  account (a)'s later batches move up by one (groups 138, decisions 147),
  and the C-01 performance note (`f.season_id` in batch 120's two joins)
  joins account (b)'s batch 201. No migration, no APK.

- **Batch 138 (one match is added once, 2026-10-14)**: the Europa League
  evening of 2026-10-15 showed twice. The fixtures sync added its ten
  matches at 01:03 (Riyadh, 10-14) and an admin added the same ten by hand
  between 01:07 and 01:13, with the same catalog teams: `POST /fixtures`
  (`RegisterFixtureSchedule`) never looked at what was already on the
  schedule. (The other order was already safe: the sync adopts a
  hand-added card of the same two teams, batch 119.) An admin's new fixture
  is now refused (409 `competition.fixture_duplicate`, an Arabic message
  naming the stored match and its Riyadh kickoff, shown as it is by the
  admin form) when a visible, non-test fixture of the same two sides kicks
  off within 12 h -- the same team, the same normalised name, or a
  hand-typed side inside the other, never two different teams on file by a
  name inside another (C-04) (`SameMatchFinder`, `PostgresSameMatchFinder`,
  `same_match_query_test.sql`). A test fixture is never checked, and a
  hidden copy is not in the way. The copies made before this batch stay as
  they are (the owner hid one of each pair). No migration; server only, no
  APK.

- **Batch 139 (the schedule itself holds one copy of a match, 2026-10-14)**:
  batch 138 stops an admin's second copy at the server; the owner asked
  that no path, for any role or competition, can ever put one match on the
  schedule twice. Migration 0110 adds `competition.team_name_key` (hamza
  forms, alif maqsura, taa marbuta, case and spaces folded) and a trigger
  on `competition.fixture_schedules` that refuses (23505
  `fixture_schedules_one_match`) any insert or update leaving a visible,
  non-test fixture beside another visible, non-test fixture of the same two
  sides -- either order, the same catalog team or the same name key, never
  a name inside another (C-04) -- less than 12 h apart: the sync with a
  second provider id, a correction moving a fixture onto another, a hidden
  copy shown again, a hand-run insert. Two writers of one pair are
  serialised by an advisory lock. Hiding, and updates that change no team,
  kickoff or visibility, always pass; rows already there are not checked.
  The schedule adapter maps the refusal to `competition.fixture_duplicate`
  (Arabic). `PostgresSameMatchFinder` now uses the same name key and also
  matches home and away swapped. Two SQL tests that place two copies on
  purpose turn the trigger off inside their rolled-back transaction.
  Migration 0110 (apply in the SQL Editor before pushing); server only, no
  APK.

- **Batch 140 (friends' leagues: leave, remove, delete, a limit, 2026-10-14,
  audit M-26 server, L-40, L-45)**: M-26 -- a league's roster could only
  grow: no leaving, no removal, no deletion, no limit, so strangers who
  came in by a link posted in a public chat stayed on its board, feed and
  pushes for good. `LeaveGroup` (`DELETE /groups/{id}/members/me`; the owner
  cannot leave, `group.owner_cannot_leave`), `RemoveGroupMember` (owner
  only, `DELETE /groups/{id}/members/{userId}`) and `DeleteGroup` (owner
  only, `DELETE /groups/{id}`; memberships, invitations, reactions and the
  league's notifications follow by cascade, nobody's points move) over a
  new `GroupRosterStore` port that `PostgresGroupRepository` implements;
  the leaver's invitation row goes with him, so he can be invited again.
  Ownership does not move: the owner deletes. `JoinGroupByInvite` refuses a
  51st member (`group.full`, in Arabic so the app shows it as it is);
  migration 0111's trigger `group_memberships_capacity` is the backstop.
  L-40 -- `GetGroupMonthBoard` read each member's participant one query at
  a time; `GroupRosterStore.memberParticipantIds` reads them in one (the old
  path stays for a root without the store). L-45 -- two players placed into
  one tier at once could both take a group's last seat; the placement
  transaction first takes an advisory lock on the week and tier, and 0111's
  trigger `weekly_league_members_capacity` refuses a seat over capacity
  (a player already seated this week is left to the unique constraint).
  The plan's later batches of account (a) move by three (138 and 139 were
  the duplicate-match batches; groups are split into 140 server and 141
  app). Migration 0111 (apply in the SQL Editor before pushing); server
  only, the buttons come with batch 141's APK.

- **Batch 141 (friends' leagues in the app, 2026-10-14, audit M-11, M-26
  app, L-03)**: M-26 -- a new `GroupMembersScreen` lists a league's
  members by name (the roster now carries `display_name`:
  `GroupRosterStore.memberDisplayNames`, `ListGroupMembers.withNames`,
  optional on `GroupMembershipDto`, so older apps read it unchanged); the
  owner removes a member and deletes the league, a member leaves, each
  after a confirmation, through `GroupsApi.removeMember` / `deleteGroup` /
  `leaveGroup`. Batch 140's DELETE routes answered `204` with no body,
  which the app's DELETE reads as a malformed answer; they now answer
  `200` with `{"left"|"removed"|"deleted": true}`. M-11 -- the league
  already lived in the leaderboard's friends tab; its header gains a
  members button, My Groups a members button per league, the creation
  screen a "share the invitation link" button (the invitation sheet), and
  a join closes with "انضممت إلى «X»" instead of in silence. L-03 -- the
  group feed shows the time in the viewer's zone (`formatTimestamp`)
  instead of the raw ISO string and drops `round_scored`, which only
  repeated the round model's old rounds; the invitation sheet's search by
  name says when it found nobody or failed. No migration; the roster
  names and the JSON answers ship with the server, the screens need an
  APK.
- **Batch 142 (abuse: the error log and player-to-player pushes,
  2026-10-15, audit M-19, M-20 part)**: M-19 -- `POST /errors/report` is
  open before sign-in, so a script could invent an error or a build per
  request and ring every admin's phone. `RecordError` now lets only the
  server's own errors and reports with a valid token alert (an anonymous
  report is still kept); migration 0112 replaces `ops.claim_error_alert`
  with the same rules plus a budget -- once six errors alerted within the
  hour the next is kept without an alert, except a new critical error,
  which only the server records -- and a partial index on
  `last_alert_at`; one network address with nobody signed in sends 120
  reports an hour (`anonymousErrorReportAddressLimiter`, on top of 600).
  M-20 -- the invitation push title no longer carries the league's name
  (`InviteToGroup.pushTitle`, the same for every league; the name stays
  in the inbox), and what reaches another player's phone is counted per
  player over 24 hours, only when it succeeded (`PlayerReach`,
  `RateLimiter.blockedFor`): 5 new leagues, 30 invitations, 3 private
  challenges to the same player; a refusal is `409 social.daily_limit`
  with an Arabic sentence the app shows as it is. In-process like every
  limit here, so a restart forgets the counts. Left for batch 151: the
  two mute switches (league invitations, challenges) and a block list.
  NOTE: apply 0112 in the SQL Editor before pushing. No APK.
- **Batch 143 (notifications, the server side, 2026-10-15, audit M-14
  server, M-32, L-27, M-28 rest)**: M-14 -- `POST /admin/announcements`
  takes an optional `request_id` (a UUID the app makes once per message)
  that becomes the announcement id; the save is `ON CONFLICT (id) DO
  NOTHING`, so "send" pressed again after a timeout, even while the first
  publish still runs, reaches no inbox and no phone twice and answers the
  inboxes it added. M-32 -- `FcmPushSender` sends `parallelMessages` (10)
  at a time instead of one after the other, the dead list still in token
  order; `NotifyFixtureWinners` makes one send per message (an exact hit,
  a doubled one) with all the winners' devices and one queue call for the
  quiet ones, instead of a send per winner inside the request that scored
  the fixture. L-27 -- before announcing, `withdrawExactNotices` deletes
  the fixture's `fixture_scored` notification of every user who is no
  longer an exact caller (all of them when none is left); the SQL test
  `score_notice_withdraw_query_test.sql` copies the adapter's statement.
  M-28 -- on SIGTERM the server stops taking connections, starts no sweep
  (`singleFlight` now knows the running ones, `drainSweeps`), lets the
  requests and sweeps in progress finish for 20 seconds at most, closes
  the pool and exits. The app's half of M-14 (a confirmation with the
  count, sending `request_id`, the button held until the answer) and L-04,
  L-05, L-50 are batch 152. No migration, no APK.
- **Batch 152 (notifications, the app side, 2026-10-15, audit M-14 app,
  L-04, L-05, L-50)**: M-14 -- the announcement screen asks before it
  sends, showing the message as it will arrive and that it cannot be taken
  back; each message gets a version-4 UUID (`newAnnouncementRequestId`)
  sent as `request_id` (`PublishAnnouncementRequestDto.requestId`,
  `AdminApi.publishAnnouncement`) and kept through every retry of the same
  text, new for the next message; the result reads "أُرسل الإشعار إلى 3
  مستخدمين" (`arabicCount`), or that it had arrived before when a replay
  added nobody. The count before sending is not shown: no route counts
  the audience. L-04 -- in the inbox a scored match opens the history and
  a new member My Groups (`fixture_scored`, `group_member_joined`); an
  announcement still reads in place. L-05 -- "later" on the web push card
  is kept per browser (`WebPushLaterStore`, secure storage) and hides the
  card for a week. L-50 -- the prediction reminder's description also
  names the reminder before a match not yet predicted on a day already
  started, which the same switch controls. Needs an APK (and the web
  deploy); no migration.
- **Batch 144 (the crests, 2026-10-15, audit M-34, L-09)**: the 339
  bundled crests were 500 to 800 pixels (8.9 MB in every APK, each
  downloaded whole on the web) for a crest drawn at most 34 logical
  pixels; each is now at most 128 pixels, a 256-colour PNG with its
  transparency (1.2 MB in all; the smaller of palette and full colour,
  and the original when it was already smaller). The patch replaces a
  crest only while it is still the file this batch was made from, and
  stops otherwise. `team_logo_weight_test.dart` refuses any crest above
  160 pixels or 40 KB from now on. L-09 -- Al Ahly of Egypt (the Cairo
  derby showed Zamalek's crest beside initials) and 16 Asian national
  flags were bundled but missing from `_monthlyLogoSlugs`; they are
  shown now. Needs an APK (and the web deploy); no migration. M-35 and
  L-53 (avatars kept on the phone, medals without the emoji font) are
  batch 153.
- **Batch 153 (profile pictures kept on the phone, 2026-10-15, audit
  M-35)**: the server answers a picture `immutable` for a year under a
  `?v=` URL, but the app reads the bytes through `api_client`, which has
  no disk cache, and held them two minutes in memory: every board, group
  and duel opened later, and every launch, downloaded every face again.
  `avatarBytesProvider` now reads `AvatarDiskCache` first and keeps what
  it downloads: on Android a file per URL (base64url of the whole URL) in
  `nukhba_avatars` under the app's temporary folder, trimmed oldest first
  from 20 MB to 15 MB; on the web nothing (the browser's cache already
  honours the header; conditional import `avatar_disk_cache_io.dart` /
  `_stub.dart`); under `flutter test` nothing, so every test starts empty.
  A replaced picture is a new URL, so an old face never returns. Every
  read and write is best effort. `UserAvatar` decodes at its drawn size
  on native (`cacheWidth`), as the crests do. L-53 moves to batch 154:
  `RankBadge`, the medal widget, is not used anywhere; the emoji left are
  the marks beside the points. Needs an APK; no migration.
- **Batch 154 (verdict marks the web can draw, 2026-10-15, audit L-53)**:
  CanvasKit has no emoji font and fetches one from fonts.gstatic.com,
  which some networks block, so ✅ ❌ 🔥 ⚡ beside the points could be empty
  boxes on the web. `EmojiMark` (core/ui) draws each known mark as a
  Material icon on the web (check, cancel, flame, bolt; success, error
  and gold) and keeps the text on native, under the key the tests read
  (`textKey`). Used by the predictions board, the match screen's badge,
  the history's final line and the shared exact-hit picture (those two
  split mark and points into a row on the web only). "أنت في الصدارة 🥇"
  is still a sentence in the ARB files. Needs an APK and the web deploy;
  no migration.
- **Batch 145 (the screens say what happened, 2026-10-15, audit M-06,
  M-10, L-06, L-07, L-08, L-17, L-18, L-52)**: the home overview shows the
  error and a retry when the month's matches cannot be read and there is
  no older list (it said "updating your matches..." for ever), and drops
  the season count rather than "..." when that read fails. Only the
  head-to-head league is "المواجهات": the friends' duels are "التحديات"
  everywhere (the account row, the page, the code, "فاز في 5 تحديات"; the
  server already said تحدٍّ), and the league's fourth section is
  "المجموعة", short enough for a quarter of a phone. The favourite-team
  bar puts the two teams under the question in a Wrap. The H2H round
  detail and the insights' best call show Arabic team names. The team
  registry no longer matches by substring: the name, then a normalized
  form (case, hyphens, "&", FC/SFC/AFC/Saudi at either end) and a short
  alias list, so "Al Hilal Omdurman" is not Al Hilal. Every list error
  offers a retry, not only a dropped connection. The three picture shares
  go through `sharePicture` (core/ui), which reports a failure, and the
  dialog says "تعذّرت المشاركة. حاول مرة أخرى.". The duel score buttons
  carry tooltips with the team. Needs an APK and the web deploy; no
  migration.
- **Batch 147 (one supported version, 2026-10-15, audit L-15, L-20,
  L-54, L-62; migration 0113)**: 19 Android builds were in use at once and
  fixes already shipped kept arriving from old phones, because the app
  only offered an update as a quiet row on the account tab. Each release
  is now numbered: the CI run number goes into the APK
  (`NUKHBA_BUILD_NUMBER`, with `NUKHBA_BUILT_AT`) and into the release
  name, `Build <sha> #<number>`, which `GithubBuildInfoRepository` reads
  back. `ops.app_update_policy` (0113, one row) holds the oldest build
  still supported; `GET /app/latest-build` carries `build_number` and
  `min_supported_build`, and `PUT /admin/app/min-build {"to_latest"}`
  (admin, `SetMinSupportedBuild`) makes the newest release the minimum or
  clears it, never a typed number. An app older than the minimum shows
  `RequiredUpdateScreen` ("حدِّث نُخبة لتكمل") with the in-app install
  instead of itself; a local run (number 0) is never held. An Android
  build more than 7 days old with a release waiting raises a home card,
  closable for the run. The web build reloads by itself only at launch;
  a return to a page left open raises the same card (L-62). The admin's
  card sits under the announcement form ("إصدار التطبيق"), so the
  announcement reaches the builds older than this batch, which do not
  know the minimum. The progress dialog's watchdog cancels a download
  that went quiet, and the plugin's raw message waits behind "التفاصيل"
  (L-15). The landing page's manifest installs `/nukhbaa/` (L-20); the
  mirror keeps `assets/assets/` pictures a week (L-54). Releases still go
  out on every green push. Apply 0113 before pushing; needs an APK and the
  web deploy. M-04's offline content moved to batch 155.

- **Batch 156 (the server's connections, 2026-10-16, outside the audit
  plan)**: at 00:46-00:51 the error log held `db.query_timeout` on the
  scores route (AGMU, now from builds older than script 75 only) and the
  month board ('still waiting for a connection after 10.4s; connections
  in use 8/8, waiting 89'), while `pg_stat_statements` showed no query
  slower than about 0.65 s on average: the server's eight connections,
  not the database. Two clients held them. The admin's "المباريات
  المحتسبة" sent one `GET /admin/fixtures/{id}/scores` per match played
  this month, six at a time, for minutes; it now sends
  `GET /admin/fixture-score-counts?fixtures=` (`AdminCountFixtureScores`,
  port `FixtureScoreCounter`, `PostgresFixtureScoreCounter`: one grouped
  count over `scoring.fixture_scores`, 200 ids at most) once per hundred
  matches, and a failed read fails the section at once instead of
  retrying. The players' builds older than script 75 send one
  `GET /seasons/{id}/fixtures/{id}/scores` per match of their history;
  that route now runs behind a `Bulkhead` of three places
  (`server/http/bulkhead.dart`) and answers `503 server.busy` at once
  beyond them, without an entry in the error log. The predictions board
  read as "no predictions yet" when every column failed; it now says
  why, with a retry (`fixturePredictions.failed`). The pool size comes
  from `NUKHBA_PG_POOL_SIZE` (2..40, default 8, logged at start), so it
  can be raised on Northflank without a release once Supabase's own
  connection count says there is room. No migration; the server and the
  APK and the web.
- **Batch 146b (the admin panel, second part, 2026-10-16, audit L-12,
  the admin part of C-01, part of L-14)**: "سجل النقاط" asked for a
  participant id typed by hand and read `ledger.point_entries`, the
  round ledger, empty since fixtures replaced rounds: every current
  player showed nothing. It now picks a month and a player by name and
  reads `GET /admin/users/{id}/points?season=` (`AdminViewPlayerPoints`,
  port `PlayerPointsReader`, `PostgresPlayerPointsReader`: one read of
  the player's participation, `ledger.fixture_point_entries` and each
  match's sides; `PlayerMonthPointsDto`): every movement with its match
  and its kind in words, the month's points as the board counts them
  (match scores and corrections) and the streak bonuses apart (the
  weekly league only, migration 0072). The read is audited as
  `participant_ledger_viewed` before it is served, as before. The old
  `GET /admin/participants/{id}/ledger` stays, unused by the app, for
  the cleanup batch. Adding a match (L-12): the kickoff is entered and
  shown on Riyadh's clock in both the add and the edit forms
  (`core/time/riyadh_clock.dart`, `RiyadhKickoffField`), with the
  phone's own time under it when its zone differs; the form empties
  after a match is added (month and league kept), so a second tap
  cannot add it twice; and when the link to the month fails after the
  registration, `AddMatchController.unlinked` keeps the match and the
  same submit links it rather than registering a second copy, which
  migration 0110 would refuse, leaving an orphan no month shows. A
  single server transaction was weighed and left: one admin, and the
  gap is the network between two requests. SQL test:
  `player_points_query_test`. No migration.
- **Batch 150 (the owner's decisions, first part, 2026-10-16, audit M-21,
  L-24, L-59, the M-05 decision; migration 0114)**: an invitee idle for 7
  days was suspended along with the inviter's point being taken back, so a
  real friend who travelled, or found no matches in an international break,
  opened the app to "this account is suspended". `expire_idle_referrals`
  now only takes the point back (`referral_revoked`, `inactive_7_days`),
  which is all that stops a fake invitation paying; 0114 also reinstates,
  once, every plain account the sweep had suspended and no admin had
  (no `user_suspended` row in `admin.audit_log` names it). The owner's
  decisions: the admin keeps seeing predictions before kickoff, every read
  audited as before (L-24); the Android `applicationId` stays, since a new
  one cannot update the installed app (L-59); deleting an account will
  anonymise it and keep its points and predictions in the record, the
  ledger being append-only behind `on delete restrict` keys (M-05, to be
  built in 150b with L-23). SQL tests: `0114_idle_invitee_not_suspended_test`
  and `0075_referral_idle_test` (now expecting the account active).
- **Batch 146 (the admin panel, first part, 2026-10-16, audit L-11,
  L-13, L-47, part of L-14)**: the commands that change players' points
  now ask first, by the match's name: النتائج والاحتساب confirms
  recording a result ("Arsenal × Chelsea: 2-1"), scoring and posting
  (`admin.results.confirm`), and says "سُجّلت النتيجة: Arsenal × Chelsea
  2-1" where it showed the match's id. Hiding one match from its row
  asks as a selection does (showing back stays immediate); suspending a
  player asks by his name and the reason (`admin.users.suspendConfirm`),
  and "اكتب السبب أولاً" shows by the suspend buttons
  (`admin.users.sanctionMessage`), not under the rename button.
  `ErrorPresenter.asAppError` and `messageOf` replace the 21 casts
  `error as AppError` in the admin sections and the group screens: any
  other failure reads as a message instead of a red screen. The audit
  actions read from one map (`features/admin/audit_action_labels.dart`)
  on the home and in the log ("تعليق لاعب" both), the log keeping an
  unknown token in brackets. `POST /fixtures` and `PUT /fixtures/{id}`
  read the optional team and league ids with `optionalString`: a number
  there is a 400 `request.field_type`, not a 500. Left for 146b: L-12,
  L-34, the rest of L-14 with C-01 (the points lookup by player, on the
  fixture ledger) and M-25. No migration.
- **Batch 157 (the update check after a release, 2026-10-16, outside the
  audit plan):** right after batch 156 went live, Y7GU came back: "no
  verifiable APK in the latest published release", 69 times in minutes,
  so no account screen offered the new build, while release
  `build-9ef32b3` (#723) did carry its four APKs and `checksums.json`.
  The server read the checksums by downloading `checksums.json` from
  github.com, and a failed answer was never kept: every app open after
  the redeploy asked GitHub again (the release, the list of five, a
  download each), against an hourly limit shared by the host's address.
  `GithubBuildInfoRepository` now takes an APK's SHA-256 from the
  asset's own `digest` (`sha256:` and 64 hex digits, computed by GitHub
  on upload) in the release itself, and downloads `checksums.json` only
  for an APK without one: a good answer is one GitHub call. A failed
  answer is reused for `failureTtl` (two minutes), carries its cause
  ("GitHub HTTP 403", "5 assets, 0 checksums") into the error log, and
  is written to the container log as `[latest-build] ...`. An optional
  `NUKHBA_GITHUB_TOKEN` (any token; the repository is public) is sent to
  the API only, never to a download. And the 503 `server.busy` of batch
  156's bulkhead was being kept in the error log as "HTTP 503" (2S2G):
  the bulkhead now marks the request `RequestScope.shed`, and
  `captureServerErrors` keeps no report for it. No migration; the
  server only.

### The web app loads faster (web speed 71, 2026-10-14)

Outside the audit plan. Measured 2026-10-14 by the Web Speed workflow
(branch `web-speed`: Puppeteer, a fresh profile, Slow 4G and 4x CPU, the
live nukhbaa.app/nukhbaa/): a first visit waited a median 26.7 s for the
app, 19 requests and 3.96 MB, of which CanvasKit (2.09 MB gzip) and
main.dart.js (1.36 MB) were 87%. Every file was `no-cache` (batch 72), so a
returning visitor asked again for each one.

- **Brotli on the mirror, stock nginx:** `deploy/web-mirror/
  finalize_build.mjs compress` writes a quality-11 `.br` copy of
  main.dart, both CanvasKit variants and the fonts (Node's own zlib,
  nothing installed). `nginx.conf` sends it to a browser that accepts br
  (`map` on Accept-Encoding and the path, a rewrite to an internal `\.br$`
  location with the original type and `gzip off`), gzip otherwise. What
  Chrome fetches went from 4.01 MB to 3.01 MB.
- **Names made from content:** `finalize_build.mjs version`, after
  `flutter build web` and before either host, renames `main.dart.js` to
  `main.dart.<sha256:12>.js` (the build config's `mainJsPath`) and
  `canvaskit/` to `canvaskit-<engine revision:12>/` (the loader call gets
  `config.canvasKitBaseUrl`). The mirror keeps them a year (`immutable`;
  an unknown name is a 404, never the app page) and the fonts a month;
  index.html and flutter_bootstrap.js stay `no-cache` and bring the new
  names. A build with dart2js deferred parts is refused (they are named
  after main.dart.js).
- **The gate:** the deploy workflow stages web-dist, builds the Dockerfile
  Northflank builds and runs `check_mirror.mjs` against it before GitHub
  Pages or the mirror is published: each compressed file, asked with br,
  with gzip and with neither, decodes to the bytes on disk with its type
  and cache rule; an old content name and a `.br` name asked directly are
  404; a deep link is the app page.
- `ErrorFingerprint` reads `main.dart.<hash>.js` as `main.dart.js`, so a
  web error keeps its identity across builds.
- Measured in the assistant's sandbox on the build of e0f5239 (nginx 1.28
  with the official mime.types, headless Chromium 141, Slow 4G and 4x CPU,
  two runs each): first visit 25.3 s -> 19.7 s; returning visit 7.2 s ->
  5.5 s, with 9 KB over the network. The sign-in screen renders the same.
- Left as they were: the three font weights (600 is used 34 times;
  dropping it saves 86 KB and changes the look), Google Sign-In's script
  (the `google_sign_in_web` plugin loads it when it registers) and Sentry
  (already after `runApp` on the web).

No migration, no APK, no new dependency.

### The quality scorecard (script 72, 2026-10-15)

Requested 2026-10-15: nukhbaa measured against the published standards
every day, with no manual check. The owner chose a daily report in GitHub
Actions first, then an admin screen and the real startup time in the next
APK.

- `.github/workflows/quality-scorecard.yml`, daily at 07:18 Riyadh and by
  hand, reads: the players' data of the last 7 days
  (`supabase/queries/quality_scorecard.sql`, the `SUPABASE_DB_URL` Deploy
  Web's migration check uses, inside a read-only transaction); the last
  completed Build Verification on main; the live web app opened three
  times by a new visitor (`.github/web-speed/measure.mjs`, brought over
  from the `web-speed` branch); `docs/remediation-plan.md`; and the UI
  audit ratchet. `tooling/quality/scorecard.mjs` writes the card to the
  run summary.
- Rows and limits: Build Verification green (ISO/IEC/IEEE 29119); open
  critical or high error groups seen in the week = 0 (ISO/IEC 25010
  reliability); sessions with a frozen frame <= 5% and slow frames <= 10%
  per platform (Android vitals' definitions; Google publishes no share, so
  the percentages are the project's); the web app's first frame <= 2.5 s
  (Core Web Vitals LCP); open critical audit items = 0; UI audit findings
  = 0 (WCAG 2.2 AA, the automated part). Startup time and native Android
  crashes are listed as not measured yet. A platform with fewer than 30
  sessions in the week is not judged.
- The run fails, and GitHub e-mails the owner, only when something got
  worse since the previous run: a passing row now fails, or the web first
  frame is 20% slower. The previous verdicts live in the workflow's cache,
  not in the repository; the repository is public, so the summary shows
  rates and verdicts, never how many players or sessions there were.
- Tests: `tooling/quality/scorecard.test.mjs` (`node --test`, through the
  command line, on the real plan and baseline) runs first in the workflow;
  `supabase/tests/quality_scorecard_query_test.sql` checks the query on
  Postgres 16 in db-tests.

No migration, no APK. Puppeteer, the web-speed check's, now runs from main.

### When a web frame freezes (script 73, 2026-10-15)

The quality scorecard's first card (2026-10-15): 33.7% of web sessions had
a frame over 700 ms, against 2.8% on Android. A frame report said how many
froze, not when.

- Migration 0170: `ops.frame_reports` gains `frozen_at_start` and
  `frozen_at_resume`, a subset of `frozen_frames` each (both or neither,
  together never more; null from older apps). Numbered outside the audit
  plan's ranges; the plan's rule 4 now gives this series 0170-0179.
- `FrameReporter` places each frozen frame: within
  `FrameReporter.openingWindow` (5 s) of the first frame of an opening --
  the app opening, or a return from the background (resumed after paused
  or hidden) -- on the frame's own vsync (`FramePhase.vsyncStart`), so no
  second clock is mixed in; the rest froze while the player used the app.
  `FrameReportDto`, `POST /me/frame-report` (two optional integers),
  `FrameReport`, `RecordFrameReport` (refuses one without the other, a
  negative count, or more than the frozen frames) and
  `PostgresFrameReportRepository` carry the two counts.
- `supabase/queries/quality_scorecard.sql` counts, per platform, the
  sessions that say when, and those that froze at the opening, at a return
  and later; the card adds the split to the frozen row once 30 sessions in
  the week carry it.
- The web build reports it as soon as it is deployed; Android with the
  next APK.

Migration 0170 (apply in the SQL Editor before pushing); no APK for the
web.

### One retry policy for every read (script 74, 2026-10-15)

The error log after the Champions League night of 2026-10-14/15: 389
database timeouts on `GET /seasons/{id}/fixtures/{fixtureId}/scores`
(28 players) and 464 "the server took too long" on phones and the web.
Riverpod 3.3.2's default retry (`ProviderContainer.defaultRetry`: ten
more tries, 0.2 s doubling to 6.4 s, about 38 s, for anything that is not
an `Error` -- `AppError` is not) applied to every provider of the app
but the 11 with a policy of their own, so each request that timed out
came back as up to eleven while the server
was already waiting on its database, and the screen sat in loading the
whole time (`triggerRetry` keeps the state `AsyncLoading` while it
retries).

- `SessionScope` sets `retry: appReadRetry` on the root `ProviderScope`:
  an `ErrorKind.transient` failure (no network, a timeout, a 503) is read
  again twice, after 3 and then 10 seconds (`appReadRetryDelays`);
  anything else -- a refusal, a bad request, a `ProviderException` from a
  provider it reads -- is not retried, and the screen shows it with its own
  retry button. Providers with a policy of their own (the predictions
  board's `predictionsBoardRetry`, the admin reads) keep it.
- Test: `test/core/session/session_scope_retry_test.dart`, through the
  app's own scope: a transient failure runs three times in all, a refusal
  once.
- The UI audit's `shell.matches` (every read answered with a body the app
  cannot read) now measures the matches tab's real error state -- it
  measured the loading skeleton while Riverpod kept retrying -- and caught
  it overflowing by 57 px at x2.0 on a phone. The error now scrolls and
  pulls to refresh like the empty states
  (`current_month_fixtures_screen.dart`; test:
  `feed_refresh_failure_test.dart`, a failed first load pulled down loads
  the list).
- Part (b), next: the caller's own points in one read, so cards and
  history rows stop asking for scores one match at a time.

No migration, no server change; the web takes it on deploy, Android with
the next APK.

### The caller's own points in one read (script 75, 2026-10-15)

Part (b) of the match-night fix. Every finished match card, every row of
"my predictions", the match screen and the prediction sheet asked
`GET /seasons/{id}/fixtures/{fixtureId}/scores` for their own match --
four queries and every participant's score, to show one line -- and asked
again every 2 minutes while the score was pending. When a match ended
every player's app did that at once for each finished card and each
history row: 389 database timeouts on that route on 2026-10-14/15.

- `GET /me/fixture-scores` (`ListMyFixtureScores` over the
  `MyFixtureScoreReader` port, `PostgresMyFixtureScoreReader`) returns the
  caller's own grade, points and final score for every prediction that has
  a score or a recorded result, from one call of
  `scoring.my_fixture_scores(user_id)` (migration 0171; grade and points
  null while the result waits for scoring). Wire shape
  `MyFixtureScoreDto`, keyed by (participant_id, fixture_id). A scoring
  read beside `/me/fixture-predictions`, not fields on it: a prediction's
  wire shape carries no points (the route tests check that `points` is
  absent).
- The app: `myFixtureScoresProvider` (hand-written,
  `features/history/my_fixture_scores_providers.dart`) replaces
  `fixtureScoresProvider` in the match card, the history card, the match
  screen and the sheet. It asks once the month's feed has answered, again
  when the feed shows a new result, and every 2 minutes while a recorded
  result has no grade; it is kept two minutes past its last watcher.
- `GET /seasons/{id}/fixtures/{fixtureId}/scores` stays on the server for
  apps installed before this one.
- Tests: SQL `0171_my_fixture_scores_test.sql`; contracts, application,
  infrastructure, api_client and the route; mobile
  `my_fixture_scores_providers_test.dart` through the real matches screen
  (two finished cards, one read and no per-match request; a waiting grade
  asked again after 2 minutes, then not; a new result in the feed reads
  again, a feed refresh with nothing new does not); the card, history,
  match screen and UI audit tests answer the new read.

Migration 0171 (apply in the SQL Editor before pushing); the server on
push, the web on deploy, Android with the next APK.

### Colour audit, round two: text tokens and theme defaults (script 76, 2026-10-15)

Owner's request: no screen or colour defect in either theme. Report:
`docs/reviews/colour-audit-2026-10-15.md` (CA-01 to CA-09; the plan's batch
145 items stay with account (a)).

- CA-01: 38 texts drawn in a fill token -- `error` 28, `primary` /
  `primaryLight` 4, `success` 5, `goldAccent` 1, in 22 files -- now use the
  text shades (`errorText`, `primaryText`, `successText`, `gold`), which
  reach 4.5:1 on every surface of both themes.
- `app_theme.dart`: the dark `onSecondaryContainer` is `onGold` (tonal
  buttons and selected chips: white on dark gold was 3.25:1, now 5.0:1);
  links and text buttons, the selected tab, a focused field's label, a
  selected list tile, the snack bar's action (white on the light bar,
  1.25:1) and today in the date picker all use `primaryText`; a field's
  label in error and its error line use `errorText`.
- Defences: `test/core/theme/app_theme_components_contrast_test.dart` (every
  text token on every surface, every content colour on its fill, a pumped
  tonal button, the tab, the field label and error line, the list tile, the
  snack bar action, today, the links -- from the real `AppTheme`, both
  themes) and `test/audit/text_color_tokens_test.dart` (reads all of `lib/`
  and fails on a `TextStyle`, `TextSpan` or `copyWith` whose `color:` names
  a fill token; a self-test proves it catches one and passes the right one).
- Next: the screen survey's extension to the 15 screens it does not reach
  (CA-09) moved to script 79, after the button labels (78).

No migration, no server change; the web on deploy, Android with the next
APK.

### Colour audit: the owner's screenshots (script 77, 2026-10-15)

- CA-10: the selected double button's bolt was gold on blue -- 1.06:1 in
  the light theme, 2.79:1 in the dark, under the 3:1 an icon needs; it is
  the label's white now (6.7:1 and 4.5:1). Test:
  `double_button_contrast_test.dart`, through the real matches screen in
  both themes (bolt, label, rim).
- CA-11: icons and rims took the text gold, which reads olive in the light
  theme; the home trophy, the H2H shield and division accent, the champion
  crown and the double button's rim take `goldAccent` (3:1 or better on
  every light surface; the same gold in the dark theme). Test: a medal-gold
  check in `app_theme_components_contrast_test.dart`.

No migration; the web on deploy, Android with the next APK.

### Colour audit: button labels (script 78, 2026-10-15)

- CA-12: `AppButton.danger` -- every destructive confirm through
  `AppDialog.confirm` -- was white on the dark theme's bright `error`
  (3.51:1); it fills with `errorFill` (5.39:1). The home card's white
  "start predicting" button is labelled in `scheme.primaryContainer`
  (6.7:1 dark, 10.4:1 light) instead of `primary` (4.54:1 dark, the edge).
- CA-13: `AdminSecondaryButton` is labelled in `primaryText`.
- Defences: `test/audit/button_label_tokens_test.dart` (reads all of `lib/`
  and fails on a `styleFrom(foregroundColor:)` naming a fill token, with a
  self-test) and `test/core/theme/button_labels_contrast_test.dart` (the
  destructive confirm and the home button, pumped in both themes).
- Next: script 79 extends the screen survey to CA-09; 80 on fix what it
  measures, with CA-08.

No migration; the web on deploy, Android with the next APK.

### Colour audit: the screen survey reaches 19 more screens (script 79, 2026-10-15)

- `test/audit/ui_audit_survey_test.dart` measures, in both themes and at
  text scales 1.0, 1.3 and 2.0, the screens a player opens from the tabs:
  fingerprint sign-in, password reset (e-mail and new password), name
  setup, rules, settings, notification settings, favourite teams, my
  points, my seasons, season record, the elite card, badges, insights,
  invite friends, the champions' record, a season's leaderboard, duels and
  an H2H round. Each through its real providers -- over the real transport
  with the server faked (`_served`), or with the records read given.
- The script measures them on the device, writes their counts into
  `ui_audit_baseline.json` only after checking that no screen already
  there gained a finding, and keeps the findings in
  `docs/reviews/ui-audit-survey-2026-10-15.md`.
- Not reachable from the app, so not measured: `FixturePredictionScreen`
  and `showFixturePredictSheet`, `CompetitionSeasonsScreen`,
  `MyActiveSeasonsScreen`, `LedgerScreen`.
- Next: script 80 adds the groups pages, the players' predictions board
  and the fixtures calendar; 81 on fix what the survey measures, with
  CA-08.

No migration; tests and docs only.

### Colour audit: what the survey measured (script 80, 2026-10-15)

Script 79's run found four defects, each in both themes
(`docs/reviews/ui-audit-survey-2026-10-15.md`); all are fixed and the
baseline is zero on every measured screen, so the survey fails on any new
finding anywhere.

- CA-14: my points -- "through the latest counted match" ran 158 px past
  the card at x2.0; it takes at most two fifths of the width and wraps.
- CA-15: my seasons and the season record -- the trailing total pushed the
  row 8 px past the card at x2.0; it is held to two fifths of the width
  and wraps. The place's ring grows with the text
  (`MediaQuery.textScalerOf(context).scale(42)`) instead of breaking
  "#23" inside a fixed 42 px.
- CA-16: notification settings -- the four switches had no name for a
  screen reader; each row is one `MergeSemantics` node, read with its title
  and hint.
- Next: script 81 adds the groups pages, the players' predictions board
  and the fixtures calendar to the survey; 82 on fix what it measures,
  with CA-08.

No migration; the web on deploy, Android with the next APK.

### Colour audit: the survey reaches the rest of CA-09 (script 81, 2026-10-15)

- `test/audit/ui_audit_survey_test.dart` measures 12 more screens in both
  themes at three text scales: my leagues, create a league, join by code,
  a league's feed, its board and its members, the invite sheet (opened
  from a button, as the league page opens it), the friends' board with a
  league and without one, the players' predictions board on a day of two
  started matches, the fixtures calendar and the inbox with messages.
- As in script 79, the script measures them on the device and writes their
  counts into the baseline only after checking that no screen already
  measured -- all at zero since script 80 -- gained a finding; the
  findings go to `docs/reviews/ui-audit-survey-2026-10-15.md`.
- Next: script 82 on fixes what this run measures, with CA-08.

No migration; tests and docs only.

### Colour audit: the calendar's targets and a tighter day strip (script 82, 2026-10-15)

Script 81's run found one defect on its 12 screens, in both themes: the
calendar's days were 44 x 44 targets (60 of them), under Android's 48.

- CA-17: `fixtures_calendar_page.dart` -- the whole cell (a seventh of the
  row by 52) takes the tap; the drawn day stays a 44 px circle.
- The day strip under the matches app bar, smaller at the owner's request:
  a chip is at least 64 wide instead of 80, with half the gap and half the
  side padding, and the strip is 64 high instead of 70 -- about six days
  on a phone instead of four and a half. The chips still grow with the
  reader's text (`heightFor`, UI-17) and stay 48 px targets or more.
- The survey baseline is zero on all 51 screens.
- Next: script 83, CA-08.

No migration; the web on deploy, Android with the next APK.

### Colour audit: colours that reach text through a variable (script 83, 2026-10-15)

- CA-08: a fill colour named in a `Color` variable or arrow function and
  then drawn as text -- the admin's invitation state (`stateColor`), the
  frame verdict (`verdict`, three places) and the place inside the medal
  ring on my seasons and the season record. The state and the verdict take
  `successText` / `errorText`; the place is `gold` for first,
  `textPrimary` for second and third and `textMuted` after, while the
  ring keeps the medal colour.
- Defence: `test/audit/text_color_variables_test.dart` reads all of `lib/`
  and fails where a `TextStyle`, `TextSpan` or `copyWith` takes its colour
  from a `Color` variable or arrow function whose value names a fill
  token; a self-test proves it follows both and passes an icon.
- `admin_frame_stats_card_test.dart` expects the text shades.

No migration; the web on deploy, Android with the next APK.

### Colour audit: non-text contrast (script 84, 2026-10-15)

Every fill token against every surface, at the 3:1 that icons, control
rims and bars need: all pass in both themes except the dark `primary` on
`surfaceHigh` (2.97:1) and the decorative hairline `border` (by design).

- CA-18: the only place that pairing is drawn is the day's challenge bar
  on its track; it fills with `primaryText` (the text blue, 4.5:1 or
  better on every surface) while on its way, `success` once done.
- Defence: `daily_challenge_bar_contrast_test.dart` draws the real card
  over the real transport in both themes, on its way and done, and holds
  the bar at 3:1 on its track and on its card.

No migration; the web on deploy, Android with the next APK.

### Colour audit: gold on amber, not on a grey wash (script 85, 2026-10-15)

- CA-19: a 14-16% gold wash over the navy came out a neutral grey in the
  dark theme (#353C3B, hue 171) -- the H2H first-division circle, the
  first-place rank badge, every gold `AppBadge` ("pilot month"), the
  board's lead chip and a held badge's circle.
- `AppTokens.goldContainer` (new): an opaque amber taken from the palette's
  own `warningContainer` (#2E2008 dark, #FDF3DE light), the way success and
  error already have their containers; `gold` reads 9.7:1 on it dark,
  5.7:1 light, the medal gold 3.5:1 or better. The five places use it; a
  held badge's icon takes the medal gold instead of the olive text gold.
- Defence: `gold_container_test.dart` -- the token is opaque, in gold's
  hue and tinted, with gold text at 4.5:1 and the medal gold at 3:1 on
  it, and the real gold badge is drawn on it, in both themes.

No migration; the web on deploy, Android with the next APK.

### Dead screens removed (script 86, 2026-10-15)

Nothing in the app opened them, so no player could reach them and the
screen survey could not measure them; each colour round still had to edit
them. Removed, about 2,100 lines:

- `fixture_prediction/fixture_prediction_screen.dart` (the season-scoped
  match screen) and `fixture_predict_sheet.dart`, reached only from
- `competition/competition_seasons_screen.dart` and
  `my_active_seasons_screen.dart`, which nothing opened;
- `fixture_prediction/kickoff_countdown.dart`, used only by the match
  screen;
- `ledger/ledger_screen.dart` and `ledger_providers.dart` (the player's
  ledger page; the admin's ledger lookup has its own section and stays);
- `test/.../graded_points_tone_test.dart`, which drew the removed screen.

Kept: the prediction controller and submission (the matches tab saves
through them), `ScreenNames.fixturePrediction` and `ScreenNames.ledger`
(the server's list of names), the server routes, and the contracts. The
script also removes the generated `ledger_providers.g.dart`, which git does
not track.

No migration; the web on deploy, Android with the next APK.

### Colour audit: gold fills from the owner's light screenshots (script 87, 2026-10-15)

- CA-20: in the light theme gold filled with its dark text gold (#6B5300
  for the scheme's `secondaryContainer`, #755D00 for the day strip's
  badge) under white, which read olive brown: the selected friends'
  league chip, tonal buttons, the "today / yesterday / tomorrow" badges.
- The light scheme's `secondaryContainer` is `AppColorsLight.goldFill`
  (#B8860B, the dark theme's own goldenrod) with `onGoldFill` (#2A1E04,
  5.0:1); the day strip's badge takes the scheme's gold fill and its
  content colour, so both themes fill gold alike.
- Icons drawn in the text gold (three on the rules page, two admin
  metrics) take the medal gold `goldAccent`.
- Defence: `gold_fill_test.dart` -- the scheme's gold fill is goldenrod
  (gold's hue, saturated, bright enough not to read olive) with its
  content at 4.5:1, and the real day strip's "today" badge is drawn on
  it, in both themes; UI-02 keeps the badge label at 4.5:1.

No migration; the web on deploy, Android with the next APK.

### Provider results: the quota stop, late matches, the admins told (script 88, 2026-10-16)

Prompted by the Europa League night of 2026-10-15, whose results came on
time: shortly after midnight the 22:00 matches had no result yet, which
is expected (90 min settle, 15 min confirmation, 10-minute ticks), and
the sync recorded and scored them soon after. Reading the chain at that
point found these defects in the code, none of which caused a loss that
night:

- The Highlightly adapter stops calling once the provider reports 25
  requests left and would not call again until a restart: the count was
  only refreshed by a response. The reserve meant for results would stop
  results too, since both syncs shared one adapter.
- A postponed match was asked about every 10 minutes for 6 hours.
- A match still without a result 6 hours after kickoff was dropped
  without a word to the admins; quota and fetch failures were only
  container-log lines.

Changes:

- `HighlightlyFootballDataProvider`: a stop at the reserve (or a 429)
  holds for `quotaRecheck` (1 h), then one request is tried; a `clock`
  is injectable. The results sync gets its own adapter with
  `quotaReserve: 0` (composition root); the fixtures sync keeps 25.
- `SyncProviderResults`: fixtures are chased for `lateLookback` (24 h);
  past `lookback` (6 h) a group of late fixtures alone is asked about
  every `lateInterval` (2 h) at most, and a finished score is recorded at
  once. A late fixture is put to the admins once
  (`provider_sync.result_overdue`, Arabic, with the reason: quota, fetch
  error, not returned, not finished, or not saved). A postponed or
  cancelled match rests `parkFor` (1 h) between requests and is never
  also reported overdue.
- `PendingProviderFixture.game` (`home - away`, from `_pendingSql`) names
  the match in the admins' entry.
- Tests: the adapter's stop and its expiry, and the no-reserve adapter;
  the results sync's overdue entry, two-hourly late chase, the 24 h end
  and the resting postponed match, through `SyncProviderResults.call`.

Not changed: the database pool on match nights (425 `db.query_timeout`,
8/8 connections in use, about 85 waiting, at 23:54-23:55 on 2026-10-15),
which is the C-01 performance work. The hand-added copy of Hoffenheim -
Besiktas that players predicted on is not linked to a provider and takes
its result from an admin.

No migration; the server on push.

### A hidden match frees its double (script 89, 2026-10-16)

Decided by the owner on 2026-10-16. A match is hidden when it is
postponed or called off (0098). A hidden match is never scored, yet its
double still counted towards the day's one double, and a hidden match
takes no prediction write, so the double could not be taken off it
either: whoever had doubled it lost the day's double for nothing, and
was not told.

- Migration 0172: `prediction.reject_second_daily_double()` leaves out a
  double on a hidden fixture (`fs.hidden_at is null`), and
  `notification.notification_kind` gains `double_released`.
  `PostgresFixturePredictionRepository._countDoublesSql` leaves hidden
  fixtures out the same way, so `SubmitFixturePrediction` and the
  trigger agree. The player may double another match of that day that
  has not kicked off.
- `NotifyDoubleReleased` (application/notification), called by
  `AdminSetFixturesHidden` after a hide, best effort: each player who
  doubled a just-hidden fixture whose Riyadh day has not ended (never a
  test fixture) gets one inbox row (`double_released`, subject the
  fixture, deduped per player and fixture) and a push ("تحرّرت مضاعفتك",
  the match named, link `fixtures`), over the exact-hit announcement's
  transport (`ScoreAnnouncementRepository.targetsForParticipants`): a
  player with no device is not told. Inside the quiet hours the push is
  left out, the inbox row is not. Hiding again after showing says
  nothing new.
- The app's inbox labels `double_released` in words with a bolt icon;
  an older app shows its generic inbox title.
- Showing a hidden match brings its double back as it was; a player who
  doubled another match that day in between then has two that day, as
  a kickoff moved to another day can already leave. Not refused: the
  admin decides.
- Tests: `0172_hidden_double_released_test.sql` (the trigger and the
  adapter's count, hidden and shown again; every SQL test on a local
  Postgres 16), `hide_releases_double_test.dart` through
  `AdminSetFixturesHidden.call`, the kind and subject in the domain
  test, the stored row in the notification repository test, and the
  inbox row in `double_released_inbox_test.dart`.

**0172 must be on the live DB before this server is deployed.**

### Provider results skip hidden matches; affected tests only on the phone (script 90, 2026-10-16)

- `PostgresProviderSyncStore._pendingSql` leaves out hidden fixtures
  (`s.hidden_at IS NULL`). A hidden match was usually postponed or called
  off and is never scored, yet the results sync (and the live poll, which
  reads the same list) went on asking the provider about it until 24
  hours after kickoff, from Highlightly's 100 daily requests (Al Ahli -
  Al Nassr, reported postponed on 2026-10-15 and hidden the next day).
  Shown again, it is asked about again. Tested in
  `supabase/tests/provider_sync_pending_query_test.sql` (copy of the
  constant; run on a local Postgres 16).
- `docs/agent-script-protocol.md`: a script runs the affected tests only;
  the full suites run in Build Verification on every push, and nothing is
  released before they pass (decided by the owner on 2026-10-16).

No migration; the server on push.

### A match with both clubs from the list (script 91, 2026-10-16)

On 2026-10-15 the fixtures sync added the Europa League evening and an
admin added it again by hand; "هوفنهايم - بيشتكاش" beside the sync's
"هوفنهايم - بشكتاش" was not caught. The add form took any name with a
warning only, a name the catalog does not know carries no team id, and
both `SameMatchFinder` (batch 138) and the trigger of 0110 needed both
sides to agree by team or by name key. Decided by the owner on
2026-10-16: a match is added (and corrected) with both clubs picked from
the list, and a club the list lacks is added to it from the admin panel.
The first of the scripts on the duplicates; 93 (one club in two matches
within 12 hours), 94 (merging a copy instead of hiding it) and 95 (the
warning before a hide) follow, after 92 (four clubs never on the
schedule).

- Migration 0173: `admin.audit_action` gains `team_added`.
- `POST /admin/teams` (`AdminAddTeam`, port `TeamCatalogWriter`,
  `PostgresTeamCatalogWriter`): the name with its spaces folded (80
  characters at most) under the league picked, none for a continental
  one (as 0103 and 0104 file theirs); no crest, no short name (initials).
  One transaction with an advisory lock on the name's spelling key
  (`competition.team_name_key`, 0110): a club already under that key is
  refused, 409 `football_data.team_exists`, its Arabic message naming it,
  and nothing is written. Every club added is audited (`team_added`, the
  team's id, its name as the reason). `CacheClearingTeamCatalogWriter`
  empties the server's ten-minute catalog cache after an add.
- The add and edit forms (`fixture_schedule_section.dart`,
  `fixture_edit_section.dart`): a side whose name is not a club of the
  list blocks the button (a test fixture excepted), with the hint now
  saying so (`adminTeamNotInCatalogHint`) and a button "أضف النادي إلى
  القائمة" (`UnresolvedTeamHint`, `widgets/add_club_dialog.dart`). The
  dialog lists the clubs of the list whose names are close
  (`similarClubs`: one spelling key, one name inside the other, or one
  or two edits, a swap of neighbours counted once) to be picked instead;
  else it adds the club, refreshes the catalog and fills the field. The
  add form reads each side's id in build (`_sideId`) instead of keeping
  it in state, so a catalog that loads after typing still resolves it.
  The test-fixture switch sits in its own transparent `Material`: on the
  card's background Flutter asserted that its ink was hidden, which the
  first widget test of this form showed on the phone.
- The server does not yet refuse a match without team ids: an older
  admin app still sends one. Script 93 requires them for a non-test
  fixture.
- Tests: `admin_add_team_test.dart` (application), the cache in
  `read_caches_test.dart`, `admin_teams_route_test.dart`,
  `admin_teams_api_test.dart`, `add_club_test.dart` (the edit form, the
  add form and the dialog through the admin harness), the audit tokens in
  the domain and app tests; `0173_team_added_audit_test.sql` and
  `team_catalog_add_query_test.sql` on a local Postgres 16 with every
  migration.

**0173 must be on the live DB before this server is deployed.**

### Four clubs never on the schedule (script 92, 2026-10-16)

Decided by the owner on 2026-10-16: no match of Hapoel Beer Sheva
(هبوعيل بئر السبع), Maccabi Tel Aviv (مكابي تل أبيب), Beitar Jerusalem
(بيتار القدس) or Hapoel Tel Aviv (هبوعيل تل أبيب) appears in Nukhbaa, in
any league, cup, qualifier or friendly, in any season. That day the
schedule held one such match, "ألكمار - هابوعيل بئر السبع" of
2026-10-15, already hidden (2 predictions, no double); it stays hidden for
good, and no board changes.

- Migration 0174: `football_data.club_block_key` folds a name (case,
  spaces, dashes, dots, brackets, apostrophes; hamza forms, alif maqsura,
  taa marbuta, tatweel); `football_data.blocked_clubs` holds 23 fragments
  of such keys, Arabic and English spellings of the four clubs;
  `football_data.is_blocked_club(name)` says whether a name holds one.
  `competition.fixture_schedules` refuses a fixture with such a side, by
  its name or by its catalog team, hidden or test or not, and refuses to
  show one again (`fixture_schedules_blocked_club`); a hidden one may be
  corrected while it stays hidden. `football_data.teams` refuses a new
  club or a rename with such a name (`teams_blocked_club`). The catalog
  row the Europa League seed added stays, unused.
- `Team.blocked` (domain), read by `PostgresTeamRepository`
  (`is_blocked_club(name) AS blocked`): `ListTeams` leaves blocked clubs
  out of `GET /teams`, so no picker offers them; `SyncProviderFixtures`
  skips a match with one before writing (note `blocked club: ...`).
- The refusals in Arabic: `RegisterFixtureSchedule.blockedClub`
  (`competition.fixture_blocked_club`) from the schedule adapter on an add
  or a correction and from the visibility store on a show;
  `AdminAddTeam.blocked` (`football_data.team_blocked`) from the catalog
  writer, which checks the name before it looks for a club on file.
- The app drops Hapoel Beer Sheva's crest (`hapoel-beer-sheva.png` and its
  three entries in `team_logo_assets.dart`).
- Tests: `0174_blocked_clubs_test.sql` (the names, the schedule, the hidden
  match, the catalog, the catalog read) and the blocked step in
  `team_catalog_add_query_test.sql`, every SQL test on a local Postgres 16
  with every migration; `blocked_clubs_test.dart` through `ListTeams` and
  `SyncProviderFixtures`.

**0174 must be on the live DB before this server is deployed.**

### One club, one match within 12 hours; both teams from the list on the server (script 93, 2026-10-16)

The second script on the duplicates. 0110 and `SameMatchFinder` refused a
second copy only when both sides agreed; "هوفنهايم - بيشتكاش" beside
"هوفنهايم - بشكتاش" agreed on one. A club plays one match in 12 hours, so
one is enough.

- Migration 0175 replaces `competition.reject_second_copy_of_match()`
  (same trigger): a visible, non-test fixture is refused when another
  visible, non-test one kicks off less than 12 hours from it with one of
  its clubs -- the same catalog team or the same name key -- on either
  side. Both sides alike stays `fixture_schedules_one_match`; one club in
  both is `fixture_schedules_one_club`, the same `unique_violation`. A
  lock per club joins the lock per pair, the lesser key first. Rows
  already there are not checked.
- `PostgresSameMatchFinder` finds the same, both sides first
  (`both_sides`, `SameMatch.bothSides`); `RegisterFixtureSchedule` says
  "لأحد الفريقين مباراة مضافة من قبل: ..." with the match on file and its
  kickoff (`clubBusyOf`), and the schedule and visibility adapters turn
  `fixture_schedules_one_club` into Arabic too (a hidden copy shown again
  beside the visible one says so instead of a 503).
- `RegisterFixtureSchedule` and `CorrectFixtureSchedule` take
  `requireTeamIds` (on in the server's root): a fixture that is not a test
  needs both team ids, else 400 `competition.fixture_teams_required` in
  Arabic. Script 91's forms already send them; an older admin app sending
  a typed name is told to pick the club or add it.
- Tests: `fixture_teams_required_test.dart` (application),
  `fixture_teams_required_route_test.dart` (server),
  `0175_one_club_one_match_test.sql`, and `same_match_query_test.sql` now
  expecting one club alike to be found; every SQL test on a local
  Postgres 16 with every migration. The tap warning of scripts 91 and 92
  (a dropdown item tapped by `.last`, under the open menu) stays: the tap
  reaches the menu's own item and selects it, and `hitTestable()` found no
  item at all (eight tests failed on the phone), so the tests keep `.last`.

**0175 must be on the live DB before this server is deployed.**

### Faster checks, the same gates (script 94, 2026-10-16)

Measured on run #732 (235c852): Analyze + Test 8m24s, then Build Android
APK 8m37s after it, then Publish 27s -- 17m42s, the server and the web
released after that. Approved by the owner on 2026-10-16.

- `build-verification.yml`: Build Web, Build Android APK and Build server
  Docker image no longer wait for Analyze + Test; they start with it.
  Nothing they make is published there: `publish_latest_apk` now needs
  `workspace` as well as the build and the migrations, and Deploy Web and
  Release Server still start only when the whole run succeeded. A failed
  test still releases nothing; the builds just run to their end for
  nothing.
- The Android job keeps Gradle's downloads (`~/.gradle/caches`,
  `~/.gradle/wrapper`, `actions/cache@v6`, keyed by the Flutter version and
  `pubspec.lock`); the build itself runs from scratch every time. A bad
  cache is cleared from the repository's Actions -> Caches page.
- The actions run on Node 24 (the runner warned that Node 20 is
  deprecated): checkout v7, upload-artifact v7, download-artifact v8,
  setup-java v6, cache v6, configure-pages v6, deploy-pages v5,
  upload-pages-artifact v5, build-push-action v7, setup-buildx-action v4,
  action-gh-release v3 -- each version's inputs checked against the ones
  the workflows pass. `supabase/setup-cli@v1` in `db-backup.yml` stays: v3
  changes the image registry the dump runs from.
- `docs/agent-script-protocol.md`: a script resolves the workspace once
  (`flutter pub get`) and runs its tests with `--no-pub`, and prints each
  step's duration and the whole run's. Analysing only the affected
  packages on the phone was weighed and left until the timings show the
  analysis is what makes a script slow: it would find a break one push
  later.

No migration; nothing in the app or the server changes.

### Merging two copies of one match (script 95, 2026-10-16)

The third script on the duplicates of 2026-10-15/16. Some players
predicted one copy, some the other; hiding a copy took its predictions
out of sight, and the fixes by hand switched the triggers off to move
them. Decided by the owner: an admin merges a copy into the copy kept,
from the matches page, in one transaction, every trigger on.

- Migration 0176: `competition.merge_fixture_copies(duplicate, kept,
  actor, apply)`, security definer, closed to the clients. It refuses two
  fixtures that are not one match (no club in common, or 12 hours apart),
  a test fixture, a hidden kept copy, a copy already merged
  (`fixture_merge_*`). It hides the copy first, then moves to the kept
  copy, as they are (id, scoreline, `submitted_at`, double), the
  predictions of players who did not predict the kept copy, sent before
  its kickoff, from a season it belongs to; a double that would be the
  player's second of the kept copy's Riyadh day moves without it. The
  rest stay on the copy, counted. It hands the copy's provider link to a
  kept copy that has none, and writes the audit row (`fixtures_merged`)
  and `competition.fixture_merges`. With `apply` false: the counts only.
- `prediction.reject_fixture_write_after_kickoff` lets one write through
  after kickoff: a prediction moved by a merge, in the transaction that
  recorded it, from that copy to that kept copy, nothing else changed,
  sent before the kept copy's kickoff. `fixture_schedules_merged`: a
  merged copy is never shown again (its old scores and ledger entries
  stay on it, off every board, 0107).
- `AdminMergeFixtureCopies` (`POST /admin/fixtures/{id}/merge`,
  `{"into", "apply"}`) scores the kept copy again through `FixtureRescorer`
  (`ScoreFixture`, `PostFixtureToLedger`) when something moved and its
  result is in; `AdminListFixtureCopies` (`GET /admin/fixtures/{id}/copies`)
  lists the copies with their predictions, doubles, result and link
  (`PostgresFixtureMerger`).
- The app: a «دمج» button on every non-test row of «المباريات»; the
  dialog lists the copies, the admin picks the visible one that stays,
  reads the preview, and merges.
- Tests: `0176_merge_fixture_copies_test.sql`,
  `fixture_copies_query_test.sql`, `admin_merge_fixture_copies_test.dart`,
  `admin_fixture_merge_route_test.dart`, `admin_fixture_merge_api_test.dart`,
  `fixtures_admin_merge_test.dart`.

**0176 must be on the live DB before this server is deployed.** After the
deploy the owner merges, from the app, Salzburg - Milan (`fde6264d` into
`a2e41db8`) and Lech - Leverkusen (`147b5dda` into `c6d2b914`), preview
first.

### Merging a match put back to another day (script 137, 2026-10-23)

The provider put Al-Ahli - Al-Khaleej back from 22 October 21:00 to 23
October 21:00 (Riyadh) after the first kickoff had passed
(`provider_sync.kickoff_put_back_late`, error KXBA). The admin hid the
first copy and added the match again on the 23rd; 27 players who had
predicted only the first copy would get nothing, and 0176 refused to merge
copies 12 hours apart. Decided by the owner: such a copy may be merged.

- Migration 0182 replaces `competition.merge_fixture_copies` (same
  signature, still security definer, closed to the clients): two fixtures
  are also one match when the kept copy has the same two catalog teams,
  home and away, kicks off later by 7 days at most, and both belong to one
  season. Everything else is 0176: the moved predictions were all sent
  before the first kickoff, the kickoff lock lets them through only inside
  the merge, the copy is hidden for good, the audit row is written.
- `PostgresFixtureMerger._copiesSql` lists such a later copy from the
  earlier one, so the «دمج» dialog offers it; the refusal of
  `fixture_merge_not_copies` names the new rule.
- The provider link of the live case was moved by hand on 2026-10-23
  (`highlightly/1364206546` to `7e4b5b9d`), so the results sync records
  the kept copy's result.
- Tests: `0182_merge_postponed_copy_test.sql`,
  `fixture_copies_query_test.sql`.

**0182 must be on the live DB before this server is deployed.** Then the
owner merges `d0ee283f` (22 October, hidden) into `7e4b5b9d` (23 October)
from its row, preview first: 27 move, 46 predicted both.

### The egress caches (script 138, 2026-10-23)

Supabase: the organization (Free Plan) went over its 5 GB egress quota in
the previous billing cycle; the grace period ends on 22 November 2026, and
the cycle of 28 September - 28 October stood at 6.42 GB on 23 October
(about 100 MB a day until 9 October, 300-460 MB a day since 10 October).
`pg_stat_statements` (since 27 July) put first the reads that returned the
most rows: a player's whole history (`listByUser`, 17.4 million rows), a
season's fixture list (`listSeasonFixtures`, 10.6 million) and the batched
schedules (8.5 million). Decided by the owner on 2026-10-23: cut them now,
in the server only (no APK). Statistics were reset on 2026-10-23 20:21 UTC
to measure what remains.

- `CachedPredictionHistory` (new) in front of `listByUser`: one answer per
  player for 10 minutes. `SubmitFixturePrediction` is handed it, so a
  player's own save or amendment drops that player's history at once (a
  participant not seen yet -- a first prediction in a new month -- drops
  every history). `ListMyFixturePredictions` reads it, with its own
  `CachedFixtureScheduleRepository` (10 minutes, 512 batches) for the
  visibility filter. Hiding a fixture or merging copies drops both
  (`forgetSchedules`, `predictionHistory.forget`).
- `CachedFixturePredictionReads.listSeasonFixtures`: cached per season for
  `linkTtl` (60 s), dropped on a link or unlink through it. The read
  use-cases now get the read caches: `ListCurrentMonthFixtures` (season
  fixtures and display-only results), `GetSeasonFixtureLeaderboard`,
  `GetLiveStanding` (season fixtures and the in-play predictions, frozen at
  kickoff; its results stay direct, so a recorded result leaves the live
  line at once) and `GetGroupMonthBoard`. `BrowseSeasonFixtures` stays
  direct: the admin's matches page reads it right after a change.
- The caches live in the server process. Should the server ever run more
  than one instance, a player's own save would show on the other instances
  only when their copy expires (10 minutes).
- Tests: `cached_prediction_history_test.dart` (through
  `ListMyFixturePredictions`, wired as the composition root wires it),
  `read_coalescing_test.dart` (a season's fixtures).

### A new league from the add-match form (script 139, 2026-10-24)

Asked by the owner: some competitions play rarely but carry strong
matches, and the league list held only what the seed migrations put there
(0027, 0038, 0103, 0104, 0180), so their matches had no league of their
own.

- The league list of both match forms (`LeaguePickerField`) ends with
  «دوري جديد» (`admin.fixtures.leagueField.new`). It opens
  `AddLeagueDialog` (`add_league_dialog.dart`): the admin types the name;
  a league on file under the same spelling key (`clubNameKey`) is offered
  instead and the add stays off; else `POST /admin/leagues`, the league
  list is read again and the new league is picked for the match. A
  cancelled dialog puts the list back on the league picked before.
- `POST /admin/leagues` (`AdminAddLeague`, port `LeagueCatalogWriter`,
  `PostgresLeagueCatalogWriter`): admin only; the name folded, 1-80
  letters; one transaction (an advisory lock on
  `competition.team_name_key`, the league on file, else a new row). The
  league is added with `is_continental = true`, as 0104 filed the big
  derbies: its clubs come from the whole catalog, and a club added under
  it is filed under none. A name already on file is `409`
  `football_data.league_exists`, its Arabic message naming that league;
  every league added is audited (`league_added`, migration 0183).
  `GET /leagues` reads the table directly, so the league is in the next
  read; the provider sync maps leagues by name and ignores it.
- No new dependency, no l10n key. Tests: `admin_add_league_test.dart`,
  `admin_leagues_route_test.dart`, `admin_leagues_api_test.dart`,
  `add_league_test.dart` (through `FixtureScheduleSection`),
  `0183_league_added_audit_test.sql`, `league_catalog_add_query_test.sql`.

**0183 must be on the live DB before this server is deployed.**

### The hero's own card, the special hero, the doubles card (script 140, 2026-10-24)

Asked by the owner: the hero of the day (decided 2026-10-07) was an
admin's card only, and the board said nothing of the doubles that paid.
His decisions: the hero card is shared by the admins and by the hero
himself only; a hero whose exact call was also his double of the day is
the special hero of the day (البطل المميز لليوم), the same card under
that name; the doubles card, with names or only their count, is the
admins' alone.

- The predictions board (`fixture_predictions_board_page.dart`) works out
  each match's hero for every viewer (`soloExactParticipant`, the
  server's `exact_scoreline`) and keeps it for an admin, or for the hero
  himself (his participant id among `/me/fixture-predictions`). The hero
  reads «حصلت على بطل اليوم» above the table; his cell and his
  reaction sheet offer the card. `DayHero` carries `isDouble` and the
  server's `points`; on a double the line, the sheet's button, the card's
  title («بطاقة البطل المميز لليوم», key `dayHero.double` for
  «مضاعفة · 6 نقاط») and the share text say so.
- Admins only: each started match whose doubles earned points (a double
  with the server's points above zero, the board's ⚡🔥) gets a line
  «مضاعفة ناجحة: 3 لاعبين · …» (`fixturePredictions.doubles.<id>`)
  that opens `DoubleHitsShareDialog` (`double_hits_card.dart`): the
  match, each player numbered with his points (most first, at most 15
  names, the rest counted), or with «إظهار أسماء اللاعبين» off only
  the count and «كل لاعب 6 نقاط»; captured and shared as the hero
  card is, the text «اختار 3 لاعبين مباراة … مضاعفة، فحصلوا
  على نقاط المضاعفة، كل لاعب 6 نقاط» with the names under it
  when shown, and the admin's invitation link.
- Nothing is graded in the app: the grade and points are the board's
  read. No server change, no migration, no new dependency, no l10n key.
  Tests: `day_hero_test.dart` (the hero's own, the special hero),
  `double_hits_test.dart` (new), both through the real board page.

### The history's own writes; schedules held per fixture (script 141, 2026-10-25)

Measured after script 138 (`pg_stat_statements`, reset 2026-10-23 21:23
UTC, read 2026-10-25): egress fell from about 450 MB a day (22-23
October) to about 270 MB (24 October), still above the 167 MB a day a
5 GB cycle allows. Of 3.27 million rows, a player's history
(`listByUser`) returned 30% (3256 reads, about 301 rows each) and the
batched schedules 23% (5320 reads, 748 thousand of the widest rows);
1504 predictions were sent in the same time, each followed by the app's
read of the history. Script 141 cuts both in the server only (no APK,
no contract change); pagination waits for the next measurement.

- `CachedPredictionHistory`: a save or an amendment that succeeded is
  written into the history held for that player (goals, double, the
  submission time, the season of the player's other predictions under
  that participant; newest first, then by id, as the query orders it), so
  the read after a save costs no query. It still drops the history on a
  failed write, when nothing is held for that player, for a participant
  not seen yet (every history) and for an id not in lower case.
- `CachedFixtureScheduleRepository` holds each fixture's schedule on its
  own (a fixture without one too), keyed in lower case, instead of each
  batch under the sorted list of its fixtures: a batch reads only the
  fixtures not held, so a history that grew by one prediction reads one
  schedule, and every player and screen shares the same entries.
  `maxEntries` now counts fixtures (4096 by default and for the history's
  copy). Writes and `forget` still drop the whole cache.
- Tests: `cached_prediction_history_test.dart` (through
  `ListMyFixturePredictions`, wired as the composition root wires it: the
  read after a save, the amended row, a failed write, the one new
  schedule); `read_caches_test.dart` and `read_coalescing_test.dart`
  unchanged.

### Every build names itself; the server refuses old ones (script 142, 2026-10-25)

`ops.error_group_builds` (7 days to 2026-10-25) held 27 builds; 19 of them
(534 of 588 errors) were the old Android app `com.example.mobile` (before
script 110, 2026-10-18), whose update installs the new app beside it, and
10 were older than batch 147, so they do not know the minimum build. The
owner reported that no player answers a notification. Every build since
2026-10-03 shows a `409` envelope's Arabic message as it is
(`ErrorPresenter`, `kindForStatus`), so the server is the one channel
that reaches all of them. Decided by the owner on 2026-10-25: the gate
starts only when he sets the variable, after the release that sends the
header can be downloaded.

- The app's one HTTP client (`createHttpClient`, both transports) wraps
  `BuildHeaderClient` (api_client) off the web: every request carries
  `x-nukhba-build` (`appBuildHeader`, contracts) with
  `NUKHBA_BUILD_NUMBER` (0 for a local run). The web build sends nothing
  (no CORS change) and reloads to the newest release by itself.
- `buildGate` (`apps/server/lib/http/build_gate.dart`), wired in the root
  middleware: with `NUKHBA_BUILD_HEADER_SINCE` set to a release number on
  Northflank, a request without the header or from an older build gets
  `409 app.update_required` with `oldBuildMessage` (install the new app
  from links.nukhbaa.app, sign in with the same account, delete the old
  app), before any route or the database. Always open: `/`, `/health`,
  `/app/latest-build`, a browser request (an `Origin` header) and build 0.
  Unset, empty or not a positive number: the gate is off. No database
  read, no migration, no new dependency, no l10n key.
- Rollout: push; when the new release is on the links page, set
  `NUKHBA_BUILD_HEADER_SINCE` to its number (Northflank redeploys); remove
  it to let every build in again.
- Tests: `build_gate_test.dart` (server: the root middleware without the
  variable, the gate the root wires), `build_header_client_test.dart`
  (api_client: the header through the real `ApiTransport`, the refusal read
  as an invariant with its Arabic message), `http_client_test.dart`
  (mobile).

### The refusal names the old app's own buttons; a 32-bit file (script 143, 2026-10-25)

After `NUKHBA_BUILD_HEADER_SINCE=772` (2026-10-25) an old build shows the
refusal on its session screen (`_ConnectionRetry`) as plain text, so the
link cannot be tapped; and `nukhbaa.apk` on the links page is arm64 only,
while `ops.frame_reports` names up to 8 players on low-end phones that may
be 32-bit. Asked by the owner on 2026-10-25.

- `oldBuildMessage` now leads with the old app's own buttons: «تسجيل
  الدخول بحساب آخر» (clears the session on the phone even when the server
  refuses, then the sign-in screen) and «يتوفر تحديث جديد» (the sign-in
  row since 2026-10-13, d55f4b3; the in-app install picks the phone's
  processor). Builds before it (8, among them 599e510 and 9d7c474) have
  only the link, which stays in the message.
- The release job also publishes `nukhbaa-32bit.apk` (the armeabi-v7a
  file), copied after `checksums.json` like `nukhbaa.apk`; no ABI in its
  name, so `GithubBuildInfoRepository` never lists it. The links page
  (outside this repo) gets a second button:
  `https://github.com/adbrhman/nukhbaa/releases/latest/download/nukhbaa-32bit.apk`.
- Server and CI only; no APK change needed for the message. Test:
  `build_gate_test.dart` (the two button names).

### Updates download from nukhbaa.app (script 144, 2026-10-25)

Players reported that an update downloads very slowly, and normally over a
VPN: the in-app updater and the download buttons took the APK from GitHub's
download host (`GithubBuildInfoRepository`, `releases/latest/download`),
which is throttled in Yemen like github.io, while nukhbaa.app (the
Northflank web mirror) is reachable. The owner asked for the best option
on 2026-10-25; chosen over Cloudflare R2 (an account and keys) and asking
players for a VPN; Supabase Storage was ruled out (egress).

- Deploy Web downloads the release's arm64-v8a and armeabi-v7a APKs
  (`gh release download build-<sha>`) into the mirror's `site/apk/`, with
  copies `nukhbaa.apk` and `nukhbaa-32bit.apk` for the buttons; no APKs (a
  manual deploy of a commit without a release) leaves the folder out.
- `nginx.conf`: `/apk/` sends them as they are with the APK type; the
  commit's names are kept a year, the buttons' copies `no-cache`; a
  missing file is a 404, never a page. `check_mirror.mjs` checks each one
  in the image (type, no compression, cache rule, bytes, the 404).
- Server: `MirroredBuildInfoRepository` (infrastructure) wraps the GitHub
  reader in the composition root. An APK whose release name carries the
  commit moves to `https://nukhbaa.app/apk/<name>` once a `HEAD` there
  answers 200 with the APK type (asked again after 2 minutes on a miss,
  never again on a hit); until then the GitHub address stays. The SHA-256
  stays the release's, which the updater checks whatever the host. Every
  build reads the address from `GET /app/latest-build`, so old builds
  download from the mirror too. `NUKHBA_APK_MIRROR` (Northflank) sets
  another https folder, or `off`.
- The landing page's button points at `/apk/nukhbaa.apk` (GitHub's release
  page only when the mirror lacks it), with a link for 32-bit phones. The
  links page (outside this repo) should use the same two addresses.
- Northflank egress, about 6 GB when 145 players take a 41 MB update, sits
  within the free plan's resources. No migration, no new dependency, no
  APK needed. Test: `mirrored_build_info_repository_test.dart` (through
  `GetLatestBuild` over the real GitHub reader).

### The update row stayed after updating (script 145, 2026-10-25)

After script 144 the account tab kept offering «يتوفر تحديث جديد» right
after the update was installed (the owner, 2026-10-25). `UpdateGate`
decides a build is the newest when `apk_url` holds `/build-<its sha>/`
(Android, and the web build's reload check); script 144 had moved
`apk_url` to `nukhbaa.app/apk/nukhbaa-<abi>-<sha>.apk`, which never holds
it, so every build saw an update forever.

- `MirroredBuildInfoRepository` keeps `apk_url` GitHub's and moves only
  `assets` (what the in-app updater downloads, by processor) to the
  mirror. Server only: every build, old ones included, reads it from
  `GET /app/latest-build`, so the row goes away with the next check.
- Test: `mirrored_build_info_repository_test.dart` (`apk_url` keeps
  `/build-<sha>/` while the assets come from the mirror).

### The head-to-head opponent is secret until the last kickoff (script 146, 2026-10-25)

A group played its round-robin in the slots' own order
(`opponentSlot(slot, round)`), and `/me/h2h-league` named the opponent of
every approved round; the board shows everyone's picks as each match kicks
off. A player who knew his opponent could shape his later picks of the day
against the opponent's earlier ones, and two friends could arrange their
round. Decided by the owner on 2026-10-25 (option D): a secret round order,
the opponent named at the last match of the day, the admins watching the
suspicious matches (a later batch). Server and database only; the screen
follows in script 147.

- Migration 0184 (additive): `gamification.h2h_league_turns`, one row per
  group: a permutation of 1 .. capacity - 1 (the circle's turns), shuffled
  by `gen_random_uuid()` in the database. Round n plays turn turns[n]
  (`H2hLeaguePolicy.turnOf`; again from the start past the end), so every
  pair still meets once; a group without a row plays the turns in order.
  Append-only, server-only (RLS, no grants). Its insert trigger refuses an
  order that is not a permutation (`h2h_league_turns_order`) and an order
  for a group whose member was seated at or before a lock of a round of
  its month (`h2h_league_turns_played`): the table is recomputed from the
  order on every read, so a group that may have played keeps its order
  (the October pilot).
- Written by `PostgresH2hTurnKeeper.ensureSql` (the same guard in its
  WHERE): at the end of the draw's transaction and of the extra groups'
  one, and by `RunH2hRounds` (port `H2hTurnKeeper`) for yesterday's and
  today's months before anything is approved or locked; a failed order
  approves and locks nothing in that run.
- Every pairing reads the order: `H2hLeaguePolicy.table(turns:)`,
  `h2hGroupPairs`, `GetMyH2hLeague`, `GetMyH2hGroupRound`, the admin's
  groups and `CloseH2hMonth`. `PostgresH2hSheetReader` reads it
  (`turnsSql`, as text) and each locked round's last kickoff among the
  fixtures that count (`roundStatusSql.last_kickoff`).
- The secret (`h2hOpponentSecret`): a round not started, or live before its
  last fixture that counts kicks off (`FixtureLock`: at or after the
  kickoff), names nobody. `MyH2hRound` carries `opponentHidden`,
  `revealsAt` (the live round's last kickoff) and `ownPoints`; no opponent,
  no match, no opponent points, no result. `GetMyH2hRound` then reads no
  pick but the caller's and withholds every line of theirs;
  `GetMyH2hGroupRound` and the admin's group round return no pairs
  (`pairsHidden`): the admins play too. Settled and void rounds are open.
- Contracts (additive): `opponent_hidden` and `reveals_at` on
  `H2hRoundViewDto` and `MyH2hRoundDto`, `matches_hidden` and `reveals_at`
  on `H2hGroupRoundDto`. Builds before 147 read a secret opponent as the
  group average: decided 2026-10-25, `NUKHBA_BUILD_HEADER_SINCE` goes up to
  147's release before the first November round locks.
- Known limit: by elimination a member can tell the opponent of the last
  rounds (two candidates before round 18, one before round 19).
- Tests: `h2h_league_policy_test.dart` (`turnOf`, every pair once in any
  order, the ordered table), `get_my_h2h_league_test.dart`,
  `get_my_h2h_month_test.dart`, `get_my_h2h_round_test.dart`,
  `get_my_h2h_group_round_test.dart`, `admin_h2h_groups_test.dart`,
  `close_h2h_month_test.dart`, `h2h_rounds_test.dart` (the keeper before any
  lock; a failure locks nothing), `postgres_h2h_adapters_test.dart`,
  `postgres_h2h_group_extension_test.dart`, the routes through
  `h2h_round_routes_test.dart`, `h2h_group_routes_test.dart`,
  `h2h_league_routes_test.dart`, `h2h_admin_desk_routes_test.dart`, the
  DTO tests; `0184_h2h_secret_turns_test.sql` (18 checks) and
  `0100_h2h_queries_test.sql` (the last kickoff). All 71 SQL tests pass on
  PostgreSQL 16 with every migration (127 files).

**Apply 0184 in the Supabase SQL editor before pushing this server.**

### The secret opponent on the screen (script 147, 2026-10-25)

The app side of script 146. Builds before it read an empty opponent as the
group average (`h2h_parts.dart`, `h2h_next_match.dart`, the round page),
so a secret one would show as «متوسط المجموعة»; this build reads
`opponent_hidden` first everywhere. Push it with 146; then, decided by the
owner on 2026-10-25, `NUKHBA_BUILD_HEADER_SINCE` goes up to this release
before the first November round locks.

- `h2h_texts.dart`: «خصم سري» (`h2hSecretOpponent`), `h2hRevealLabel`
  («يُكشف الساعة 23:00» on the Riyadh clock from `reveals_at`, else
  «يُكشف عند انطلاق آخر مباراة في الجولة»), `h2hSecretPairs`,
  `h2hSecretPick` («مخفي حتى كشف الخصم»), and a rule: «خصمك في كل جولة
  سري، ويُكشف عند انطلاق آخر مباراة فيها.»
- `h2hOpponentOf` and `H2hSide(secret:)` (a lock in place of a picture);
  `H2hRevealLine`. The match card and a round's tile show the caller's
  own points only («نقاطك 6») and when the opponent is named; the round
  page names nobody, withholds every pick of theirs with «مخفي حتى كشف
  الخصم» and their counts with «—»; the group section shows
  «مواجهات هذه الجولة سرية…» instead of pairs (`matches_hidden`); the
  admin's group round and player tab say the same.
- Nothing is decided in the app: the secret is the server's flag.
  No l10n key, no dependency, no server change.
- Test: `h2h_secret_opponent_test.dart` (the real screens over the real
  `AuthApi`: the match card, the rounds, the round page, the group section,
  the rules; 360px at text x1.3 and x2).

### The admin's minimum forces the update (script 148, 2026-10-26)

Asked by the owner on 2026-10-26: most players do not understand the
refusal screen (the old builds' plain text), so while an admin holds a
minimum the app must download the update by itself, a cancelled download
must keep the player out with a warning, and clearing the minimum must
bring back the quiet row; the builds too old to know the minimum keep the
server's text. Shipped with 146 and 147.

- Server: the build gate (script 142) now refuses below the higher of
  `NUKHBA_BUILD_HEADER_SINCE` and the minimum an admin raised from the
  dashboard («ارفع الحد الأدنى», 0113) -- `servedMinimum`, read through
  `ReadMinSupportedBuild` for a request the gate may refuse only (never for
  the update check, the web build or a local run). One
  `CachedAppUpdatePolicyStore` (60 s, concurrent reads shared, the admin's
  write held at once, a failed write drops it) serves the gate, the update
  check and the admin's button. An unreadable minimum is no minimum. Once
  the variable is removed from Northflank, the admin's button alone turns
  the refusal on and off.
- App: `RequiredUpdateScreen` («يتوفر تحديث جديد · حدِّثه لتكمل») starts the
  in-app download by itself once per screen (not the Play build); cancelled
  or failed, it stays with «لتدخل إلى نُخبة حدِّث التطبيق أولًا. لن يفتح قبل
  التحديث.» and its button. `installUpdate` answers the terminal phase. The
  admin's confirmation says what the button now does.
- Who sees what while a minimum is held: builds since batch 147 (they read
  `min_supported_build`) see the update screen and the download; older
  builds send no header and get the server's 409 text on every request.
- No migration, no new dependency, no l10n key. Tests:
  `build_gate_admin_minimum_test.dart` (the root's wiring: raised, cleared,
  the higher of the two, unreadable, exempt requests never read it),
  `cached_app_update_policy_store_test.dart`, `update_required_test.dart`
  (the download by itself, a cancel, no second start on a return).

### Only the builds before the head-to-head tab read the refusal (script 149, 2026-10-26)

The owner's list of players by build (`ops.frame_reports`, 2026-10-26):
93 Android players, 36 of them on builds first seen before the
head-to-head tab (10 October; «توقعاتي» in their bottom bar), 14 between it
and batch 147 (11-14 October), 43 on builds that know the minimum. Asked by
the owner: the server's refusal for those 36 only, and only while the
minimum is held. This replaces script 148's server half.

- The build gate is the variable's again (script 142): `buildGate` and the
  root middleware read `NUKHBA_BUILD_HEADER_SINCE` alone; script 148's
  `servedMinimum`, `adminMinimumFrom` and `ReadMinSupportedBuild` are gone.
- `bearerAuth`, once the principal is verified: a request that names no
  build (`sentNoBuild`: no `x-nukhba-build`, no `Origin`) from a player
  `RefuseRetiredBuild` finds retired is answered `409 app.update_required`
  with `oldBuildMessage` (`retiredBuildRefusal`). Retired: an admin holds a
  minimum (the cached 0113 row) and the player's newest Android session ran
  a build first seen before `RefuseRetiredBuild.retiredBefore`
  (2026-10-10 00:00 Riyadh) -- `PostgresRetiredBuildReader.playersSql`,
  held 10 minutes by `CachedRetiredBuildReader`. No minimum, an unreadable
  one or an unreadable list refuses nobody; a build that names itself and
  the web are never refused. A player who updates names his build and is
  served at once.
- Who sees what while a minimum is held: the 36 read the refusal; the
  builds since batch 147 show their update screen (the download by itself
  from 148's build on); 11-14 October are served as before.
  `NUKHBA_BUILD_HEADER_SINCE` should be removed from Northflank: while set,
  it still refuses every build without the header.
- No migration, no new dependency, no l10n key. Tests:
  `retired_build_refusal_test.dart` (through `bearerAuth`, the root's
  wiring, the admin's button), `refuse_retired_build_test.dart`,
  `retired_build_reader_test.dart`, `retired_build_players_query_test.sql`
  (PostgreSQL 16).

### The 36 alone, by their own switch (script 150, 2026-10-26)

The owner, on 2026-10-26: the update is for the 36 players on the oldest
builds first, and for nobody else; a plan for the rest comes after. The
dashboard's minimum cannot do that -- every build since batch 147 obeys it
with its own update screen (43 players) -- so script 149's refusal no
longer follows it.

- `RefuseRetiredBuild(enabled:, players:)`: on while
  `NUKHBA_REFUSE_RETIRED_BUILDS` is `on` (`true`, `yes`, `1`; Northflank
  redeploys on a change), off when it is removed; the minimum plays no
  part. The rest is 149's: the request names no build, the player's newest
  Android session ran a build first seen before 2026-10-10 00:00 Riyadh.
- To retire the 36 alone: remove `NUKHBA_BUILD_HEADER_SINCE` (while set it
  refuses every build without the header, 87 of the 93 players listed),
  set `NUKHBA_REFUSE_RETIRED_BUILDS=on`, and leave the dashboard's minimum
  unset. The players inactive since before that list, on the same old
  builds, are refused too when they come back.
- The admin's confirmation says the minimum reaches the builds since 15
  October only. Tests: `refuse_retired_build_test.dart` (the switch),
  `retired_build_refusal_test.dart` (through `bearerAuth`: off, on, a build
  that names itself, the web, one read for many requests).

### The retired builds' own words (script 151, 2026-10-26)

The owner tested the refusal on a build from before the head-to-head tab
(2026-10-26): it worked, but `oldBuildMessage` sends the player to
«تسجيل الدخول بحساب آخر» then «يتوفر تحديث جديد», and those builds' sign-in
screen has no such row (it came on 13 October). `retiredBuildRefusal` now
carries `retiredBuildMessage`: open the browser, type nukhbaa.app, tap
«حمّل التطبيق لأندرويد» (the landing page's button), sign in with the same
account, delete the old app. The gate's own message is unchanged. Test:
`retired_build_refusal_test.dart`.

### The invitations and the duels removed (script 153, 2026-10-26)

The owner removed both features from every layer ("full removal"). What a
player and an admin see:

- **App**: no «ادعُ أصدقاءك» or «التحديات» row on the account tab, no
  invitation code at registration or on the name screen, no duels card on
  the home page, no duel offer after a saved prediction, no duel lines on
  the live card, no duel-win marks on the month board, no "who you duel
  most" on the friends' league start, no admin section «نظام الدعوات» and
  no held-invitations row on the admin home. A shared card (exact hit,
  day hero, top three, doubles, champion) now carries the site's link
  (`appSiteLink()`, `core/config/web_links.dart`), never an invitation
  code. A `?duel=` or `?ref=` link opens nothing special; a `duel` push
  opens the app as a plain tap. When no group row is left in the account's
  friends group, the group goes too.
- **Ranking**: invitation points no longer break a points tie anywhere --
  month board, season board, day board, group boards, personal record,
  crown and the daily snapshot: points, exact scorelines, right outcomes,
  the earlier join. Migration **0185** redefines
  `leaderboard.capture_season_rank_snapshots` the same way, re-orders each
  season's latest snapshot among players level on points (as 0108 did) and
  switches `gamification.feature_flags.referrals` off. The rules page
  (`rules.tieBreak`) and the public terms (`/rules/`) say so; the privacy
  page says the install id now only limits crash reports.
- **Kept**: every stored invitation, invitation point, duel and duel
  notification row (additive rule, section 5 of the protocol); the
  champions' frozen `referral_points` column (no longer sent); the
  `NUKHBA_INVITE_BASE_URL` define (league links). The inbox, its unread
  count and a single read leave out the stored `duel_challenged` /
  `duel_accepted` rows
  (`PostgresNotificationRepository`, `kind NOT IN (...)`); a screen-views
  report naming `duels`, `duel_accept`, `duel_create` or `invite` drops
  those names, as any unknown name.
- **Moved, not removed**: the search by name that invites a player to a
  friends' league used `GET /duels/players`; it is now
  `GET /groups/invitees?q=` (`SearchGroupInvitees`, `InviteeDirectory`,
  `PostgresInviteeDirectory`, `GroupInviteesDto`,
  `GroupsApi.searchInvitees`), same SQL and limits.
- **Server**: the `/duels/*`, `/me/duels`, `/me/referral*`,
  `/seasons/{id}/duel-wins` and `/admin/referral*` routes, their use-cases,
  ports, adapters, DTOs and API methods, the referral qualification
  scheduler, the duel rate limits and `keepStoredDouble` of
  `SubmitFixturePrediction` (used by duel acceptance only) are gone;
  `GET /seasons/{id}/live` no longer carries `duels`. Older APKs read the
  missing keys as empty; their duel and invitation screens show an error,
  and their league search finds nobody, until they update.

Order: apply **0185** in the SQL Editor, then push (the running server keeps
working on 0185). After Northflank has redeployed, script 154 brings
migration 0186, which drops the invitation and duel functions and views
the old server still called.

### The invitation and duel functions dropped (script 154, 2026-10-26)

Migration **0186**, applied once the server of script 153 was live, drops
what only the removed features called: the invitation functions
(`ensure_referral_code`, `mark_referral_install`, `claim_referral`,
`qualify_referrals`, `expire_idle_referrals`, `review_referral`,
`referral_hash`) and views (`referral_invitations`,
`referral_season_points`, `referral_month_points`), the duel functions
(`create_`, `accept_`, `cancel_`, `decline_duel_challenge`,
`new_duel_code`) and the `users_cancel_open_duel_challenges` trigger on
`identity.users`. Every table and row stays, with the guards that keep
the history unaltered (`reject_referral_mutation`, `guard_referral_claim`,
`guard_referral_event`, `guard_duel_challenge_change`) and
`gamification.normalized_email` (an index uses it). The SQL tests of the
dropped functions went with them; `0186_..._test.sql` checks what is left.

### The feed's reads held until written (script 155, 2026-10-27)

Supabase: the Free Plan's 5 GB egress went over again (7.62 GB in the
cycle of 28 September - 28 October); the restriction starts on 22
November if the organization stays over. The owner asked for a way that
costs nothing and changes nothing in the app. `pg_stat_statements`
(reset 2026-10-25 21:58 UTC) put first the month's feed reads: the
results (1641 reads, about 217 rows each), the win-share split (1078,
about 322), the schedules (2888, about 116 of the widest rows) -- each
read again whole every 20 to 60 seconds, when its cache expired. Server
only: no APK, no contract, no migration.

- Every writer of these rows runs in this server, so each cache is held
  until a write drops it; the ttl (30 minutes) only bounds an edit made
  outside the server (the SQL Editor) or a deleted account's predictions.
- `CachedFixtureResultReads`: held per fixture (a fixture without a result
  too), shared by `findByFixture` and `findByFixtures`; a batch reads only
  the fixtures not held. `RecordFixtureResult` (the admin's form and the
  provider sync) is handed this decorator, so a result drops its fixture
  and shows on the next read. Scoring keeps the plain repository.
- `CachedFixturePredictionTallyReader`: held per fixture the same way.
  `CachedPredictionHistory` (what `SubmitFixturePrediction` writes
  through) calls `onFixtureWritten` for every save or amendment, failed
  ones too, which drops that fixture's split; a merge drops every split.
- `CachedFixtureScheduleRepository`: ttl 30 minutes (writes already drop
  it); one cache (8192 fixtures) now serves the history too.
- `CachedPredictionHistory` and `CachedFixtureScoreRepository`: ttl 30
  minutes (their writes already update or drop them).
- Should the server ever run more than one instance, a write would show
  on the other instances only when their copy expires (30 minutes).
- Tests: `feed_reads_until_written_test.dart` (new: the feed through
  `ListCurrentMonthFixtures`, a result through `RecordFixtureResult`, a
  prediction through `SubmitFixturePrediction`, wired as the composition
  root wires them); `read_caches_test.dart`, `read_coalescing_test.dart`
  and `cached_prediction_history_test.dart` follow the new ttls.
- To measure: reset `pg_stat_statements` after the deploy and read the
  egress per day in Usage after two days.

### Home and account information architecture (script 156, 2026-10-27)

Mobile only: no server, contract or migration change.

- Home reads: pending predictions, live and upcoming fixtures, the
  monthly overview, prediction history, then the web-only push setup.
  `HomeScreen` no longer mounts the daily-challenge card; its widget,
  API and own tests stay, so this removes it from the home only.
- Account: the summary shows points first on the RTL right, then
  settled matches, then accuracy. The rows are grouped as performance
  (points, insights), achievements (elite card, badges), the app,
  administration (admins only) and the account's e-mail; sign-out
  stays last.
- Tests through the real `HomeScreen` and `AccountScreen`:
  `home_reading_order_test.dart`, `home_my_predictions_test.dart`,
  `account_groups_test.dart` (order, no challenge card on the home,
  RTL figure order).

### The board's headers pinned, the day's cards folded; a way to the developer (script 157, 2026-10-27)

Mobile only: no server, contract or migration change.

- Predictions board (`fixture_predictions_board_page.dart`): the search
  stays on top; the reaction hint and the day's cards scroll away with
  the table (one `CustomScrollView`), whose header row (the player
  caption and every match) is a pinned `SliverPersistentHeader`. The
  headers' sideways scroll and the cells' follow each other (two
  controllers), so a header always sits over its column. An admin's day
  had eleven cards above the table, which left it a third of the screen.
- Up to three cards show as they were; more fold into one line,
  `fixturePredictions.cards.toggle` ("بطاقات اليوم (N): ..."), closed on
  opening the page. Order: the top three, the heroes, then the doubles
  that paid, most players first (kickoff order between equals).
- Account tab: a "الدعم" group after "التطبيق" with one row,
  `account.contactDeveloper` ("تواصل مع المطوّر"), which opens Nukhbaa's
  WhatsApp channel (`nukhbaaSupportUri`) through
  `notificationLinkOpenerProvider`; when nothing opens it, a snack bar
  says so. A WhatsApp channel is one-way: followers can react but not
  write to it.
- Tests through the real page and screen:
  `predictions_board_layout_test.dart` (five cards fold and open, most
  first; forty players scroll under the pinned headers; the headers and
  columns follow each other both ways -- all three fail on the old page),
  `account_contact_test.dart` (placement, the opened address, the failure
  line, text x2 at 360px).

### The sole exact call earns 6, or 9 on the double (script 159, 2026-10-27)

Decided by the owner on 2026-10-27, from the kickoffs of 1 November 2026
(00:00 Riyadh, `2026-10-31T21:00:00Z`): the hero of the day -- the only
player of all who called a match's exact score -- earns 6 points instead
of 3, and 9 instead of 6 when that call was his double. Two or more exact
calls: 3 each (6 on a double), as before. Server and app; no migration.

- Ruleset v4 (`ConfiguredRulesetProvider`): `solo_exact_bonus: 3` and
  `solo_exact_since`, read by `ScoringRuleset` (`soloExactBonusPoints`,
  `soloExactSince`, `soloExactBonusAppliesTo`); absent on older snapshots
  (0, no effect). The bonus is added once, never multiplied.
- `Scoring.soloExactIndex` / `Scoring.applySoloExactBonus` (pure): the
  grade stays `exact_scoreline`, so accuracy, exact-call counts and every
  tie-break are unchanged; only the points move.
- `ScoreFixture` applies it over every prediction of the fixture once the
  result is in, by the stored kickoff (unknown kickoff: no bonus). A
  fixture that kicked off before 1 November keeps 3 and 6 however often it
  is scored again. A corrected result moves the bonus with the facts: the
  ledger's existing `correction` entries carry the difference. The monthly
  board, the season and the head-to-head rounds read the stored points, so
  the bonus counts there too.
- `GetLiveStanding` shows the same bonus on the running score (the
  composition root hands it the schedule repository for the kickoff).
- `NotifyFixtureWinners`: the double is named by the prediction
  (`doubled`), no longer guessed from 6 points, and the one alone reads
  «أصبت النتيجة بالضبط وحدك» (`solo`).
- App: the hero card is «بطاقة بطل اليوم للنخبة» and, on a double,
  «بطاقة البطل الاحترافي لليوم» (formerly البطل المميز لليوم); a single hero's
  card shows his points (`dayHero.points`); the share text reads «بطل اليوم
  للنخبة: … وحده أصاب مباراة ليفربول × أرسنال 2-2، وحصل على 6 نقاط.» and
  «البطل الاحترافي لليوم: … وحده أصاب نتيجة مباراة … مضاعفة كما انتهت
  بالضبط، وحصل على 9 نقاط.» (`DayHero.shareMessage`). The rules page and
  the sign-in rules list carry `rulesSoloExact`.
- Tests: `solo_exact_bonus_test.dart` (new), `scoring_ruleset_test.dart`,
  `get_live_standing_test.dart`, `notify_fixture_winners_test.dart`
  (through `ScoreFixture` too), `fixture_prediction_scoring_test.dart`
  (`POST /fixtures/{id}/score` over the production ruleset: 6, 9, two
  exact calls, a kickoff a minute before 1 November), `day_hero_test.dart`,
  `rules_screen_test.dart`.
- The head-to-head league needs no change for 1 November: `DrawH2hMonth`
  draws November as the first public month (`is_pilot` false), seeded
  from October's active players even though October was the pilot.

### The bar's brand mark drawn as a vector (script 160, 2026-10-27)

Asked by the owner on 2026-10-27 with a screenshot of the bar: a better
look for the five tabs and for the small Nukhbaa mark on them. Mobile
only; the bar stays as script 158 left it (no band, the fade, the middle
item inside the bar, the order and indexes).

- `core/ui/brand_mark.dart` (new): `BrandMark` paints the logo's shapes
  (the N, the nun's bowl, the dot) from `nukhbaa_logo.png`'s 512 px canvas
  as paths, in its blue tile (`kBrandMarkBlue`, picked from the picture)
  or alone. The 512 px picture scaled to 12 px read as a blurred square.
- Side tabs (`_NavGlyph`): outlined icon while closed, filled in a soft
  blue pill while open; the mark is an 11 px tile at the same top corner
  of every icon (the left in Arabic), cut out by a ring of what is behind
  it, instead of a picture laid over the icon at a different place each.
- Middle tab (`_NavBrand`, key `nav.brand`): a 44 px blue disc carrying
  the white mark, in place of the ball with the picture on it; open, its
  rim lights and it glows. The underline under the open tab stays.
- Test: `bottom_nav_order_test.dart` (every tab wears a `BrandMark`, no
  `Image`; the side marks share size and top; no ball), with the
  survey's text x2 checks unchanged.

## 3. Version-Verification Log

Per ADR 0007 §8: every external version/API verified against current source
before code is built on it.

**Flutter App phase (verified 2026-07-14, against pub.dev):** `apps/mobile` is
the first Flutter/UI code in the project; every UI/state/codegen library was
version-checked at pub.dev on the date above before a line was written (§4
constraint), and each is compatible with the ratified Flutter pin **3.44.0**
(`.fvmrc`) / Dart `^3.9.0` floor:
| Component | Version/Fact |
|---|---|
| Flutter SDK pin | `3.44.0` (unchanged, `.fvmrc`) — bundles a Dart `>=3.9` SDK, above the workspace floor |
| `flutter_riverpod` | `3.3.2` — env `sdk: ^3.7.0`, `flutter: >=3.0.0` (both satisfied). The ratified state-management choice (§4 decision #3); the 3.x stable line |
| `riverpod_annotation` | `4.0.3` — the annotation surface (`@riverpod`) for the generator-based style (§4 decision #3) |
| `riverpod_generator` | `4.0.4` — `build_runner` code generator producing the `*.g.dart` provider glue |
| `riverpod_lint` | `3.1.4` — the analyzer plugin (via `custom_lint`) that enforces Riverpod best-practices |
| `custom_lint` | `0.8.1` — host for `riverpod_lint`'s analyzer rules |
| `build_runner` | `2.15.2` — runs the Riverpod generator (`dart run build_runner build`) |
| `flutter_secure_storage` | `10.3.1` — persists the Supabase access token off the widget tree (Auth decision; keychain/keystore on mobile, WebCrypto-backed on web) |
| `flutter_lints` | `^6.0.0` — the Flutter analyzer ruleset, matching the workspace `lints ^6.0.0` |

**Design note (Flutter App):** `apps/mobile` performs **no HTTP itself** — all
networking is the already-ratified `packages/api_client` (which pins
`http ^1.6.0`, §3 above), consumed read-only per the `mobile ->
{api_client, contracts, shared}` boundary registered in `tooling/import_lint`.
So the app introduces no HTTP/serialization dependency of its own; it adds only
the Flutter UI + Riverpod state + secure-storage libraries listed here. Because
the sandbox has no Flutter toolchain (§2 Environment note), `flutter pub get` /
`dart run build_runner build` / `flutter analyze` / `flutter test` are to be run
on a machine with Flutter `3.44.0`; verification here is by-construction against
these confirmed versions and the exact `api_client`/`contracts`/`shared` public
surfaces.

> **Note (2026-10-17, audit NUKHBA-011):** still true in effect: `apps/mobile`
> sends no request itself. It names `package:http` in two files, both only
> to hand an `http.Client` to `api_client`'s transport:
> `lib/core/network/http_client.dart` creates it and
> `lib/core/auth/session_refresher.dart` takes it as a parameter.

**Milestone 0 (verified 2026-07-08):**
| Component | Version/Fact |
|---|---|
| Dart SDK floor | `^3.9.0` |
| Melos | `^8.0.0` (config under `melos:` key, native pub workspaces) |
| Dart Frog | `1.2.6` (SDK `>=3.0.0 <4.0.0`) |
| `postgres` | `3.5.12` — `Pool.withEndpoints(List<Endpoint>, {PoolSettings?})`, `SslMode` |
| `lints` | `^6.0.0` |
| `test` | `^1.26.0` |
| Flutter pin | `3.44.0` via `.fvmrc` |

**Notifications phase (verified 2026-07-12):** Introduces **NO new external
dependency** (decision #2 — v1 is in-app-only; no push/email provider, so no
new SDK/API to version). Domain (`packages/domain/notification/*`) is pure Dart
— imports only `shared` + domain-internal (`identity` `UserId`, `competition`
`RoundId`, `group` `GroupId`); reuses `test ^1.26.0`. Contracts/application add
none. Infrastructure reuses `postgres 3.5.12` (the confirmed `Sql.named` binding
+ `ServerException.code`/`.constraintName` SQLSTATE surface for the adapter's
23503/23505 mapping; recipient-scoped reads + an `ON CONFLICT DO NOTHING`
idempotent create — no new driver surface beyond what Ledger/Social already
use). `apps/server` reuses `dart_frog 1.2.6` + `mocktail`. No new internal
package → `tooling/import_lint` ruleset unchanged (the `notification` slice lives
inside the existing `domain`/`application`/`contracts`/`infrastructure` packages;
`application → {domain, shared}`, `infrastructure → {application, domain,
shared}` — already permitted). Migration `0009_notification.sql` adds the ONE
`notification.notifications` table + a `notification.notification_kind` enum only
(no group ref on any competition/round/prediction/leaderboard object — decision
#1/#3; no points column — Axiom 5).

**Social phase (verified 2026-07-12):** Introduces **NO new external
dependency**. Domain (`packages/domain/social/*`) is pure Dart — imports only
`shared` + domain-internal (`group` `GroupId`, `competition` `RoundId`,
`identity` `UserId`); reuses `test ^1.26.0`. Contracts/application add none.
Infrastructure reuses `postgres 3.5.12` (the confirmed `Sql.named` binding +
`ServerException.code`/`.constraintName` SQLSTATE surface for the reaction
adapter's 23503/23505 mapping; the Activity Feed reader is a read-only projection
over existing `group`/`competition`/`ledger`/`leaderboard` surfaces — no new
VIEW/points source). `apps/server` reuses `dart_frog 1.2.6` + `mocktail`. No new
internal package → `tooling/import_lint` ruleset unchanged (the `social` slice
lives inside the existing `domain`/`application`/`contracts`/`infrastructure`
packages; `application → {domain, shared}`, `infrastructure → {application,
domain, shared}` — already permitted). Migration `0008_social.sql` adds the
`social.reactions` table + a `social.reaction_kind` enum only (the Activity Feed
needs NO table — pure projection, decision #2; no group ref on any core object —
decision #1).

**Groups phase (verified 2026-07-11):** Introduces **NO new external
dependency**. Domain (`packages/domain/group/*`) is pure Dart — imports only
`shared` + domain-internal (`identity` `UserId`); reuses `test ^1.26.0`.
Contracts/application add none (the new `InviteCodeGenerator` port + the
`UuidInviteCodeGenerator` adapter use only `dart:math`'s `Random.secure()` from
the Dart SDK — no package). Infrastructure reuses `postgres 3.5.12` (the
confirmed `Sql.named` binding + `ServerException.code`/`.constraintName`
SQLSTATE surface; the group leaderboard read reuses the existing
`leaderboard.season_standings` VIEW intersected with group membership — no new
VIEW/points source). `apps/server` reuses `dart_frog 1.2.6` + `mocktail`. No new
internal package → `tooling/import_lint` ruleset unchanged (the `group` slice
lives inside the existing `domain`/`application`/`contracts`/`infrastructure`
packages; `application → {domain, shared}`, `infrastructure → {application,
domain, shared}` — already permitted). Migration `0007_group.sql` adds group +
membership tables + a `group.group_role` enum only (no group ref on any
competition/round/prediction/leaderboard object — decision #1).

**Leaderboards phase (verified 2026-07-11):** Introduces **NO new external
dependency**. Domain (`packages/domain/leaderboard/*`) is pure Dart — imports
only `shared` + domain-internal (`competition` ids); reuses `test ^1.26.0`.
Contracts/application add none. Infrastructure reuses `postgres 3.5.12`
(read-only `SELECT … SUM(amount) … GROUP BY` over a season-scoped join of
`ledger.point_entries` → `competition.participants`/`rounds`; `Sql.named`
binding + `ResultRow.toColumnMap()` surface already in use). `apps/server`
reuses `dart_frog 1.2.6` + `mocktail`. No new internal package →
`tooling/import_lint` ruleset unchanged (the `leaderboard` slice lives inside
the existing `domain`/`application`/`contracts`/`infrastructure` packages;
`application → {domain, shared}`, `infrastructure → {application, domain,
shared}` — already permitted). Migration `0006_leaderboard.sql` adds a read VIEW
+ index only (no new writable table, no second points source — §2 decision).

**Ledger phase (verified 2026-07-11):** Introduces **NO new external
dependency**. Domain layer (`packages/domain/ledger/*`) is pure Dart, imports
only `shared` + domain-internal (`competition` ids) types; reuses `test ^1.26.0`.
Application/contracts add no dependency. Infrastructure reuses `postgres 3.5.12`
(incl. `PostgresConnection.runInTransaction` for the atomic append + the already
-confirmed `Sql.named` binding / `ServerException.code`/`.constraintName`
SQLSTATE surface); `apps/server` reuses `dart_frog 1.2.6` + `mocktail`. No new
internal package appears, so `tooling/import_lint` ruleset is unchanged
(the append-only `PostgresLedgerRepository` lives inside `infrastructure`,
imports `application`/`domain`/`shared` — already permitted).

**Scoring phase (verified 2026-07-11):** Domain layer introduces NO new external
dependency — `packages/domain/scoring/*` is pure Dart, imports only `shared` +
domain-internal (`competition`/`prediction`) types; reuses the confirmed
`test ^1.26.0` for domain tests. Remaining Scoring layers (contracts/application/
infrastructure/migration/server) are expected to reuse `postgres 3.5.12` (incl.
`PostgresConnection.runInTransaction`) and `dart_frog 1.2.6` — verify at build.

**Prediction Engine phase (verified 2026-07-10):** No new external dependency
introduced — reuses `postgres 3.5.12` (infra) and the 6 existing internal
packages; Prediction lives inside `domain`/`application`/`contracts`/`infrastructure`.
Infra adapter (2026-07-11) reuses the confirmed `postgres 3.5.x` surface already
in use by the competition adapter: `PostgresConnection.query` (Sql.named binding,
toColumnMap rows), `ServerException.code`/`.constraintName` for SQLSTATE mapping.
`apps/server` Prediction routes (2026-07-11) introduce no new dependency — reuse
`dart_frog 1.2.6` (routing/`RequestContext`/`Response.json`), `mocktail` (already
in the route-test harness), and the 6 internal packages.
Phase-exit review (2026-07-11) verified one further use of the already-pinned
`postgres 3.5.x` — transactions: `Session.runTx<R>(Future<R> Function(TxSession))`
commits on normal return / rolls back on throw; `Pool` implements `Session`;
`TxSession.execute(Sql.named(...), parameters:)` + `ResultRow.toColumnMap()`. No
new external dependency; used by `PostgresConnection.runInTransaction`.

**Authentication phase (verified 2026-07-09):**
| Component | Version/Fact |
|---|---|
| `dart_jsonwebtoken` | `2.17.0` — `JWT.verify(token, JWTKey, {Audience?, issuer, subject, Duration})`; `JWTKey.fromJWK(Map)`; typed exceptions `JWTExpiredException`/`JWTInvalidException`/`JWTException`; constant-time HMAC; `Audience` handles multiple entries |
| Supabase JWT default | Since 2025-10-01 all new projects use **asymmetric ES256** by default; legacy projects may still use shared-secret HS256 |
| Supabase JWKS endpoint | `GET https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`; Edge-cached 10 min; old key kept ≥20 min on rotation |
| Supabase JWT claims | `iss`=`https://<ref>.supabase.co/auth/v1`; `sub`=user UUID; `role`; `aud`(`authenticated`); `exp`; `email`; `phone` |
| HS256 fallback | Local verification supported for shared-secret legacy projects |
| `http` (JWKS fetch) | `^1.2.0` |

**Design decision:** Supabase JWT verification done **locally** in the
backend — primary asymmetric ES256 via JWKS (cached ≤10 min, refresh on
unknown `kid`), fallback shared-secret HS256 for legacy projects. Asserts
signature, `exp`, `nbf`, `iss`, `aud`. Satisfies Security ADR §2 and Platform
ADR §3.

**Review-time finding (2026-07-09, Authentication six-way review):**
`dart_jsonwebtoken` 2.17.0 `JWT.verify` **derives `alg` from the token header**
and applies it against the supplied key — it does NOT let the caller pin an
expected algorithm. Therefore the **server** must gate `alg` itself. Fixed by a
server-owned allow-list `AuthConfig.acceptedAlgorithms = {ES256, HS256}` (+
`allowsAlgorithm`, HS256 gated on a configured legacy secret); the verifier
rejects any non-allow-listed `alg` (incl. `none`) **before** touching key
material — mitigating algorithm-confusion / `alg`-substitution (CWE-347).
`checkHeaderType`/`checkExpiresIn`/`checkNotBefore` pinned explicitly on
`JWT.verify`. See `docs/reviews/authentication-review.md` §2 (S-1, S-2).

---

## 4. Build Verification Gate

### النتيجة النهائية

| الخطوة | الحالة |
|---|---|
| 1-3 | ✅ مؤكدة سابقًا |
| 4 `dart analyze` | ✅ No issues found |
| 5 `flutter test` / `dart test` | ✅ All tests passed |
| 6 `flutter build web` | ✅ Built successfully |
| 7 `flutter build apk` | 🔴 BLOCKED — Android SDK غير موجود في Codespaces |
| 8 `flutter build ios` | ⬜ SKIPPED — يتطلب macOS/Xcode |

**الحكم:** بوابة §4 مكتملة. فشل Android ليس فشلًا في المشروع، وإنما قيد في
بيئة التحقق الحالية. لا تُعاد فتح المراحل الـ12 بسبب ذلك.

لا تضف أي تبعية أو تعدّل المعمارية بسبب هذا القيد.

## 5. Execution & Resume Rules

- Treat this file as the only project memory; do not regenerate ratified ADRs
  or re-derive architecture already decided in §1.
- Resume: read this file top to bottom, then continue exactly from §4.
- Never regenerate completed work; never redesign architecture; never restart
  a completed phase/milestone.
- Production-ready code only — no TODOs, no placeholders, no mocks.
- Complete one file before moving to the next; maintain CI compatibility.
- Before context runs low: save all generated files, update §2 and §4 in this
  file, then stop with "Checkpoint Saved."
