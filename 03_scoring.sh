#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# 1) packages/api_client — recordFixtureResult / scoreRound / getRoundScores
cat > packages/api_client/lib/src/competition_api.dart << 'NUKHBAA_EOF'
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
}
NUKHBAA_EOF

# 2) admin_providers.dart — RecordFixtureResultController / ScoreRoundController / RoundScoresLookupController
cat > apps/mobile/lib/features/admin/admin_providers.dart << 'NUKHBAA_EOF'
/// The Admin Panel **view** state (audit log) plus the sanction commands
/// (suspend/reinstate) and the narrow cross-user ledger support-read.
///
/// Admin-only, enforced entirely server-side (Security ADR §2.2/§2.3) — this
/// file makes no authorization decision; `AdminApi` surfaces a non-admin
/// refusal as a typed `AppError` like any other failure.
///
/// **Scope (this pass):** audit trail, user suspend/reinstate, the
/// single-participant ledger support-read (all three over `AdminApi`),
/// fixture-identity register/correct (over `FixtureScheduleApi` —
/// `POST /fixtures` / `PUT /fixtures/{id}`, the fixture-IDENTITY seam, Axiom
/// 3), round administration — open a round + link a fixture into it, and
/// results/scoring administration — record a fixture's actual result, score
/// a round, and look up a scored round's results (all over `CompetitionApi`
/// — `POST /seasons/{id}/rounds` / `POST /rounds/{id}/fixtures` /
/// `PUT /fixtures/{id}/result` / `POST /rounds/{id}/score` /
/// `GET /rounds/{id}/scores`). Ledger-post administration is a separate
/// follow-up slice, mirroring how Groups was phased in this project.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'admin_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /admin/audit` — the append-only audit trail, newest first.
@riverpod
Future<AuditLogDto> auditLog(Ref ref) async {
  final api = ref.watch(adminApiProvider);
  return _unwrap(await api.listAuditLog());
}

/// Owns the suspend/reinstate sanction commands. On success it invalidates
/// [auditLogProvider] so the trail reflects the new entry.
@riverpod
class UserSanctionController extends _$UserSanctionController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<UserSanctionResultDto>? build() => null;

  /// Suspends [userId] with the mandatory [reason].
  Future<void> suspend(String userId, String reason) async {
    state = const AsyncValue.loading();
    final result = await _api.suspendUser(userId, reason);
    _applyAndRefresh(result);
  }

  /// Reinstates [userId] with the mandatory [reason].
  Future<void> reinstate(String userId, String reason) async {
    state = const AsyncValue.loading();
    final result = await _api.reinstateUser(userId, reason);
    _applyAndRefresh(result);
  }

  void _applyAndRefresh(Result<UserSanctionResultDto> result) {
    state = switch (result) {
      Ok<UserSanctionResultDto>(:final value) => AsyncValue.data(value),
      Err<UserSanctionResultDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<UserSanctionResultDto>) {
      ref.invalidate(auditLogProvider);
    }
  }
}

