library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/competition_providers.dart';
import '../../../competition/team_registry.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// جدولة المباريات — اختيار المسابقة/الموسم/الجولة ثم إضافة مباراة.
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
  String? _roundId;
  int? _roundSequence;

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
    if (_roundId != null) {
      final AsyncValue<List<RoundFixtureCardDto>> fixturesState = ref.watch(
        roundFixturesProvider(_roundId!),
      );
      if (fixturesState is AsyncData<List<RoundFixtureCardDto>>) {
        nextDisplayOrder = fixturesState.value.length;
      }
    }

    final bool canSubmit =
        !inFlight &&
        _roundId != null &&
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
                fieldKey: const Key('admin.fixtures.competitionField'),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !inFlight,
                selectedId: _competitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _competitionId = competition.id;
                  _competitionName = competition.name;
                  _seasonId = null;
                  _roundId = null;
                  _roundSequence = null;
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
                    _roundId = null;
                    _roundSequence = null;
                  }),
                ),
              ],
              if (_seasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                RoundPickerField(
                  seasonId: _seasonId!,
                  enabled: !inFlight,
                  selectedId: _roundId,
                  onSelected: (RoundDto round) => setState(() {
                    _roundId = round.id;
                    _roundSequence = round.sequence;
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
              AdminDateTimeField(
                key: const Key('admin.fixtures.kickoffPicker'),
                value: _kickoffLocal,
                placeholder: l10n.adminPickKickoffButton,
                enabled: !inFlight,
                onChanged: (DateTime picked) =>
                    setState(() => _kickoffLocal = picked),
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
                    state.value.roundSequence,
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
        if (_roundId != null) ...[
          const SizedBox(height: AppSpacing.xl),
          AdminSectionHeader(title: l10n.adminExistingFixturesSectionTitle),
          _RoundFixturesList(roundId: _roundId!),
        ],
      ],
    );
  }

  void _addMatch(int displayOrder) {
    final roundId = _roundId;
    final sequence = _roundSequence;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (roundId == null ||
        sequence == null ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(addMatchControllerProvider.notifier)
        .submit(
          roundId: roundId,
          roundSequence: sequence,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
          displayOrder: displayOrder,
        );
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

/// قائمة مباريات الجولة المختارة مع زر حذف لكل مباراة (المشكلة 1: تصحيح
/// مباراة مكرّرة/مُضافة بالخطأ). يعتمد على `roundFixturesProvider` — نفس
/// مصدر البيانات المستخدم أعلاه لحساب `nextDisplayOrder`.
class _RoundFixturesList extends ConsumerWidget {
  const _RoundFixturesList({required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<RoundFixtureCardDto>> fixtures = ref.watch(
      roundFixturesProvider(roundId),
    );
    final removeState = ref.watch(removeFixtureControllerProvider);
    final bool removing = removeState is AsyncLoading<bool>;

    return fixtures.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(),
      ),
      error: (Object error, StackTrace _) =>
          AdminCard(child: Text(ErrorPresenter.message(error as AppError))),
      data: (List<RoundFixtureCardDto> list) {
        if (list.isEmpty) {
          return AdminCard(
            child: AdminEmptyState(
              icon: Icons.sports_soccer_rounded,
              title: l10n.adminNoFixturesHint,
            ),
          );
        }
        return AdminCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final RoundFixtureCardDto fixture in list)
                AdminListRow(
                  key: Key('admin.fixtures.existing.${fixture.fixtureId}'),
                  leadingIcon: Icons.sports_soccer_rounded,
                  leadingColor: context.tokens.primary,
                  title: fixture.homeTeam != null && fixture.awayTeam != null
                      ? '${fixture.homeTeam} × ${fixture.awayTeam}'
                      : l10n.adminFixtureIncompleteDataLabel,
                  trailing: IconButton(
                    key: Key('admin.fixtures.remove.${fixture.fixtureId}'),
                    tooltip: l10n.adminRemoveFixtureTooltip,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: context.tokens.error,
                    ),
                    onPressed: removing
                        ? null
                        : () => _confirmAndRemove(context, ref, fixture),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    WidgetRef ref,
    RoundFixtureCardDto fixture,
  ) async {
    final l10n = AppLocalizations.of(context);
    final home = fixture.homeTeam ?? l10n.adminFixtureIncompleteDataLabel;
    final away = fixture.awayTeam ?? l10n.adminFixtureIncompleteDataLabel;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminRemoveFixtureConfirmTitle),
        content: Text(l10n.adminRemoveFixtureConfirmMessage(home, away)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminRemoveFixtureCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminRemoveFixtureConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(removeFixtureControllerProvider.notifier)
        .remove(roundId: roundId, fixtureId: fixture.fixtureId);

    final state = ref.read(removeFixtureControllerProvider);
    if (!context.mounted) return;
    if (state is AsyncData<bool>) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminRemoveFixtureSuccess)),
      );
    } else if (state is AsyncError<bool>) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorPresenter.message(state.error as AppError)),
        ),
      );
    }
  }
}
