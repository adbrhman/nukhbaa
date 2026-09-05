library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// التوقعات — تصفّح كل التوقعات المسجّلة لمباراة واحدة، قبل احتسابها أو
/// بعده. مبني على قراءة الأدمن الخام (`GET /admin/fixtures/{id}/predictions`)
/// بلا اشتراط أن تكون المباراة محتسبة، على عكس تقرير المباراة في قسم
/// "النتائج والاحتساب" الذي يستلزم الاحتساب أولاً.
class AdminPredictionsSection extends ConsumerStatefulWidget {
  const AdminPredictionsSection({super.key});

  @override
  ConsumerState<AdminPredictionsSection> createState() =>
      _AdminPredictionsSectionState();
}

class _AdminPredictionsSectionState
    extends ConsumerState<AdminPredictionsSection> {
  String? _competitionId;
  String? _seasonId;
  String? _fixtureId;

  void _loadPredictions() {
    final fixtureId = _fixtureId;
    if (fixtureId == null) return;
    ref
        .read(adminFixturePredictionsControllerProvider.notifier)
        .load(fixtureId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<FixturePredictionDto>>? state = ref.watch(
      adminFixturePredictionsControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<List<FixturePredictionDto>>;
    final bool canLoad = !inFlight && _fixtureId != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminPredictionsTab,
          subtitle: l10n.adminPredictionsSubtitle,
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                key: const Key('admin.predictions.competitionField'),
                fieldKey: const Key('admin.predictions.competitionField.field'),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !inFlight,
                selectedId: _competitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _competitionId = competition.id;
                  _seasonId = null;
                  _fixtureId = null;
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
                    _fixtureId = null;
                  }),
                ),
              ],
              if (_seasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.predictions',
                  seasonId: _seasonId!,
                  enabled: !inFlight,
                  selectedId: _fixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {
                    _fixtureId = fixture.fixtureId;
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<List<FixturePredictionDto>>)
                AdminErrorBanner(
                  key: const Key('admin.predictions.error'),
                  message: ErrorPresenter.message(state.error as AppError),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.predictions.load'),
                label: l10n.adminLoadPredictionsButton,
                icon: Icons.rule_folder_rounded,
                loading: inFlight,
                onPressed: canLoad ? _loadPredictions : null,
              ),
            ],
          ),
        ),
        if (state is AsyncData<List<FixturePredictionDto>>) ...[
          const SizedBox(height: AppSpacing.md),
          if (state.value.isEmpty)
            AdminCard(
              child: AdminEmptyState(
                icon: Icons.rule_folder_rounded,
                title: l10n.adminPredictionsEmpty,
              ),
            )
          else
            Column(
              children: [
                for (final prediction in state.value) ...[
                  _PredictionRowCard(prediction: prediction),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
        ],
      ],
    );
  }
}

/// Fallback when the server joined no display name: a short slice of the
/// id instead of a full UUID filling the row.
String _shortId(String participantId) => participantId.length <= 8
    ? participantId
    : '${participantId.substring(0, 8)}…';

class _PredictionRowCard extends StatelessWidget {
  const _PredictionRowCard({required this.prediction});

  final FixturePredictionDto prediction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prediction.displayName.isNotEmpty
                      ? prediction.displayName
                      : _shortId(prediction.participantId),
                  key: Key('admin.predictions.item.${prediction.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.adminPredictionSubmittedAtLabel(prediction.submittedAt),
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (prediction.isDouble) ...[
            Icon(Icons.star_rounded, size: 16, color: t.gold),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            '${prediction.homeGoals}-${prediction.awayGoals}',
            key: Key('admin.predictions.score.${prediction.id}'),
            style: context.text.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
