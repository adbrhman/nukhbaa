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
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// إدارة الجولات — فتح جولة جديدة، وعرض الجولات الموجودة للموسم المختار.
class RoundAdministrationSection extends ConsumerStatefulWidget {
  const RoundAdministrationSection({super.key});

  @override
  ConsumerState<RoundAdministrationSection> createState() =>
      _RoundAdministrationSectionState();
}

class _RoundAdministrationSectionState
    extends ConsumerState<RoundAdministrationSection> {
  final TextEditingController _sequenceController = TextEditingController();
  DateTime? _deadlineLocal;

  String? _competitionId;
  String? _seasonId;

  @override
  void dispose() {
    _sequenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<RoundDto>? openState = ref.watch(
      roundOpenControllerProvider,
    );
    final bool openInFlight = openState is AsyncLoading<RoundDto>;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminOpenRoundSectionTitle,
          subtitle: 'افتح جولة جديدة لموسم مسابقة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                fieldKey: const Key('admin.rounds.competitionField'),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !openInFlight,
                selectedId: _competitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _competitionId = competition.id;
                  _seasonId = null;
                }),
              ),
              if (_competitionId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonPickerField(
                  competitionId: _competitionId!,
                  enabled: !openInFlight,
                  selectedId: _seasonId,
                  onSelected: (String seasonId) => setState(() {
                    _seasonId = seasonId;
                    _suggestNextSequence();
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AdminTextField(
                key: const Key('admin.rounds.sequenceField'),
                controller: _sequenceController,
                hint: l10n.adminSequenceLabel,
                keyboardType: TextInputType.number,
                enabled: !openInFlight,
              ),
              const SizedBox(height: AppSpacing.md),
              AdminDateTimeField(
                key: const Key('admin.rounds.deadlinePicker'),
                value: _deadlineLocal,
                placeholder: l10n.adminPickDeadlineButton,
                enabled: !openInFlight,
                onChanged: (DateTime picked) =>
                    setState(() => _deadlineLocal = picked),
              ),
              const SizedBox(height: AppSpacing.md),
              if (openState is AsyncError<RoundDto>)
                AdminErrorBanner(
                  key: const Key('admin.rounds.open.error'),
                  message: ErrorPresenter.message(openState.error as AppError),
                ),
              if (openState is AsyncData<RoundDto>)
                AdminSuccessBanner(
                  key: const Key('admin.rounds.open.result'),
                  message: l10n.adminRoundOptionLabel(
                    openState.value.sequence,
                    openState.value.status,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.rounds.open'),
                label: l10n.adminOpenRoundButton,
                icon: Icons.lock_open_rounded,
                loading: openInFlight,
                onPressed: openInFlight || _seasonId == null
                    ? null
                    : _openRound,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AdminSectionHeader(
          title: l10n.adminManageRoundsSectionTitle,
          subtitle: 'اطّلع على الجولات المفتوحة لهذا الموسم',
        ),
        if (_seasonId != null) _ExistingRoundsList(seasonId: _seasonId!),
      ],
    );
  }

  void _suggestNextSequence() {
    final seasonId = _seasonId;
    if (seasonId == null) return;
    final AsyncValue<List<RoundDto>> roundsState = ref.read(
      seasonRoundsProvider(seasonId),
    );
    if (roundsState is! AsyncData<List<RoundDto>>) return;
    final List<RoundDto> rounds = roundsState.value;
    final int next = rounds.isEmpty
        ? 1
        : (rounds.map((r) => r.sequence).reduce((a, b) => a > b ? a : b) + 1);
    _sequenceController.text = '$next';
  }

  void _openRound() {
    final seasonId = _seasonId;
    final sequence = int.tryParse(_sequenceController.text.trim());
    final deadline = _deadlineLocal;
    if (seasonId == null || sequence == null || deadline == null) return;
    ref
        .read(roundOpenControllerProvider.notifier)
        .open(
          seasonId: seasonId,
          sequence: sequence,
          predictionDeadline: deadline.toUtc().toIso8601String(),
        );
  }
}

/// عرض قائمة الجولات الموجودة للموسم المختار (قراءة فقط، بلا UUID).
class _ExistingRoundsList extends ConsumerWidget {
  const _ExistingRoundsList({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<RoundDto>> rounds = ref.watch(
      seasonRoundsProvider(seasonId),
    );
    return rounds.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) =>
          AdminErrorBanner(message: ErrorPresenter.message(error as AppError)),
      data: (List<RoundDto> list) {
        if (list.isEmpty) {
          return AdminCard(
            child: AdminEmptyState(
              icon: Icons.event_busy_rounded,
              title: l10n.adminExistingRoundsEmpty,
            ),
          );
        }
        return Column(
          children: [
            for (final RoundDto round in list) ...[
              _ExistingRoundCard(round: round),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

/// بطاقة جولة واحدة: تعرض حالتها، وزر "إغلاق الجولة" عندما تكون مفتوحة
/// (شرط سابق لاحتساب النقاط عبر [ScoreRoundController]).
class _ExistingRoundCard extends ConsumerWidget {
  const _ExistingRoundCard({required this.round});

  final RoundDto round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<RoundDto>? lockState = ref.watch(
      roundLockControllerProvider,
    );
    final bool lockInFlight = lockState is AsyncLoading<RoundDto>;

    return AdminCard(
      key: Key('admin.rounds.existing.${round.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.adminRoundOptionLabel(round.sequence, round.status),
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            round.predictionDeadline,
            style: TextStyle(color: context.tokens.textSecondary),
          ),
          if (round.status == 'open') ...[
            const SizedBox(height: AppSpacing.md),
            if (lockState is AsyncError<RoundDto>)
              AdminErrorBanner(
                key: Key('admin.rounds.lock.error.${round.id}'),
                message: ErrorPresenter.message(lockState.error as AppError),
              ),
            const SizedBox(height: AppSpacing.sm),
            AdminPrimaryButton(
              key: Key('admin.rounds.lock.${round.id}'),
              label: l10n.adminLockRoundButton,
              icon: Icons.lock_rounded,
              loading: lockInFlight,
              onPressed: lockInFlight
                  ? null
                  : () => ref
                        .read(roundLockControllerProvider.notifier)
                        .lock(round.id),
            ),
          ],
        ],
      ),
    );
  }
}
