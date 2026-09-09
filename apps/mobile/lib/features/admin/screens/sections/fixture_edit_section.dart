/// تعديل مباراة مسجّلة — شاشة مستقلة: الشهر ← المباراة ← الفريقان
/// والموعد، مع إمكانية إسناد دوري للمباراة التي بلا دوري.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/teams_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';
import '../../widgets/team_picker_field.dart';

/// شاشة تعديل مباراة مسجّلة.
///
/// كانت بطاقة أسفل شاشة الإضافة تشاركها منتقي المسابقة. صارت مستقلة
/// ومفتاحها الشهر لا المسابقة، تمامًا كشاشة الإضافة.
class FixtureEditSection extends ConsumerStatefulWidget {
  /// ينشئ القسم.
  const FixtureEditSection({super.key});

  @override
  ConsumerState<FixtureEditSection> createState() => _FixtureEditSectionState();
}

class _FixtureEditSectionState extends ConsumerState<FixtureEditSection> {
  final TextEditingController _homeTeamController = TextEditingController();
  final TextEditingController _awayTeamController = TextEditingController();
  final FocusNode _homeTeamFocusNode = FocusNode();
  final FocusNode _awayTeamFocusNode = FocusNode();

  String? _seasonId;
  String? _fixtureId;
  String? _homeTeamId;
  String? _awayTeamId;
  DateTime? _kickoffLocal;

  /// The league the admin picked, or `null` for "leave it as it is".
  ///
  /// Not prefilled, and deliberately so: the browse read carries the
  /// league's NAME but not its id, and the correction goes through an
  /// upsert that COALESCEs the league. Sending nothing therefore keeps
  /// whatever the row already has, while picking one overwrites it — which
  /// is how a fixture that migration 0035 could not recover a league for
  /// finally gets one.
  String? _leagueId;

  /// The league name shown on the selected fixture, for context only.
  String? _currentLeagueName;

  @override
  void dispose() {
    _homeTeamController.dispose();
    _awayTeamController.dispose();
    _homeTeamFocusNode.dispose();
    _awayTeamFocusNode.dispose();
    super.dispose();
  }

  /// The clubs to suggest: the chosen league's when one is picked,
  /// otherwise the whole catalog — an existing fixture's teams may well
  /// predate any league, and refusing to suggest them would make a name
  /// typo unfixable.
  Iterable<String> _teamOptions(
    String query, {
    required List<TeamDto> catalog,
  }) {
    final List<String> options = <String>[
      for (final TeamDto team in catalog)
        if (_leagueId == null || team.leagueId == _leagueId) team.name,
    ]..sort();
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return options;
    final String needle = trimmed.toLowerCase();
    return options.where((String t) => t.toLowerCase().contains(needle));
  }

