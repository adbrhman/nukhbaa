library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/team_registry.dart';
import '../../../competition/teams_providers.dart';
import '../../../fixture_prediction/fixture_prediction_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// جدولة المباريات — اختيار المسابقة/الموسم ثم إضافة مباراة.
class FixtureScheduleSection extends ConsumerStatefulWidget {
  const FixtureScheduleSection({super.key});

  @override
  ConsumerState<FixtureScheduleSection> createState() =>
      _FixtureScheduleSectionState();
}

class _FixtureScheduleSectionState
    extends ConsumerState<FixtureScheduleSection> {
  final TextEditingController _homeTeamController = TextEditingController();
  final TextEditingController _awayTeamController = TextEditingController();
  final FocusNode _homeTeamFocusNode = FocusNode();
  final FocusNode _awayTeamFocusNode = FocusNode();
  DateTime? _kickoffLocal;

  String? _competitionId;
  String? _competitionName;
  String? _seasonId;
  String? _homeTeamId;
  String? _awayTeamId;

  // نطاق اختيار المباراة (لتصحيح بياناتها).
  final TextEditingController _correctHomeTeamController =
      TextEditingController();
  final TextEditingController _correctAwayTeamController =
      TextEditingController();
  final FocusNode _correctHomeTeamFocusNode = FocusNode();
  final FocusNode _correctAwayTeamFocusNode = FocusNode();
  DateTime? _correctKickoffLocal;

  String? _correctCompetitionId;
  String? _correctCompetitionName;
  String? _correctSeasonId;
  String? _correctFixtureId;
  String? _correctHomeTeamId;
  String? _correctAwayTeamId;

  static final List<String> _teamOptions = <String>[
    ...kEplTeams.keys,
    ...kSaudiTeams.keys,
  ]..sort();

  List<String> _scopedTeamOptions(String? competitionName) {
    final String name = competitionName ?? '';
    if (name.contains('إنجليز')) return kEplTeams.keys.toList()..sort();
    if (name.contains('سعود')) return kSaudiTeams.keys.toList()..sort();
    return _teamOptions;
  }

  /// Resolves [text] against [catalog] (the real `football_data.teams`
  /// catalog) by exact, case-insensitive name match — `null` when the typed
  /// text doesn't (yet) name a real team, which is a legitimate state (a
  /// free-text legacy team name, or a league with no seeded catalog).
  String? _resolveTeamId(List<TeamDto> catalog, String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    for (final TeamDto team in catalog) {
      if (team.name.toLowerCase() == trimmed.toLowerCase()) return team.id;
    }
    return null;
  }

  /// Suggestion options merging the legacy name-only lists with the real
  /// [catalog] (deduplicated, case-insensitive), so an admin sees genuine
  /// `football_data.teams` rows alongside the still-supported free-text
  /// legacy names — selecting a catalog name is what lets [_resolveTeamId]
  /// attach a real team id to the fixture.
  Iterable<String> _filterTeamsWithCatalog(
    String query, {
    String? competitionName,
    required List<TeamDto> catalog,
  }) {
    final Map<String, String> merged = <String, String>{};
    for (final String name in _scopedTeamOptions(competitionName)) {
      merged[name.toLowerCase()] = name;
    }
    for (final TeamDto team in catalog) {
      merged[team.name.toLowerCase()] = team.name;
    }
    final List<String> options = merged.values.toList()..sort();
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return options;
    final String needle = trimmed.toLowerCase();
    return options.where((String t) => t.toLowerCase().contains(needle));
  }

  @override
  void dispose() {
    _homeTeamController.dispose();
    _awayTeamController.dispose();
    _homeTeamFocusNode.dispose();
    _awayTeamFocusNode.dispose();
    _correctHomeTeamController.dispose();
    _correctAwayTeamController.dispose();
    _correctHomeTeamFocusNode.dispose();
    _correctAwayTeamFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<TeamDto> catalog =
        ref.watch(teamCatalogProvider).value ?? const <TeamDto>[];
    final AsyncValue<AddMatchResult>? state = ref.watch(
      addMatchControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<AddMatchResult>;

    int nextDisplayOrder = 0;
    if (_seasonId != null) {
      final AsyncValue<List<SeasonFixtureCardDto>> fixturesState = ref.watch(
        seasonFixturesProvider(_seasonId!),
      );
      if (fixturesState is AsyncData<List<SeasonFixtureCardDto>>) {
        nextDisplayOrder = fixturesState.value.length;
      }
    }

    final bool canSubmit =
        !inFlight &&
        _seasonId != null &&
        _homeTeamController.text.trim().isNotEmpty &&
        _awayTeamController.text.trim().isNotEmpty &&
        _kickoffLocal != null;

    final AsyncValue<FixtureScheduleDto>? correctState = ref.watch(
      fixtureScheduleControllerProvider,
    );
    final bool correctInFlight =
        correctState is AsyncLoading<FixtureScheduleDto>;
    final bool canSubmitCorrection =
        !correctInFlight &&
        _correctSeasonId != null &&
        _correctFixtureId != null &&
        _correctHomeTeamController.text.trim().isNotEmpty &&
        _correctAwayTeamController.text.trim().isNotEmpty &&
        _correctKickoffLocal != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminAddMatchSectionTitle,
          subtitle: 'اختر المسابقة والموسم والجولة ثم أضف المباراة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                key: const Key('admin.fixtures.competitionField'),
                fieldKey: const Key('admin.fixtures.competitionField.field'),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !inFlight,
                selectedId: _competitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _competitionId = competition.id;
                  _competitionName = competition.name;
                  _seasonId = null;
                  _homeTeamController.clear();
                  _awayTeamController.clear();
                  _homeTeamId = null;
                  _awayTeamId = null;
                }),
              ),
              if (_competitionId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonPickerField(
                  competitionId: _competitionId!,
                  enabled: !inFlight,
                  selectedId: _seasonId,
                  onSelected: (String seasonId) => setState(() {
                    _seasonId = seasonId;
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _TeamPickerField(
                fieldKey: const Key('admin.fixtures.homeTeamField'),
                controller: _homeTeamController,
                focusNode: _homeTeamFocusNode,
                label: l10n.adminHomeTeamLabel,
                enabled: !inFlight,
                catalog: catalog,
                optionsBuilder: (q) => _filterTeamsWithCatalog(
                  q,
                  competitionName: _competitionName,
                  catalog: catalog,
                ),
                onChanged: () => setState(() {
                  _homeTeamId = _resolveTeamId(
                    catalog,
                    _homeTeamController.text,
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              _TeamPickerField(
                fieldKey: const Key('admin.fixtures.awayTeamField'),
                controller: _awayTeamController,
                focusNode: _awayTeamFocusNode,
                label: l10n.adminAwayTeamLabel,
                enabled: !inFlight,
                catalog: catalog,
                optionsBuilder: (q) => _filterTeamsWithCatalog(
                  q,
                  competitionName: _competitionName,
                  catalog: catalog,
                ),
                onChanged: () => setState(() {
                  _awayTeamId = _resolveTeamId(
                    catalog,
                    _awayTeamController.text,
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                key: const Key('admin.fixtures.kickoffPicker'),
                label: _kickoffLocal == null
                    ? l10n.adminPickKickoffButton
                    : _formatKickoff(_kickoffLocal!),
                icon: Icons.event_outlined,
                onPressed: inFlight ? null : _pickKickoff,
              ),
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<AddMatchResult>)
                AdminErrorBanner(
                  key: const Key('admin.fixtures.error'),
                  message: ErrorPresenter.message(state.error as AppError),
                ),
              if (state is AsyncData<AddMatchResult>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtures.result'),
                  message: l10n.adminAddMatchSuccess(
                    state.value.fixture.homeTeam,
                    state.value.fixture.awayTeam,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.fixtures.addMatch'),
                label: l10n.adminAddMatchButton,
                icon: Icons.sports_soccer_rounded,
                loading: inFlight,
                onPressed: canSubmit ? () => _addMatch(nextDisplayOrder) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AdminSectionHeader(
          title: l10n.adminCorrectFixtureSectionTitle,
          subtitle: l10n.adminCorrectFixtureSubtitle,
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                key: const Key('admin.fixtures.correct.competitionField'),
                fieldKey: const Key(
                  'admin.fixtures.correct.competitionField.field',
                ),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !correctInFlight,
                selectedId: _correctCompetitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _correctCompetitionId = competition.id;
                  _correctCompetitionName = competition.name;
                  _correctSeasonId = null;
                  _correctFixtureId = null;
                  _correctHomeTeamController.clear();
                  _correctAwayTeamController.clear();
                  _correctHomeTeamId = null;
                  _correctAwayTeamId = null;
                  _correctKickoffLocal = null;
                }),
              ),
              if (_correctCompetitionId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonPickerField(
                  competitionId: _correctCompetitionId!,
                  enabled: !correctInFlight,
                  selectedId: _correctSeasonId,
                  onSelected: (String seasonId) => setState(() {
                    _correctSeasonId = seasonId;
                    _correctFixtureId = null;
                  }),
                ),
              ],
              if (_correctSeasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.fixtures.correct',
                  seasonId: _correctSeasonId!,
                  enabled: !correctInFlight,
                  selectedId: _correctFixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {
                    _correctFixtureId = fixture.fixtureId;
                    _correctHomeTeamController.text = fixture.homeTeam ?? '';
                    _correctAwayTeamController.text = fixture.awayTeam ?? '';
                    _correctHomeTeamId = fixture.homeTeamId;
                    _correctAwayTeamId = fixture.awayTeamId;
                    _correctKickoffLocal = DateTime.tryParse(
                      fixture.kickoffAt ?? '',
                    )?.toLocal();
                  }),
                ),
              ],
              if (_correctFixtureId != null) ...[
                const SizedBox(height: AppSpacing.md),
                _TeamPickerField(
                  fieldKey: const Key('admin.fixtures.correct.homeTeamField'),
                  controller: _correctHomeTeamController,
                  focusNode: _correctHomeTeamFocusNode,
                  label: l10n.adminHomeTeamLabel,
                  enabled: !correctInFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _filterTeamsWithCatalog(
                    q,
                    competitionName: _correctCompetitionName,
                    catalog: catalog,
                  ),
                  onChanged: () => setState(() {
                    _correctHomeTeamId = _resolveTeamId(
                      catalog,
                      _correctHomeTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                _TeamPickerField(
                  fieldKey: const Key('admin.fixtures.correct.awayTeamField'),
                  controller: _correctAwayTeamController,
                  focusNode: _correctAwayTeamFocusNode,
                  label: l10n.adminAwayTeamLabel,
                  enabled: !correctInFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _filterTeamsWithCatalog(
                    q,
                    competitionName: _correctCompetitionName,
                    catalog: catalog,
                  ),
                  onChanged: () => setState(() {
                    _correctAwayTeamId = _resolveTeamId(
                      catalog,
                      _correctAwayTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                AdminSecondaryButton(
                  key: const Key('admin.fixtures.correct.kickoffPicker'),
                  label: _correctKickoffLocal == null
                      ? l10n.adminPickKickoffButton
                      : _formatKickoff(_correctKickoffLocal!),
                  icon: Icons.event_outlined,
                  onPressed: correctInFlight ? null : _pickCorrectKickoff,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (correctState is AsyncError<FixtureScheduleDto>)
                AdminErrorBanner(
                  key: const Key('admin.fixtures.correct.error'),
                  message: ErrorPresenter.message(
                    correctState.error as AppError,
                  ),
                ),
              if (correctState is AsyncData<FixtureScheduleDto>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtures.correct.result'),
                  message: l10n.adminCorrectFixtureSuccess(
                    correctState.value.homeTeam,
                    correctState.value.awayTeam,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.fixtures.correct.submit'),
                label: l10n.adminCorrectFixtureButton,
                icon: Icons.edit_calendar_rounded,
                loading: correctInFlight,
                onPressed: canSubmitCorrection ? _correctFixture : null,
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

  void _addMatch(int displayOrder) {
    final seasonId = _seasonId;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (seasonId == null ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(addMatchControllerProvider.notifier)
        .submit(
          seasonId: seasonId,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
          displayOrder: displayOrder,
          homeTeamId: _homeTeamId,
          awayTeamId: _awayTeamId,
        );
  }

  Future<void> _pickCorrectKickoff() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _correctKickoffLocal ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _correctKickoffLocal == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_correctKickoffLocal!),
    );
    if (time == null) return;
    setState(() {
      _correctKickoffLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _correctFixture() {
    final fixtureId = _correctFixtureId;
    final seasonId = _correctSeasonId;
    final homeTeam = _correctHomeTeamController.text.trim();
    final awayTeam = _correctAwayTeamController.text.trim();
    final kickoff = _correctKickoffLocal;
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
          homeTeamId: _correctHomeTeamId,
          awayTeamId: _correctAwayTeamId,
        );
  }

  String _formatKickoff(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// حقل نصي مع اقتراحات فرق مفلترة — أي نص يُقبل، حتى لو لم يكن ضمن السجل.
class _TeamPickerField extends StatelessWidget {
  const _TeamPickerField({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.enabled,
    required this.optionsBuilder,
    this.catalog = const <TeamDto>[],
    this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool enabled;
  final Iterable<String> Function(String query) optionsBuilder;

  /// The real `football_data.teams` catalog — an option matching one of
  /// these by name (case-insensitive) is a genuine team: selecting it is
  /// what lets the fixture link a real team id, shown here as a small hint
  /// distinguishing it from a legacy free-text-only name.
  final List<TeamDto> catalog;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          optionsBuilder: (TextEditingValue value) =>
              optionsBuilder(value.text),
          onSelected: (String selection) {
            controller.text = selection;
            onChanged?.call();
          },
          fieldViewBuilder: (context, fieldController, fieldFocusNode, _) {
            return TextField(
              key: fieldKey,
              controller: fieldController,
              focusNode: fieldFocusNode,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              enabled: enabled,
              onChanged: (_) => onChanged?.call(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final List<String> optionList = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: 240,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: optionList.length,
                    itemBuilder: (context, index) {
                      final String option = optionList[index];
                      final TeamBrand? brand =
                          kEplTeams[option] ?? kSaudiTeams[option];
                      final bool isCatalogTeam = catalog.any(
                        (TeamDto t) =>
                            t.name.toLowerCase() == option.toLowerCase(),
                      );
                      return ListTile(
                        dense: true,
                        title: Text(option),
                        subtitle: isCatalogTeam
                            ? const Text('team id مرتبط ✓')
                            : (brand == null ? null : Text(brand.ar)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