/// Owns the narrow cross-user ledger support-read
/// (`GET /admin/participants/{id}/ledger`). Modelled as a controller (rather
/// than a `FutureProvider`) because the read is itself an audited *action*
/// (Admin Panel decision OPEN-A #3) an admin explicitly triggers, not a
/// passive view an admin screen loads on entry.
@riverpod
class AdminLedgerLookupController extends _$AdminLedgerLookupController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<ParticipantEntriesDto>? build() => null;

  /// Looks up [participantId]'s ledger, optionally recording [reason] on the
  /// mandatory audit entry.
  Future<void> lookup(String participantId, {String? reason}) async {
    state = const AsyncValue.loading();
    final result = await _api.viewParticipantLedger(
      participantId,
      reason: reason,
    );
    state = switch (result) {
      Ok<ParticipantEntriesDto>(:final value) => AsyncValue.data(value),
      Err<ParticipantEntriesDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the fixture-identity register/correct commands
/// (`POST /fixtures` / `PUT /fixtures/{id}`) — the fixture-IDENTITY seam
/// (Axiom 3; Next-Task decision 2026-07-11, option (a)). Modelled as a
/// controller, not a `FutureProvider`, for the same reason as
/// [UserSanctionController]: a one-shot admin command, not a passive view an
/// admin screen loads on entry. No other provider reads a fixture's schedule
/// today, so a success here has nothing to invalidate.
@riverpod
class FixtureScheduleController extends _$FixtureScheduleController {
  FixtureScheduleApi get _api => ref.read(fixtureScheduleApiProvider);

  @override
  AsyncValue<FixtureScheduleDto>? build() => null;

  /// Registers a brand-new fixture's identity. The server generates the
  /// fixture id; it comes back on [FixtureScheduleDto.fixtureId] for the
  /// admin to note down (e.g. for a later [correct] call or to link it into
  /// a round).
  Future<void> register({
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.registerFixtureSchedule(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    _apply(result);
  }

  /// Corrects an already-registered fixture's identity by [fixtureId] (a
  /// mistyped team name or kickoff time, before the round is linked/locked).
  Future<void> correct({
    required String fixtureId,
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.correctFixtureSchedule(
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    _apply(result);
  }

  void _apply(Result<FixtureScheduleDto> result) {
    state = switch (result) {
      Ok<FixtureScheduleDto>(:final value) => AsyncValue.data(value),
      Err<FixtureScheduleDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the open-round command (`POST /seasons/{id}/rounds`, command intent
/// `OpenRound`) over `CompetitionApi`. Modelled as a controller, not a
/// `FutureProvider`, for the same reason as [UserSanctionController]: a
/// one-shot admin command, not a passive view an admin screen loads on entry.
@riverpod
class RoundOpenController extends _$RoundOpenController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundDto>? build() => null;

  /// Opens round [sequence] in season [seasonId] with [predictionDeadline]
  /// (an ISO 8601 timestamp string; the server normalizes it to UTC).
  Future<void> open({
    required String seasonId,
    required int sequence,
    required String predictionDeadline,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.openRound(
      seasonId: seasonId,
      sequence: sequence,
      predictionDeadline: predictionDeadline,
    );
    state = switch (result) {
      Ok<RoundDto>(:final value) => AsyncValue.data(value),
      Err<RoundDto>(:final error) => AsyncValue.error(error, StackTrace.current),
    };
  }
}

/// Owns the link-fixture-to-round command (`POST /rounds/{id}/fixtures`,
/// command intent `LinkFixtureToRound`; Axiom 3) over `CompetitionApi`.
/// Modelled as a controller for the same reason as [RoundOpenController].
@riverpod
class RoundFixtureLinkController extends _$RoundFixtureLinkController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundFixtureDto>? build() => null;

  /// Links [fixtureId] into [roundId] at [displayOrder] (0-based).
  Future<void> link({
    required String roundId,
    required String fixtureId,
    required int displayOrder,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.linkFixtureToRound(
      roundId: roundId,
      fixtureId: fixtureId,
      displayOrder: displayOrder,
    );
    state = switch (result) {
      Ok<RoundFixtureDto>(:final value) => AsyncValue.data(value),
      Err<RoundFixtureDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the record-fixture-result command (`PUT /fixtures/{id}/result`,
/// command intent `RecordFixtureResult`; Axiom 3) over `CompetitionApi`.
/// Modelled as a controller for the same reason as [RoundOpenController].
@riverpod
class RecordFixtureResultController
    extends _$RecordFixtureResultController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<FixtureResultDto>? build() => null;

  /// Records fixture [fixtureId]'s actual final score.
  Future<void> record({
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.recordFixtureResult(
      fixtureId: fixtureId,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
    );
    state = switch (result) {
      Ok<FixtureResultDto>(:final value) => AsyncValue.data(value),
      Err<FixtureResultDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the score-round command (`POST /rounds/{id}/score`, command intent
/// `ScoreRound`) over `CompetitionApi`. Modelled as a controller for the same
/// reason as [RoundOpenController]. No request body — points are computed
/// server-side (Axioms 2/5).
@riverpod
class ScoreRoundController extends _$ScoreRoundController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundScoresDto>? build() => null;

  /// Scores every prediction in [roundId].
  Future<void> score(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.scoreRound(roundId);
    state = switch (result) {
      Ok<RoundScoresDto>(:final value) => AsyncValue.data(value),
      Err<RoundScoresDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the round-scores lookup (`GET /rounds/{id}/scores`, query intent
/// `GetRoundScores`) over `CompetitionApi`. Modelled as a controller (rather
/// than a `FutureProvider`) for the same reason as
/// [AdminLedgerLookupController]: an admin explicitly triggers this read, it
/// is not a passive view a screen loads on entry.
@riverpod
class RoundScoresLookupController extends _$RoundScoresLookupController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundScoresDto>? build() => null;

  /// Looks up [roundId]'s computed scores.
  Future<void> lookup(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.getRoundScores(roundId);
    state = switch (result) {
      Ok<RoundScoresDto>(:final value) => AsyncValue.data(value),
      Err<RoundScoresDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}
NUKHBAA_EOF

# 3) admin_dashboard_screen.dart — Results & Scoring tab
cat > apps/mobile/lib/features/admin/admin_dashboard_screen.dart << 'NUKHBAA_EOF'
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'admin_providers.dart';

/// The admin dashboard. Gated by the caller's platform role — a route pushing
/// this screen must first check `AuthenticatedUserDto.role == 'admin'`
/// (`AccountScreen` does this before offering the entry point); the true
/// authority gate is still server-side inside every `AdminApi` call.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminDashboard, key: const Key('admin.title')),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(
                key: const Key('admin.tab.audit'),
                text: l10n.adminAuditLogTab,
              ),
              Tab(key: const Key('admin.tab.users'), text: l10n.adminUsersTab),
              Tab(
                key: const Key('admin.tab.ledger'),
                text: l10n.adminLedgerLookupTab,
              ),
              Tab(
                key: const Key('admin.tab.fixtures'),
                text: l10n.adminFixturesTab,
              ),
              Tab(
                key: const Key('admin.tab.rounds'),
                text: l10n.adminRoundsTab,
              ),
              Tab(
                key: const Key('admin.tab.scoring'),
                text: l10n.adminScoringTab,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _AuditLogTab(),
            _UserSanctionTab(),
            _LedgerLookupTab(),
            _FixtureScheduleTab(),
            _RoundAdministrationTab(),
            _ResultsScoringTab(),
          ],
        ),
      ),
    );
  }
}

class _AuditLogTab extends ConsumerWidget {
  const _AuditLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AuditLogDto> log = ref.watch(auditLogProvider);
    return AsyncListView<AuditEntryDto>(
      value: log.whenData((dto) => dto.entries),
      emptyMessage: l10n.adminAuditLogEmpty,
      onRetry: () => ref.invalidate(auditLogProvider),
      itemBuilder: (context, entry) => ListTile(
        key: Key('admin.audit.item.${entry.id}'),
        title: Text(entry.action, key: Key('admin.audit.action.${entry.id}')),
        subtitle: Text(
          '${entry.targetRef}${entry.reason != null ? ' — ${entry.reason}' : ''}',
          key: Key('admin.audit.detail.${entry.id}'),
        ),
        trailing: Text(
          entry.occurredAt,
          key: Key('admin.audit.occurredAt.${entry.id}'),
          style: TextStyle(color: context.tokens.textSecondary),
        ),
      ),
    );
  }
}

class _UserSanctionTab extends ConsumerStatefulWidget {
  const _UserSanctionTab();

  @override
  ConsumerState<_UserSanctionTab> createState() => _UserSanctionTabState();
}

class _UserSanctionTabState extends ConsumerState<_UserSanctionTab> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<UserSanctionResultDto>? state = ref.watch(
      userSanctionControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('admin.users.userIdField'),
            controller: _userIdController,
            decoration: InputDecoration(
              labelText: l10n.userId,
              border: const OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.users.reasonField'),
            controller: _reasonController,
            decoration: InputDecoration(
              labelText: l10n.adminReasonMandatoryLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state is AsyncError<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(state.error as AppError),
                key: const Key('admin.users.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (state is AsyncData<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${state.value.userId} is now ${state.value.status}',
                key: const Key('admin.users.result'),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('admin.users.suspend'),
                  onPressed: inFlight ? null : () => _act(suspend: true),
                  child: Text(l10n.adminSuspendButton),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  key: const Key('admin.users.reinstate'),
                  onPressed: inFlight ? null : () => _act(suspend: false),
                  child: Text(l10n.adminReinstateButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _act({required bool suspend}) {
    final userId = _userIdController.text.trim();
    final reason = _reasonController.text.trim();
    if (userId.isEmpty || reason.isEmpty) return;
    final notifier = ref.read(userSanctionControllerProvider.notifier);
    if (suspend) {
      notifier.suspend(userId, reason);
    } else {
      notifier.reinstate(userId, reason);
    }
  }
}

class _LedgerLookupTab extends ConsumerStatefulWidget {
  const _LedgerLookupTab();

  @override
  ConsumerState<_LedgerLookupTab> createState() => _LedgerLookupTabState();
}

class _LedgerLookupTabState extends ConsumerState<_LedgerLookupTab> {
  final TextEditingController _participantIdController =
      TextEditingController();

  @override
  void dispose() {
    _participantIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<ParticipantEntriesDto>? state = ref.watch(
      adminLedgerLookupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<ParticipantEntriesDto>;
    final AppTokens tokens = context.tokens;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('admin.ledger.participantIdField'),
                  controller: _participantIdController,
                  decoration: InputDecoration(
                    labelText: l10n.adminParticipantIdLabel,
                    border: const OutlineInputBorder(),
                  ),
                  enabled: !inFlight,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                key: const Key('admin.ledger.lookup'),
                onPressed: inFlight
                    ? null
                    : () {
                        final id = _participantIdController.text.trim();
                        if (id.isEmpty) return;
                        ref
                            .read(adminLedgerLookupControllerProvider.notifier)
                            .lookup(id);
                      },
                child: Text(l10n.adminLookUpButton),
              ),
            ],
          ),
        ),
        if (state is AsyncLoading<ParticipantEntriesDto>)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: CircularProgressIndicator(),
          ),
        if (state is AsyncError<ParticipantEntriesDto>)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              ErrorPresenter.message(state.error as AppError),
              key: const Key('admin.ledger.error'),
              style: TextStyle(color: tokens.error),
            ),
          ),
        if (state is AsyncData<ParticipantEntriesDto>)
          Expanded(
            child: ListView.separated(
              key: const Key('admin.ledger.list'),
              itemCount: state.value.entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = state.value.entries[index];
                return ListTile(
                  key: Key('admin.ledger.item.${entry.id}'),
                  title: Text(
                    entry.kind,
                    key: Key('admin.ledger.kind.${entry.id}'),
                  ),
                  subtitle: Text(
                    entry.occurredAt,
                    key: Key('admin.ledger.occurredAt.${entry.id}'),
                  ),
                  trailing: Text(
                    '${entry.amount}',
                    key: Key('admin.ledger.amount.${entry.id}'),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FixtureScheduleTab extends ConsumerStatefulWidget {
  const _FixtureScheduleTab();

  @override
  ConsumerState<_FixtureScheduleTab> createState() =>
      _FixtureScheduleTabState();
}

class _FixtureScheduleTabState extends ConsumerState<_FixtureScheduleTab> {
  final TextEditingController _fixtureIdController = TextEditingController();
  final TextEditingController _homeTeamController = TextEditingController();
  final TextEditingController _awayTeamController = TextEditingController();
  DateTime? _kickoffLocal;

  @override
  void dispose() {
    _fixtureIdController.dispose();
    _homeTeamController.dispose();
    _awayTeamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<FixtureScheduleDto>? state = ref.watch(
      fixtureScheduleControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<FixtureScheduleDto>;
    final AppTokens tokens = context.tokens;
    final bool hasFixtureId = _fixtureIdController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('admin.fixtures.fixtureIdField'),
            controller: _fixtureIdController,
            decoration: InputDecoration(
              labelText: l10n.adminFixtureIdOptionalLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !inFlight,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.fixtures.homeTeamField'),
            controller: _homeTeamController,
            decoration: InputDecoration(
              labelText: l10n.adminHomeTeamLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.fixtures.awayTeamField'),
            controller: _awayTeamController,
            decoration: InputDecoration(
              labelText: l10n.adminAwayTeamLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const Key('admin.fixtures.kickoffPicker'),
            onPressed: inFlight ? null : _pickKickoff,
            child: Text(
              _kickoffLocal == null
                  ? l10n.adminPickKickoffButton
                  : _formatKickoff(_kickoffLocal!),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state is AsyncError<FixtureScheduleDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(state.error as AppError),
                key: const Key('admin.fixtures.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (state is AsyncData<FixtureScheduleDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${state.value.fixtureId}: ${state.value.homeTeam} vs '
                '${state.value.awayTeam}',
                key: const Key('admin.fixtures.result'),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('admin.fixtures.register'),
                  onPressed: inFlight || hasFixtureId ? null : _register,
                  child: Text(l10n.adminRegisterFixtureButton),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton(
                  key: const Key('admin.fixtures.correct'),
                  onPressed: inFlight || !hasFixtureId ? null : _correct,
                  child: Text(l10n.adminCorrectFixtureButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickKickoff() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffLocal ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _kickoffLocal == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_kickoffLocal!),
    );
    if (time == null) return;
    setState(() {
      _kickoffLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _register() {
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (homeTeam.isEmpty || awayTeam.isEmpty || kickoff == null) return;
    ref
        .read(fixtureScheduleControllerProvider.notifier)
        .register(
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
        );
  }

  void _correct() {
    final fixtureId = _fixtureIdController.text.trim();
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (fixtureId.isEmpty ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(fixtureScheduleControllerProvider.notifier)
        .correct(
          fixtureId: fixtureId,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
        );
  }

  String _formatKickoff(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Round administration: open a round in a season (freezing the ruleset),
/// then link an already-registered fixture into it. Two independent
/// commands over `CompetitionApi` (`RoundOpenController` /
/// `RoundFixtureLinkController`), each with its own in-flight/result/error
/// state — mirrors [_FixtureScheduleTab]'s two-command layout.
class _RoundAdministrationTab extends ConsumerStatefulWidget {
  const _RoundAdministrationTab();

  @override
  ConsumerState<_RoundAdministrationTab> createState() =>
      _RoundAdministrationTabState();
}

class _RoundAdministrationTabState
    extends ConsumerState<_RoundAdministrationTab> {
  final TextEditingController _seasonIdController = TextEditingController();
  final TextEditingController _sequenceController = TextEditingController();
  DateTime? _deadlineLocal;

  final TextEditingController _roundIdController = TextEditingController();
  final TextEditingController _fixtureIdController = TextEditingController();
  final TextEditingController _displayOrderController =
      TextEditingController();

  @override
  void dispose() {
    _seasonIdController.dispose();
    _sequenceController.dispose();
    _roundIdController.dispose();
    _fixtureIdController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final AsyncValue<RoundDto>? openState = ref.watch(
      roundOpenControllerProvider,
    );
    final AsyncValue<RoundFixtureDto>? linkState = ref.watch(
      roundFixtureLinkControllerProvider,
    );
    final bool openInFlight = openState is AsyncLoading<RoundDto>;
    final bool linkInFlight = linkState is AsyncLoading<RoundFixtureDto>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.adminOpenRoundSectionTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.rounds.seasonIdField'),
            controller: _seasonIdController,
            decoration: InputDecoration(
              labelText: l10n.adminSeasonIdLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !openInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.rounds.sequenceField'),
            controller: _sequenceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.adminSequenceLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !openInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const Key('admin.rounds.deadlinePicker'),
            onPressed: openInFlight ? null : _pickDeadline,
            child: Text(
              _deadlineLocal == null
                  ? l10n.adminPickDeadlineButton
                  : _formatInstant(_deadlineLocal!),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (openState is AsyncError<RoundDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(openState.error as AppError),
                key: const Key('admin.rounds.open.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (openState is AsyncData<RoundDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${openState.value.id} (#${openState.value.sequence}, '
                '${openState.value.status})',
                key: const Key('admin.rounds.open.result'),
              ),
            ),
          FilledButton(
            key: const Key('admin.rounds.open'),
            onPressed: openInFlight ? null : _openRound,
            child: Text(l10n.adminOpenRoundButton),
          ),
          const Divider(height: AppSpacing.x3l),
          Text(l10n.adminLinkFixtureSectionTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.rounds.roundIdField'),
            controller: _roundIdController,
            decoration: InputDecoration(
              labelText: l10n.adminRoundIdLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !linkInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.rounds.fixtureIdField'),
            controller: _fixtureIdController,
            decoration: InputDecoration(
              labelText: l10n.adminFixtureIdLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !linkInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.rounds.displayOrderField'),
            controller: _displayOrderController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.adminDisplayOrderLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !linkInFlight,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (linkState is AsyncError<RoundFixtureDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(linkState.error as AppError),
                key: const Key('admin.rounds.link.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (linkState is AsyncData<RoundFixtureDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${linkState.value.fixtureId} -> ${linkState.value.roundId} '
                '(#${linkState.value.displayOrder})',
                key: const Key('admin.rounds.link.result'),
              ),
            ),
          FilledButton(
            key: const Key('admin.rounds.link'),
            onPressed: linkInFlight ? null : _linkFixture,
            child: Text(l10n.adminLinkFixtureButton),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadlineLocal ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _deadlineLocal == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_deadlineLocal!),
    );
    if (time == null) return;
    setState(() {
      _deadlineLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _openRound() {
    final seasonId = _seasonIdController.text.trim();
    final sequence = int.tryParse(_sequenceController.text.trim());
    final deadline = _deadlineLocal;
    if (seasonId.isEmpty || sequence == null || deadline == null) return;
    ref
        .read(roundOpenControllerProvider.notifier)
        .open(
          seasonId: seasonId,
          sequence: sequence,
          predictionDeadline: deadline.toUtc().toIso8601String(),
        );
  }

  void _linkFixture() {
    final roundId = _roundIdController.text.trim();
    final fixtureId = _fixtureIdController.text.trim();
    final displayOrder = int.tryParse(_displayOrderController.text.trim());
    if (roundId.isEmpty || fixtureId.isEmpty || displayOrder == null) return;
    ref
        .read(roundFixtureLinkControllerProvider.notifier)
        .link(roundId: roundId, fixtureId: fixtureId, displayOrder: displayOrder);
  }

  String _formatInstant(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Results/scoring administration: record a fixture's actual final score,
/// then score a round (server computes points from the frozen ruleset), and
/// look up an already-scored round's participant results. Three independent
/// commands/reads over `CompetitionApi` (`RecordFixtureResultController` /
/// `ScoreRoundController` / `RoundScoresLookupController`), each with its own
/// in-flight/result/error state — mirrors [_RoundAdministrationTab]'s
/// multi-command layout.
class _ResultsScoringTab extends ConsumerStatefulWidget {
  const _ResultsScoringTab();

  @override
  ConsumerState<_ResultsScoringTab> createState() =>
      _ResultsScoringTabState();
}

class _ResultsScoringTabState extends ConsumerState<_ResultsScoringTab> {
  final TextEditingController _fixtureIdController = TextEditingController();
  final TextEditingController _homeGoalsController = TextEditingController();
  final TextEditingController _awayGoalsController = TextEditingController();

  final TextEditingController _roundIdController = TextEditingController();

  @override
  void dispose() {
    _fixtureIdController.dispose();
    _homeGoalsController.dispose();
    _awayGoalsController.dispose();
    _roundIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final AsyncValue<FixtureResultDto>? resultState = ref.watch(
      recordFixtureResultControllerProvider,
    );
    final AsyncValue<RoundScoresDto>? scoreState = ref.watch(
      scoreRoundControllerProvider,
    );
    final AsyncValue<RoundScoresDto>? lookupState = ref.watch(
      roundScoresLookupControllerProvider,
    );
    final bool resultInFlight =
        resultState is AsyncLoading<FixtureResultDto>;
    final bool scoreInFlight = scoreState is AsyncLoading<RoundScoresDto>;
    final bool lookupInFlight = lookupState is AsyncLoading<RoundScoresDto>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.adminRecordResultSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.scoring.fixtureIdField'),
            controller: _fixtureIdController,
            decoration: InputDecoration(
              labelText: l10n.adminFixtureIdLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !resultInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.scoring.homeGoalsField'),
            controller: _homeGoalsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.adminHomeGoalsLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !resultInFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.scoring.awayGoalsField'),
            controller: _awayGoalsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.adminAwayGoalsLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !resultInFlight,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (resultState is AsyncError<FixtureResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(resultState.error as AppError),
                key: const Key('admin.scoring.result.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (resultState is AsyncData<FixtureResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${resultState.value.fixtureId}: '
                '${resultState.value.homeGoals}-${resultState.value.awayGoals}',
                key: const Key('admin.scoring.result.result'),
              ),
            ),
          FilledButton(
            key: const Key('admin.scoring.recordResult'),
            onPressed: resultInFlight ? null : _recordResult,
            child: Text(l10n.adminRecordResultButton),
          ),
          const Divider(height: AppSpacing.x3l),
          Text(
            l10n.adminScoreRoundSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('admin.scoring.roundIdField'),
            controller: _roundIdController,
            decoration: InputDecoration(
              labelText: l10n.adminRoundIdLabel,
              border: const OutlineInputBorder(),
            ),
            enabled: !scoreInFlight && !lookupInFlight,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (scoreState is AsyncError<RoundScoresDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(scoreState.error as AppError),
                key: const Key('admin.scoring.score.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          FilledButton(
            key: const Key('admin.scoring.scoreRound'),
            onPressed: scoreInFlight ? null : _scoreRound,
            child: Text(l10n.adminScoreRoundButton),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.adminRoundScoresSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (lookupState is AsyncError<RoundScoresDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(lookupState.error as AppError),
                key: const Key('admin.scoring.lookup.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          OutlinedButton(
            key: const Key('admin.scoring.lookupScores'),
            onPressed: lookupInFlight ? null : _lookupScores,
            child: Text(l10n.adminViewScoresButton),
          ),
          const SizedBox(height: AppSpacing.md),
          if (lookupState is AsyncData<RoundScoresDto>)
            for (final s in lookupState.value.scores)
              ListTile(
                key: Key(
                  'admin.scoring.lookup.score.${lookupState.value.roundId}.${s.participantId}',
                ),
                title: Text(s.participantId),
                trailing: Text('${l10n.adminTotalPointsLabel}: ${s.totalPoints}'),
              )
          else if (scoreState is AsyncData<RoundScoresDto>)
            for (final s in scoreState.value.scores)
              ListTile(
                key: Key(
                  'admin.scoring.score.score.${scoreState.value.roundId}.${s.participantId}',
                ),
                title: Text(s.participantId),
                trailing: Text('${l10n.adminTotalPointsLabel}: ${s.totalPoints}'),
              ),
        ],
      ),
    );
  }

  void _recordResult() {
    final fixtureId = _fixtureIdController.text.trim();
    final homeGoals = int.tryParse(_homeGoalsController.text.trim());
    final awayGoals = int.tryParse(_awayGoalsController.text.trim());
    if (fixtureId.isEmpty || homeGoals == null || awayGoals == null) return;
    ref
        .read(recordFixtureResultControllerProvider.notifier)
        .record(fixtureId: fixtureId, homeGoals: homeGoals, awayGoals: awayGoals);
  }

  void _scoreRound() {
    final roundId = _roundIdController.text.trim();
    if (roundId.isEmpty) return;
    ref.read(scoreRoundControllerProvider.notifier).score(roundId);
  }

  void _lookupScores() {
    final roundId = _roundIdController.text.trim();
    if (roundId.isEmpty) return;
    ref.read(roundScoresLookupControllerProvider.notifier).lookup(roundId);
  }
}
NUKHBAA_EOF

# 4) test harness — scoring DTO fixtures
cat > apps/mobile/test/support/admin_harness.dart << 'NUKHBAA_EOF'
/// Test harness for the Admin Panel slice.
///
/// Mirrors `prediction_harness.dart`: it builds a `ProviderScope` whose
/// networking is served entirely by a `package:http/testing.dart` [MockClient]
/// (no live socket), wiring the shared `apiTransportProvider` over that client
/// so the real `adminApiProvider`, `fixtureScheduleApiProvider`, and
/// `competitionApiProvider` (the screen's five controllers/reads) exercise the
/// genuine `api_client` end-to-end — only the socket is faked. The token store
/// is a seedable in-memory fake so the transport still attaches a bearer token
/// exactly as production does.
///
/// A test supplies a [handler] that returns a canned response per request (or
/// throws to simulate a transport failure). Because the Admin dashboard issues
/// several distinct reads/writes (`GET /admin/audit`,
/// `POST /admin/users/{id}/suspend`, `POST /admin/users/{id}/reinstate`,
/// `GET /admin/participants/{id}/ledger`, `POST /fixtures`,
/// `PUT /fixtures/{id}`, `POST /seasons/{id}/rounds`,
/// `POST /rounds/{id}/fixtures`), the handler is expected to branch on
/// `request.method` + `request.url.path`. Response builders
/// ([okJsonObject]/[errorEnvelope]) and DTO fixtures are provided.
library;

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/token_store.dart';
import 'package:mobile/core/providers.dart';

/// One captured outbound request (for asserting method + path + body).
final class CapturedRequest {
  /// Wraps a captured [http.Request].
  CapturedRequest(this.request);

  /// The raw captured request.
  final http.Request request;
}

/// The pieces a test needs to drive and inspect the Admin slice.
final class AdminHarness {
  /// Creates a harness over its [container] and [captured] list.
  AdminHarness({required this.container, required this.captured});

  /// The Riverpod container backing the overridden providers.
  final ProviderContainer container;

  /// Every request the [MockClient] saw, in order.
  final List<CapturedRequest> captured;

  /// `ProviderScope` overrides for widget tests.
  List<Override> get overrides => _overrides;

  late final List<Override> _overrides;

  /// Disposes the container (call in `addTearDown`).
  void dispose() => container.dispose();
}

/// Builds an [AdminHarness]. The [handler] decides each canned response (or
/// throws to simulate a transport failure).
AdminHarness buildAdminHarness(
  Future<http.Response> Function(http.Request request) handler,
) {
  final captured = <CapturedRequest>[];
  final client = MockClient((request) async {
    captured.add(CapturedRequest(request));
    return handler(request);
  });

  final overrides = <Override>[
    // A fixed token store so the transport attaches a bearer token like prod.
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore('admin-jwt')),
    apiTransportProvider.overrideWith(
      (ref) => ApiTransport(
        baseUri: Uri.parse('https://api.test.example/'),
        httpClient: client,
        tokenProvider: ref.watch(tokenStoreProvider).read,
        // No real HTTP ever happens here (MockClient) — disable the timeout
        // so a test that intentionally never resolves its handler (to assert
        // a loading state) doesn't leave a real Timer pending at teardown.
        requestTimeout: null,
      ),
    ),
    // The real Admin + FixtureSchedule clients over the faked transport (the
    // providers/controllers/screen under test are NOT overridden).
    adminApiProvider.overrideWith(
      (ref) => AdminApi(ref.watch(apiTransportProvider)),
    ),
    fixtureScheduleApiProvider.overrideWith(
      (ref) => FixtureScheduleApi(ref.watch(apiTransportProvider)),
    ),
    competitionApiProvider.overrideWith(
      (ref) => CompetitionApi(ref.watch(apiTransportProvider)),
    ),
  ];

  final container = ProviderContainer(
    overrides: overrides,
    retry: (retryCount, error) => null,
  );
  final harness = AdminHarness(container: container, captured: captured);
  harness._overrides = overrides;
  return harness;
}

/// A `200 OK` JSON-object response (a single-item read or a command result).
http.Response okJsonObject(Map<String, Object?> object) => http.Response(
  jsonEncode(object),
  200,
  headers: const {'content-type': 'application/json'},
);

/// A non-2xx response carrying the server's versioned error envelope.
http.Response errorEnvelope(int status, String code, String message) =>
    http.Response(
      jsonEncode({'schema_version': 1, 'code': code, 'message': message}),
      status,
      headers: const {'content-type': 'application/json'},
    );

// ---------------------------------------------------------------------------
// DTO fixtures (the exact wire shapes the admin routes return).
// ---------------------------------------------------------------------------

/// An empty audit trail (legitimate empty — `GET /admin/audit`).
const AuditLogDto emptyAuditLog = AuditLogDto(entries: <AuditEntryDto>[]);

/// Two audit entries, newest-first.
const AuditLogDto twoAuditEntries = AuditLogDto(
  entries: <AuditEntryDto>[
    AuditEntryDto(
      id: 'audit-2',
      actorId: 'admin-1',
      action: 'user_suspended',
      targetRef: 'user-9',
      reason: 'ابتزاز داخل الدردشة',
      occurredAt: '2026-08-07T12:00:00.000Z',
    ),
    AuditEntryDto(
      id: 'audit-1',
      actorId: 'admin-1',
      action: 'fixture_registered',
      targetRef: 'fixture-1',
      occurredAt: '2026-08-06T09:00:00.000Z',
    ),
  ],
);

/// The result of suspending `user-9`.
const UserSanctionResultDto suspendedResult = UserSanctionResultDto(
  userId: 'user-9',
  status: 'suspended',
);

/// The result of reinstating `user-9`.
const UserSanctionResultDto reinstatedResult = UserSanctionResultDto(
  userId: 'user-9',
  status: 'active',
);

/// A single participant's ledger with one entry.
const ParticipantEntriesDto oneLedgerEntry = ParticipantEntriesDto(
  participantId: 'part-1',
  entries: <PointEntryDto>[
    PointEntryDto(
      id: 'entry-1',
      participantId: 'part-1',
      roundId: 'r-1',
      kind: 'round_score',
      amount: 9,
      sourceRef: 'round-r-1',
      occurredAt: '2026-08-01T10:00:00.000Z',
    ),
  ],
);

/// A freshly registered fixture (`POST /fixtures` response).
const FixtureScheduleDto registeredFixture = FixtureScheduleDto(
  fixtureId: 'f-new',
  homeTeam: 'Al Hilal',
  awayTeam: 'Al Nassr',
  kickoffAt: '2026-08-20T18:00:00.000Z',
);

/// A freshly opened round (`POST /seasons/{id}/rounds` response).
const RoundDto openedRound = RoundDto(
  id: 'round-new',
  seasonId: 'season-1',
  sequence: 3,
  predictionDeadline: '2026-08-25T18:00:00.000Z',
  status: 'open',
  rulesetVersion: 1,
);

/// A freshly linked round-fixture (`POST /rounds/{id}/fixtures` response).
const RoundFixtureDto linkedRoundFixture = RoundFixtureDto(
  roundId: 'round-new',
  fixtureId: 'f-new',
  displayOrder: 0,
);

/// A freshly recorded fixture result (`PUT /fixtures/{id}/result` response).
const FixtureResultDto recordedFixtureResult = FixtureResultDto(
  fixtureId: 'f-new',
  homeGoals: 2,
  awayGoals: 1,
);

/// A scored round with one participant (`POST /rounds/{id}/score` and
/// `GET /rounds/{id}/scores` share this exact shape).
const RoundScoresDto oneRoundScore = RoundScoresDto(
  roundId: 'round-new',
  scores: <RoundScoreDto>[
    RoundScoreDto(
      roundId: 'round-new',
      participantId: 'part-1',
      rulesetVersion: 1,
      totalPoints: 9,
      fixtureResults: <FixtureScoreResultDto>[
        FixtureScoreResultDto(
          fixtureId: 'f-new',
          grade: 'exact_scoreline',
          points: 9,
        ),
      ],
    ),
  ],
);
NUKHBAA_EOF

# 5) l10n source (ar/en)
cat > apps/mobile/lib/l10n/app_ar.arb << 'NUKHBAA_EOF'
{
  "@@locale": "ar",
  "appTitle": "نُخبة",
  "signIn": "تسجيل الدخول",
  "signOut": "تسجيل الخروج",
  "loading": "جارٍ التحميل…",
  "error": "حدث خطأ ما",
  "retry": "إعادة المحاولة",
  "showPassword": "إظهار كلمة المرور",
  "hidePassword": "إخفاء كلمة المرور",
  "markNotificationRead": "تعليم كمقروءة",
  "createAccount": "إنشاء حساب",
  "signInSubtitle": "سجّل الدخول بالبريد الإلكتروني وكلمة المرور للمتابعة.",
  "signUpSubtitle": "أنشئ حساباً لتبدأ اللعب في نُخبة.",
  "email": "البريد الإلكتروني",
  "emailHint": "you@example.com",
  "emailRequired": "الرجاء إدخال بريدك الإلكتروني.",
  "password": "كلمة المرور",
  "passwordRequired": "الرجاء إدخال كلمة المرور.",
  "toggleToSignIn": "لديك حساب بالفعل؟ سجّل الدخول",
  "toggleToRegister": "جديد هنا؟ أنشئ حساباً",
  "tagline": "منصة توقعات كرة القدم",
  "authTabSignIn": "دخول",
  "authTabRegister": "تسجيل",
  "confirmPassword": "تأكيد كلمة المرور",
  "confirmPasswordRequired": "الرجاء تأكيد كلمة المرور.",
  "passwordMismatch": "كلمتا المرور غير متطابقتين.",
  "rulesTitle": "كيف تلعب؟",
  "rulesTagline": "توقع، نافس، تصدّر، كن من النخبة",
  "rulesPredictMajorLeagues": "توقع مباريات الدوريات الكبرى",
  "rulesCorrectPrediction": "التوقع الصحيح: 3 نقاط",
  "rulesWrongPrediction": "التوقع الخاطئ: 0 نقطة",
  "rulesDoubleMatch": "المباراة المختارة كدبل: 6 نقاط",
  "notifications": "الإشعارات",
  "signedIn": "تم تسجيل الدخول",
  "userId": "معرّف المستخدم",
  "role": "الدور",
  "status": "الحالة",
  "browseCompetitions": "تصفح البطولات",
  "hallOfFame": "قاعة المشاهير",
  "myPredictions": "توقعاتي",
  "createGroup": "إنشاء مجموعة",
  "joinGroup": "الانضمام إلى مجموعة",
  "adminDashboard": "لوحة تحكم المشرف",
  "hallOfFameEmpty": "لم يحصل أحد على أي نقاط بعد.",
  "hallOfFameSeasonsPlayed": "{count, plural, zero{لم يشارك في أي موسم} one{شارك في موسم واحد} two{شارك في موسمين} few{شارك في {count} مواسم} many{شارك في {count} موسمًا} other{شارك في {count} موسم}}",
  "competitionSeasonsEmpty": "لا توجد مواسم لهذه البطولة بعد.",
  "leaderboardTitle": "{label} — لوحة الصدارة",
  "seasonLeaderboardEmpty": "لم ينضم أحد لهذا الموسم بعد.",
  "leaderboardEntriesCounted": "{count, plural, zero{لا توجد مشاركات محتسبة} one{مشاركة واحدة محتسبة} two{مشاركتان محتسبتان} few{{count} مشاركات محتسبة} many{{count} مشاركة محتسبة} other{{count} مشاركة محتسبة}}",
  "pointsAbbreviated": "{count, plural, zero{0 نقطة} one{نقطة واحدة} two{نقطتان} few{{count} نقاط} many{{count} نقطة} other{{count} نقطة}}",
  "groupLeaderboardEmpty": "لم ينضم أي عضو من هذه المجموعة للموسم بعد.",
  "competitions": "المسابقات",
  "competitionsEmpty": "لا توجد مسابقات للتصفح حتى الآن.",
  "visibilityPublic": "عام",
  "visibilityPrivate": "خاص",
  "predictionHistoryEmpty": "لم تقدّم أي توقعات بعد.",
  "predictionHistoryScoreLine": "{fixtureId}: {homeGoals} - {awayGoals}",
  "groupFeedTitle": "نشاط {groupName}",
  "groupFeedEmpty": "لا يوجد نشاط بعد.",
  "activityRoundScored": "تم احتساب نتيجة الجولة",
  "activityMemberJoined": "انضم عضو جديد",
  "activityRankShift": "انتقل من المركز #{oldRank} إلى #{newRank}",
  "activityRankShiftUnknown": "تغيّر الترتيب",
  "seasonRoundsTitle": "{seasonLabel} — الجولات",
  "viewLeaderboardTooltip": "عرض لوحة الصدارة",
  "seasonRoundsEmpty": "لا توجد جولات لهذا الموسم بعد.",
  "roundItemTitle": "الجولة {sequence}",
  "roundDeadlineLine": "{statusLabel} · الموعد النهائي {deadline}",
  "roundStatusOpen": "مفتوحة للتوقعات",
  "roundStatusLocked": "مغلقة",
  "roundStatusScored": "محتسبة",
  "roundFixturesTitle": "الجولة",
  "roundRulesLine": "{statusLabel} · القواعد إصدار {rulesetVersion}",
  "predictRoundButton": "توقع نتائج هذه الجولة",
  "roundFixturesEmpty": "لا توجد مباريات لهذه الجولة بعد.",
  "fixtureItemTitle": "المباراة {fixtureId}",
  "fixtureVsTitle": "{home} ضد {away}",
  "predictionTitle": "التوقّع",
  "predictionClosedMessage": "هذه الجولة {status}. التوقعات مغلقة.",
  "genericErrorMessage": "حدث خطأ ما. يُرجى المحاولة مرة أخرى.",
  "tryAgainButton": "حاول مرة أخرى",
  "predictionAlreadySubmitted": "لقد أرسلت توقعاً لهذه الجولة مسبقاً. التعديل والإرسال مرة أخرى سيحدّثه.",
  "predictionSaved": "تم حفظ توقعك.",
  "submitPredictionButton": "إرسال التوقع",
  "predictionDoubleLabel": "الدبل",
  "predictionFixtureLockedLabel": "بدأت المباراة",
  "predictionDoubleHint": "اختر مباراة واحدة كدبل قبل الإرسال.",
  "predictionIncompleteHint": "أدخل نتيجة كل مباراة مفتوحة قبل الإرسال.",
  "predictionNoOpenFixturesMessage": "كل مباريات هذه الجولة بدأت بالفعل. لا يوجد ما يمكن توقّعه الآن.",
  "adminAuditLogTab": "سجل التدقيق",
  "adminUsersTab": "المستخدمون",
  "adminLedgerLookupTab": "البحث في السجل المالي",
  "adminAuditLogEmpty": "لا توجد إدخالات تدقيق بعد.",
  "adminReasonMandatoryLabel": "السبب (إلزامي)",
  "adminSuspendButton": "تعليق",
  "adminReinstateButton": "إعادة تفعيل",
  "adminParticipantIdLabel": "معرّف المشارك",
  "adminLookUpButton": "بحث",
  "adminFixturesTab": "هوية المباراة",
  "adminFixtureIdOptionalLabel": "معرّف المباراة (للتصحيح فقط، اتركه فارغاً للتسجيل)",
  "adminHomeTeamLabel": "الفريق المضيف",
  "adminAwayTeamLabel": "الفريق الضيف",
  "adminPickKickoffButton": "اختر موعد المباراة",
  "adminRegisterFixtureButton": "تسجيل مباراة جديدة",
  "adminCorrectFixtureButton": "تصحيح المباراة",
  "adminRoundsTab": "الجولات",
  "adminOpenRoundSectionTitle": "فتح جولة جديدة",
  "adminSeasonIdLabel": "معرّف الموسم",
  "adminSequenceLabel": "رقم الجولة",
  "adminPickDeadlineButton": "اختر موعد إغلاق التوقعات",
  "adminOpenRoundButton": "فتح الجولة",
  "adminLinkFixtureSectionTitle": "ربط مباراة بجولة",
  "adminRoundIdLabel": "معرّف الجولة",
  "adminFixtureIdLabel": "معرّف المباراة",
  "adminDisplayOrderLabel": "ترتيب العرض",
  "adminLinkFixtureButton": "ربط المباراة بالجولة",
  "adminScoringTab": "النتائج والاحتساب",
  "adminRecordResultSectionTitle": "تسجيل نتيجة مباراة",
  "adminHomeGoalsLabel": "أهداف المضيف",
  "adminAwayGoalsLabel": "أهداف الضيف",
  "adminRecordResultButton": "تسجيل النتيجة",
  "adminScoreRoundSectionTitle": "احتساب نقاط الجولة",
  "adminScoreRoundButton": "احتساب الجولة",
  "adminRoundScoresSectionTitle": "نتائج المشاركين بالجولة",
  "adminViewScoresButton": "عرض النتائج",
  "adminTotalPointsLabel": "مجموع النقاط",
  "createGroupTitle": "إنشاء مجموعة",
  "groupNameLabel": "اسم المجموعة",
  "createGroupButton": "إنشاء",
  "joinGroupTitle": "الانضمام إلى مجموعة",
  "inviteCodeLabel": "رمز الدعوة",
  "joinGroupButton": "انضمام",
  "ledgerTitle": "نقاطي",
  "ledgerEmpty": "لا توجد حركات نقاط بعد.",
  "ledgerEntryCount": "{count} حركة مسجّلة",
  "@ledgerEntryCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "notificationsTitle": "الإشعارات",
  "notificationsEmpty": "ليس لديك أي إشعارات بعد.",
  "notificationRoundScored": "تم تسجيل نتيجة جولة توقعتها",
  "notificationGroupMemberJoined": "انضم شخص إلى مجموعتك",
  "notificationReactionReceived": "تلقيت تفاعلاً",
  "notificationsMarkAsRead": "تمييز كمقروء"
}
NUKHBAA_EOF

cat > apps/mobile/lib/l10n/app_en.arb << 'NUKHBAA_EOF'
{
  "@@locale": "en",
  "appTitle": "Nukhba",
  "@appTitle": {
    "description": "Application title"
  },
  "signIn": "Sign in",
  "signOut": "Sign out",
  "loading": "Loading…",
  "error": "Something went wrong",
  "retry": "Retry",
  "showPassword": "Show password",
  "hidePassword": "Hide password",
  "markNotificationRead": "Mark as read",
  "createAccount": "Create account",
  "signInSubtitle": "Sign in with your email and password to continue.",
  "signUpSubtitle": "Create an account to start playing Nukhba.",
  "email": "Email",
  "emailHint": "you@example.com",
  "emailRequired": "Please enter your email.",
  "password": "Password",
  "passwordRequired": "Please enter your password.",
  "toggleToSignIn": "Already have an account? Sign in",
  "toggleToRegister": "New here? Create an account",
  "tagline": "Football prediction platform",
  "authTabSignIn": "Sign in",
  "authTabRegister": "Register",
  "confirmPassword": "Confirm password",
  "confirmPasswordRequired": "Please confirm your password.",
  "passwordMismatch": "Passwords do not match.",
  "rulesTitle": "How to play?",
  "rulesTagline": "Predict, compete, top the table, be Nukhba.",
  "rulesPredictMajorLeagues": "Predict matches from the major leagues",
  "rulesCorrectPrediction": "Correct prediction: 3 points",
  "rulesWrongPrediction": "Wrong prediction: 0 points",
  "rulesDoubleMatch": "Match picked as double: 6 points",
  "notifications": "Notifications",
  "signedIn": "Signed in",
  "userId": "User ID",
  "role": "Role",
  "status": "Status",
  "browseCompetitions": "Browse competitions",
  "hallOfFame": "Hall of Fame",
  "myPredictions": "My Predictions",
  "createGroup": "Create a group",
  "joinGroup": "Join a group",
  "adminDashboard": "Admin dashboard",
  "hallOfFameEmpty": "Nobody has earned any points yet.",
  "hallOfFameSeasonsPlayed": "{count, plural, =0{No seasons played} =1{1 season played} other{{count} seasons played}}",
  "@hallOfFameSeasonsPlayed": {
    "description": "Number of seasons a user has played, shown on the Hall of Fame leaderboard row.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "competitionSeasonsEmpty": "This competition has no seasons yet.",
  "leaderboardTitle": "{label} — Leaderboard",
  "@leaderboardTitle": {
    "description": "Title of the season leaderboard screen.",
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "seasonLeaderboardEmpty": "No one has joined this season yet.",
  "leaderboardEntriesCounted": "{count, plural, =0{No entries counted} =1{1 entry counted} other{{count} entries counted}}",
  "@leaderboardEntriesCounted": {
    "description": "Number of prediction entries counted toward a participant's leaderboard score.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "pointsAbbreviated": "{count, plural, =0{0 pts} =1{1 pt} other{{count} pts}}",
  "@pointsAbbreviated": {
    "description": "Abbreviated points total, shown on leaderboard rows (e.g. Hall of Fame, season leaderboard).",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "groupLeaderboardEmpty": "No members of this group have joined the season yet.",
  "competitions": "Competitions",
  "competitionsEmpty": "There are no competitions to browse yet.",
  "visibilityPublic": "Public",
  "visibilityPrivate": "Private",
  "predictionHistoryEmpty": "You have not submitted any predictions yet.",
  "predictionHistoryScoreLine": "{fixtureId}: {homeGoals} - {awayGoals}",
  "@predictionHistoryScoreLine": {
    "description": "One fixture's predicted scoreline within a submitted prediction history row.",
    "placeholders": {
      "fixtureId": {
        "type": "String"
      },
      "homeGoals": {
        "type": "int"
      },
      "awayGoals": {
        "type": "int"
      }
    }
  },
  "groupFeedTitle": "{groupName} Feed",
  "@groupFeedTitle": {
    "description": "App bar title for a group's activity feed screen.",
    "placeholders": {
      "groupName": {
        "type": "String"
      }
    }
  },
  "groupFeedEmpty": "No activity yet.",
  "activityRoundScored": "Round scored",
  "activityMemberJoined": "New member joined",
  "activityRankShift": "Moved from #{oldRank} to #{newRank}",
  "@activityRankShift": {
    "description": "Describes a member's rank change in the group activity feed.",
    "placeholders": {
      "oldRank": {
        "type": "int"
      },
      "newRank": {
        "type": "int"
      }
    }
  },
  "activityRankShiftUnknown": "Rank changed",
  "seasonRoundsTitle": "{seasonLabel} — Rounds",
  "@seasonRoundsTitle": {
    "description": "App bar title for the season rounds browse screen.",
    "placeholders": {
      "seasonLabel": {
        "type": "String"
      }
    }
  },
  "viewLeaderboardTooltip": "View leaderboard",
  "@viewLeaderboardTooltip": {
    "description": "Tooltip for the app bar action that navigates to the season leaderboard."
  },
  "seasonRoundsEmpty": "This season has no rounds yet.",
  "@seasonRoundsEmpty": {
    "description": "Empty state message when a season has no rounds."
  },
  "roundItemTitle": "Round {sequence}",
  "@roundItemTitle": {
    "description": "Title of a round list item, showing its 1-based sequence number.",
    "placeholders": {
      "sequence": {
        "type": "int"
      }
    }
  },
  "roundDeadlineLine": "{statusLabel} · Deadline {deadline}",
  "@roundDeadlineLine": {
    "description": "Subtitle of a round list item combining its humanised status and formatted prediction deadline.",
    "placeholders": {
      "statusLabel": {
        "type": "String"
      },
      "deadline": {
        "type": "String"
      }
    }
  },
  "roundStatusOpen": "Open for predictions",
  "@roundStatusOpen": {
    "description": "Humanised label for a round in the open lifecycle status."
  },
  "roundStatusLocked": "Locked",
  "@roundStatusLocked": {
    "description": "Humanised label for a round in the locked lifecycle status."
  },
  "roundStatusScored": "Scored",
  "@roundStatusScored": {
    "description": "Humanised label for a round in the scored lifecycle status."
  },
  "roundFixturesTitle": "Round",
  "roundRulesLine": "{statusLabel} · Rules v{rulesetVersion}",
  "@roundRulesLine": {
    "description": "Round header status line combining the humanised status and the ruleset version applied to this round.",
    "placeholders": {
      "statusLabel": {
        "type": "String"
      },
      "rulesetVersion": {
        "type": "int"
      }
    }
  },
  "predictRoundButton": "Predict this round",
  "roundFixturesEmpty": "This round has no fixtures yet.",
  "fixtureItemTitle": "Fixture {fixtureId}",
  "@fixtureItemTitle": {
    "description": "Title of a fixture list item, showing its stable fixture id.",
    "placeholders": {
      "fixtureId": {
        "type": "String"
      }
    }
  },
  "fixtureVsTitle": "{home} vs {away}",
  "@fixtureVsTitle": {
    "description": "Title of a fixture list item when its schedule identity is known.",
    "placeholders": {
      "home": {
        "type": "String"
      },
      "away": {
        "type": "String"
      }
    }
  },
  "predictionTitle": "Predict",
  "@predictionTitle": {
    "description": "App bar title on the prediction submit/amend screen."
  },
  "predictionClosedMessage": "This round is {status}. Predictions are closed.",
  "@predictionClosedMessage": {
    "description": "Shown when a round is not open for predictions; status is the lowercase lifecycle label.",
    "placeholders": {
      "status": {
        "type": "String"
      }
    }
  },
  "genericErrorMessage": "Something went wrong. Please try again.",
  "@genericErrorMessage": {
    "description": "Fallback error message for an untyped/unexpected client error."
  },
  "tryAgainButton": "Try again",
  "@tryAgainButton": {
    "description": "Retry button label on a form error state."
  },
  "predictionAlreadySubmitted": "You have already submitted a prediction for this round. Editing and submitting again will update it.",
  "@predictionAlreadySubmitted": {
    "description": "Banner shown when the caller already has a stored prediction for this round."
  },
  "predictionSaved": "Your prediction was saved.",
  "@predictionSaved": {
    "description": "Success banner after a prediction submit/amend succeeds."
  },
  "submitPredictionButton": "Submit prediction",
  "@submitPredictionButton": {
    "description": "Label on the prediction submit button."
  },
  "predictionDoubleLabel": "Double",
  "@predictionDoubleLabel": {
    "description": "Tooltip/semantic label on the per-fixture double-selection star."
  },
  "predictionFixtureLockedLabel": "Started",
  "@predictionFixtureLockedLabel": {
    "description": "Small label under a fixture that has already kicked off and can no longer be edited."
  },
  "predictionDoubleHint": "Select exactly one open fixture as your double before submitting.",
  "@predictionDoubleHint": {
    "description": "Shown when every open fixture has a score but no double is selected yet."
  },
  "predictionIncompleteHint": "Enter a score for every open fixture before submitting.",
  "@predictionIncompleteHint": {
    "description": "Shown while at least one open fixture is missing a valid score."
  },
  "predictionNoOpenFixturesMessage": "Every fixture in this round has already kicked off. There is nothing left to predict.",
  "@predictionNoOpenFixturesMessage": {
    "description": "Shown instead of the form when every fixture in the round has already locked."
  },
  "adminAuditLogTab": "Audit Log",
  "adminUsersTab": "Users",
  "adminLedgerLookupTab": "Ledger Lookup",
  "adminAuditLogEmpty": "No audit entries yet.",
  "adminReasonMandatoryLabel": "Reason (mandatory)",
  "adminSuspendButton": "Suspend",
  "adminReinstateButton": "Reinstate",
  "adminParticipantIdLabel": "Participant ID",
  "adminLookUpButton": "Look up",
  "adminFixturesTab": "Fixture Identity",
  "adminFixtureIdOptionalLabel": "Fixture ID (correction only — leave empty to register)",
  "adminHomeTeamLabel": "Home team",
  "adminAwayTeamLabel": "Away team",
  "adminPickKickoffButton": "Pick kickoff time",
  "adminRegisterFixtureButton": "Register fixture",
  "adminCorrectFixtureButton": "Correct fixture",
  "adminRoundsTab": "Rounds",
  "adminOpenRoundSectionTitle": "Open a new round",
  "adminSeasonIdLabel": "Season ID",
  "adminSequenceLabel": "Round sequence",
  "adminPickDeadlineButton": "Pick prediction deadline",
  "adminOpenRoundButton": "Open round",
  "adminLinkFixtureSectionTitle": "Link a fixture to a round",
  "adminRoundIdLabel": "Round ID",
  "adminFixtureIdLabel": "Fixture ID",
  "adminDisplayOrderLabel": "Display order",
  "adminLinkFixtureButton": "Link fixture to round",
  "adminScoringTab": "Results & Scoring",
  "adminRecordResultSectionTitle": "Record fixture result",
  "adminHomeGoalsLabel": "Home goals",
  "adminAwayGoalsLabel": "Away goals",
  "adminRecordResultButton": "Record result",
  "adminScoreRoundSectionTitle": "Score round",
  "adminScoreRoundButton": "Score round",
  "adminRoundScoresSectionTitle": "Round participant scores",
  "adminViewScoresButton": "View scores",
  "adminTotalPointsLabel": "Total points",
  "createGroupTitle": "Create Group",
  "groupNameLabel": "Group name",
  "createGroupButton": "Create",
  "joinGroupTitle": "Join Group",
  "inviteCodeLabel": "Invite code",
  "joinGroupButton": "Join",
  "ledgerTitle": "My Points",
  "ledgerEmpty": "No points movements yet.",
  "ledgerEntryCount": "{count} movements counted",
  "@ledgerEntryCount": {
    "description": "Count of point movements shown below the balance on the ledger screen.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "notificationsTitle": "Notifications",
  "notificationsEmpty": "You have no notifications yet.",
  "notificationRoundScored": "A round you predicted was scored",
  "notificationGroupMemberJoined": "Someone joined your group",
  "notificationReactionReceived": "You received a reaction",
  "notificationsMarkAsRead": "Mark as read"
}
NUKHBAA_EOF

echo "Part 3 (results/scoring admin providers + screen + test harness) written."

# Regenerate + verify — MUST run from apps/mobile (pubspec.yaml with
# flutter: generate: true lives there, not at the repo root).
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
dart format .
cd ../..
melos run import-lint || true
flutter analyze
cd apps/mobile
flutter test