  String? _resolveTeamId(List<TeamDto> catalog, String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    for (final TeamDto team in catalog) {
      if (_leagueId != null && team.leagueId != _leagueId) continue;
      if (team.name.toLowerCase() == trimmed.toLowerCase()) return team.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<TeamDto> catalog =
        ref.watch(teamCatalogProvider).value ?? const <TeamDto>[];
    final AsyncValue<FixtureScheduleDto>? state = ref.watch(
      fixtureScheduleControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<FixtureScheduleDto>;
    final bool canSubmit =
        !inFlight &&
        _seasonId != null &&
        _fixtureId != null &&
        _homeTeamController.text.trim().isNotEmpty &&
        _awayTeamController.text.trim().isNotEmpty &&
        _kickoffLocal != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminCorrectFixtureSectionTitle,
          subtitle: l10n.adminCorrectFixtureSubtitle,
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonthPickerField(
                key: const Key('admin.fixtureEdit.monthField'),
                enabled: !inFlight,
                selectedId: _seasonId,
                onSelected: (SeasonDto month) => setState(() {
                  _seasonId = month.id;
                  _fixtureId = null;
                  _homeTeamController.clear();
                  _awayTeamController.clear();
                  _homeTeamId = null;
                  _awayTeamId = null;
                  _kickoffLocal = null;
                  _leagueId = null;
                  _currentLeagueName = null;
                }),
              ),
              if (_seasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.fixtureEdit',
                  seasonId: _seasonId!,
                  enabled: !inFlight,
                  selectedId: _fixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {
                    _fixtureId = fixture.fixtureId;
                    _homeTeamController.text = fixture.homeTeam ?? '';
                    _awayTeamController.text = fixture.awayTeam ?? '';
                    _homeTeamId = fixture.homeTeamId;
                    _awayTeamId = fixture.awayTeamId;
                    _kickoffLocal = DateTime.tryParse(
                      fixture.kickoffAt ?? '',
                    )?.toLocal();
                    _currentLeagueName = fixture.leagueName;
                    _leagueId = null;
                  }),
                ),
              ],
              if (_fixtureId != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _currentLeagueName == null
                      ? l10n.adminFixtureNoLeagueLabel
                      : l10n.adminFixtureCurrentLeagueLabel(
                          _currentLeagueName!,
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                LeaguePickerField(
                  key: const Key('admin.fixtureEdit.leagueField'),
                  enabled: !inFlight,
                  selectedId: _leagueId,
                  onSelected: (LeagueDto league) => setState(() {
                    _leagueId = league.id;
                    _homeTeamId = _resolveTeamId(
                      catalog,
                      _homeTeamController.text,
                    );
                    _awayTeamId = _resolveTeamId(
                      catalog,
                      _awayTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                TeamPickerField(
                  fieldKey: const Key('admin.fixtureEdit.homeTeamField'),
                  controller: _homeTeamController,
                  focusNode: _homeTeamFocusNode,
                  label: l10n.adminHomeTeamLabel,
                  enabled: !inFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _teamOptions(q, catalog: catalog),
                  onChanged: () => setState(() {
                    _homeTeamId = _resolveTeamId(
                      catalog,
                      _homeTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                TeamPickerField(
                  fieldKey: const Key('admin.fixtureEdit.awayTeamField'),
                  controller: _awayTeamController,
                  focusNode: _awayTeamFocusNode,
                  label: l10n.adminAwayTeamLabel,
                  enabled: !inFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _teamOptions(q, catalog: catalog),
                  onChanged: () => setState(() {
                    _awayTeamId = _resolveTeamId(
                      catalog,
                      _awayTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                AdminSecondaryButton(
                  key: const Key('admin.fixtureEdit.kickoffPicker'),
                  label: _kickoffLocal == null
                      ? l10n.adminPickKickoffButton
                      : _formatKickoff(_kickoffLocal!),
                  icon: Icons.event_outlined,
                  onPressed: inFlight ? null : _pickKickoff,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<FixtureScheduleDto>)
                AdminErrorBanner(
                  key: const Key('admin.fixtureEdit.error'),
                  message: ErrorPresenter.message(state.error as AppError),
                ),
              if (state is AsyncData<FixtureScheduleDto>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtureEdit.result'),
                  message: l10n.adminCorrectFixtureSuccess(
                    state.value.homeTeam,
                    state.value.awayTeam,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.fixtureEdit.submit'),
                label: l10n.adminCorrectFixtureButton,
                icon: Icons.edit_calendar_rounded,
                loading: inFlight,
                onPressed: canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ],
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

  void _submit() {
    final fixtureId = _fixtureId;
    final seasonId = _seasonId;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (fixtureId == null ||
        seasonId == null ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(fixtureScheduleControllerProvider.notifier)
        .correct(
          fixtureId: fixtureId,
          seasonId: seasonId,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
          homeTeamId: _homeTeamId,
          awayTeamId: _awayTeamId,
          leagueId: _leagueId,
        );
  }

  String _formatKickoff(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
