#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# 1) admin_providers.dart — RoundOpenController / RoundFixtureLinkController
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
/// 3), and round administration — open a round + link a fixture into it (over
/// `CompetitionApi` — `POST /seasons/{id}/rounds` / `POST /rounds/{id}/fixtures`).
/// Lock/score/ledger-post administration is a separate follow-up slice,
/// mirroring how Groups was phased in this project.
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
NUKHBAA_EOF

# 2) admin_dashboard_screen.dart — Rounds tab
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
      length: 5,
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
NUKHBAA_EOF

# 3) test harness — competitionApiProvider override + fixtures
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
NUKHBAA_EOF

echo "Part 2 (admin providers + screen + test harness) written."

# Regenerate + verify
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
dart format .
melos run import-lint || true
flutter analyze
flutter test
