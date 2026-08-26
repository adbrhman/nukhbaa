library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/team_registry.dart';
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

  static final List<String> _teamOptions = <String>[
    ...kEplTeams.keys,
    ...kSaudiTeams.keys,
  ]..sort();

  List<String> get _scopedTeamOptions {
    final String name = _competitionName ?? '';
    if (name.contains('إنجليز')) return kEplTeams.keys.toList()..sort();
    if (name.contains('سعود')) return kSaudiTeams.keys.toList()..sort();
    return _teamOptions;
  }

  Iterable<String> _filterTeams(String query) {
    final List<String> options = _scopedTeamOptions;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                optionsBuilder: _filterTeams,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              _TeamPickerField(
                fieldKey: const Key('admin.fixtures.awayTeamField'),
                controller: _awayTeamController,
                focusNode: _awayTeamFocusNode,
                label: l10n.adminAwayTeamLabel,
                enabled: !inFlight,
                optionsBuilder: _filterTeams,
                onChanged: () => setState(() {}),
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
    this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool enabled;
  final Iterable<String> Function(String query) optionsBuilder;
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
                      return ListTile(
                        dense: true,
                        title: Text(option),
                        subtitle: brand == null ? null : Text(brand.ar),
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
