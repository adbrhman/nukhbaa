library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'admin_providers.dart';
import 'round_report.dart';

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
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    ref
        .read(usersLookupControllerProvider.notifier)
        .search(_searchController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<UserSanctionResultDto>? state = ref.watch(
      userSanctionControllerProvider,
    );
    final AsyncValue<UserListDto>? search = ref.watch(
      usersLookupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;
    final bool searching = search is AsyncLoading<UserListDto>;
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('admin.users.searchField'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l10n.adminUsersSearchLabel,
                    border: const OutlineInputBorder(),
                  ),
                  enabled: !searching,
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                key: const Key('admin.users.searchButton'),
                onPressed: searching ? null : _search,
                child: Text(l10n.adminLookUpButton),
              ),
            ],
          ),
          if (search != null)
            SizedBox(
              height: 200,
              child: AsyncListView<UserSummaryDto>(
                value: search.whenData((dto) => dto.users),
                emptyMessage: l10n.adminUsersEmptyResults,
                onRetry: _search,
                itemBuilder: (context, user) => ListTile(
                  key: Key('admin.users.result.${user.id}'),
                  title: Text(user.email ?? user.id),
                  subtitle: Text(user.status),
                  onTap: () => setState(() => _userIdController.text = user.id),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
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
                l10n.adminSanctionResultMessage(
                  state.value.userId,
                  state.value.status,
                ),
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
  final TextEditingController _displayOrderController = TextEditingController();

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
          Text(
            l10n.adminOpenRoundSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
          Text(
            l10n.adminLinkFixtureSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
        .link(
          roundId: roundId,
          fixtureId: fixtureId,
          displayOrder: displayOrder,
        );
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
  ConsumerState<_ResultsScoringTab> createState() => _ResultsScoringTabState();
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
    final bool resultInFlight = resultState is AsyncLoading<FixtureResultDto>;
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
                trailing: Text(
                  '${l10n.adminTotalPointsLabel}: ${s.totalPoints}',
                ),
              )
          else if (scoreState is AsyncData<RoundScoresDto>)
            for (final s in scoreState.value.scores)
              ListTile(
                key: Key(
                  'admin.scoring.score.score.${scoreState.value.roundId}.${s.participantId}',
                ),
                title: Text(s.participantId),
                trailing: Text(
                  '${l10n.adminTotalPointsLabel}: ${s.totalPoints}',
                ),
              ),
          const Divider(height: AppSpacing.x3l),
          _RoundReportSection(roundIdController: _roundIdController),
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
        .record(
          fixtureId: fixtureId,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
        );
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

/// The round-report section inside [_ResultsScoringTab]: merges
/// `GET /rounds/{id}/scores` with the admin-only
/// `GET /admin/rounds/{id}/predictions` (via [RoundReportController]) into a
/// ranked, per-fixture table (rank, participant, total points, and every
/// fixture's grade + predicted scoreline), plus a copy-to-share summary.
///
/// Reuses the same round-id field as the score lookup above it — the report
/// is scoped to the same round an admin just scored.
class _RoundReportSection extends ConsumerWidget {
  const _RoundReportSection({required this.roundIdController});

  final TextEditingController roundIdController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final AsyncValue<List<RoundReportRow>>? reportState = ref.watch(
      roundReportControllerProvider,
    );
    final bool inFlight = reportState is AsyncLoading<List<RoundReportRow>>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.adminRoundReportSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportState is AsyncError<List<RoundReportRow>>)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              ErrorPresenter.message(reportState.error as AppError),
              key: const Key('admin.scoring.report.error'),
              style: TextStyle(color: tokens.error),
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('admin.scoring.viewReport'),
                onPressed: inFlight ? null : () => _load(ref),
                child: Text(l10n.adminViewRoundReportButton),
              ),
            ),
            if (reportState is AsyncData<List<RoundReportRow>> &&
                reportState.value.isNotEmpty) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                key: const Key('admin.scoring.report.share'),
                onPressed: () => _share(context, reportState.value),
                child: Text(l10n.adminRoundReportShareButton),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportState is AsyncData<List<RoundReportRow>>)
          if (reportState.value.isEmpty)
            Text(l10n.adminRoundReportEmpty)
          else
            for (final row in reportState.value)
              _RoundReportRowCard(row: row, tokens: tokens, l10n: l10n),
      ],
    );
  }

  void _load(WidgetRef ref) {
    final roundId = roundIdController.text.trim();
    if (roundId.isEmpty) return;
    ref.read(roundReportControllerProvider.notifier).load(roundId);
  }

  void _share(BuildContext context, List<RoundReportRow> rows) {
    final l10n = AppLocalizations.of(context);
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln('${row.rank}. ${row.participantId} — ${row.totalPoints}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.adminRoundReportCopiedMessage)));
  }
}

class _RoundReportRowCard extends StatelessWidget {
  const _RoundReportRowCard({
    required this.row,
    required this.tokens,
    required this.l10n,
  });

  final RoundReportRow row;
  final AppTokens tokens;
  final AppLocalizations l10n;

  Color? _rankColor() => switch (row.rank) {
    1 => tokens.gold,
    2 => tokens.silver,
    3 => tokens.bronze,
    _ => null,
  };

  static String _gradeIcon(String grade) => switch (grade) {
    'exact_scoreline' => '✅',
    'correct_outcome' => '🟡',
    'incorrect' => '❌',
    'missed' => '⏳',
    _ => '?',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('admin.scoring.report.row.${row.participantId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _rankColor() ?? tokens.surfaceHigh,
                  child: Text(
                    '${row.rank}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    row.participantId,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${l10n.adminTotalPointsLabel}: ${row.totalPoints}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final cell in row.cells)
                  Chip(
                    key: Key(
                      'admin.scoring.report.cell.${row.participantId}.${cell.fixtureId}',
                    ),
                    label: Text(
                      cell.hasRawScore
                          ? '${_gradeIcon(cell.grade)} '
                                '${cell.homeGoals}-${cell.awayGoals} '
                                '(${cell.points})${cell.isDouble ? ' x2' : ''}'
                          : '${_gradeIcon(cell.grade)} (${cell.points})',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
