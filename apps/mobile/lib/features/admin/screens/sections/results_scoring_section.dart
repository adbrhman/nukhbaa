library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_providers.dart';
import '../../round_report.dart';
import '../../widgets/admin_ui_kit.dart';

class ResultsScoringSection extends ConsumerStatefulWidget {
  const ResultsScoringSection({super.key});

  @override
  ConsumerState<ResultsScoringSection> createState() =>
      _ResultsScoringSectionState();
}

class _ResultsScoringSectionState
    extends ConsumerState<ResultsScoringSection> {
  final _fixtureId = TextEditingController();
  final _homeGoals = TextEditingController();
  final _awayGoals = TextEditingController();
  final _roundId = TextEditingController();

  @override
  void dispose() {
    _fixtureId.dispose();
    _homeGoals.dispose();
    _awayGoals.dispose();
    _roundId.dispose();
    super.dispose();
  }

  void _recordResult() {
    final f = _fixtureId.text.trim();
    final h = int.tryParse(_homeGoals.text.trim());
    final a = int.tryParse(_awayGoals.text.trim());
    if (f.isEmpty || h == null || a == null) return;
    ref
        .read(recordFixtureResultControllerProvider.notifier)
        .record(fixtureId: f, homeGoals: h, awayGoals: a);
  }

  void _scoreRound() {
    final r = _roundId.text.trim();
    if (r.isEmpty) return;
    ref.read(scoreRoundControllerProvider.notifier).score(r);
  }

  void _lookup() {
    final r = _roundId.text.trim();
    if (r.isEmpty) return;
    ref.read(roundScoresLookupControllerProvider.notifier).lookup(r);
  }

  void _loadReport() {
    final r = _roundId.text.trim();
    if (r.isEmpty) return;
    ref.read(roundReportControllerProvider.notifier).load(r);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final resultState = ref.watch(recordFixtureResultControllerProvider);
    final scoreState = ref.watch(scoreRoundControllerProvider);
    final lookupState = ref.watch(roundScoresLookupControllerProvider);
    final reportState = ref.watch(roundReportControllerProvider);
    final resultInFlight = resultState is AsyncLoading<FixtureResultDto>;
    final scoreInFlight = scoreState is AsyncLoading<RoundScoresDto>;
    final lookupInFlight = lookupState is AsyncLoading<RoundScoresDto>;
    final reportInFlight = reportState is AsyncLoading<List<RoundReportRow>>;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminRecordResultSectionTitle,
          subtitle: 'سجّل النتيجة النهائية لمباراة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminTextField(
                controller: _fixtureId,
                hint: l10n.adminFixtureIdLabel,
                prefixIcon: Icons.sports_soccer_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AdminTextField(
                      controller: _homeGoals,
                      hint: l10n.adminHomeGoalsLabel,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminTextField(
                      controller: _awayGoals,
                      hint: l10n.adminAwayGoalsLabel,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (resultState is AsyncError<FixtureResultDto>)
                AdminErrorBanner(
                  message:
                      ErrorPresenter.message(resultState.error as AppError),
                ),
              if (resultState is AsyncData<FixtureResultDto>)
                AdminSuccessBanner(
                  message:
                      '${resultState.value.fixtureId}: ${resultState.value.homeGoals}-${resultState.value.awayGoals}',
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                label: l10n.adminRecordResultButton,
                icon: Icons.scoreboard_rounded,
                loading: resultInFlight,
                onPressed: resultInFlight ? null : _recordResult,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        AdminSectionHeader(
          title: l10n.adminScoreRoundSectionTitle,
          subtitle: 'احسب نقاط جميع التوقعات في الجولة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminTextField(
                controller: _roundId,
                hint: l10n.adminRoundIdLabel,
                prefixIcon: Icons.tag_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
              if (scoreState is AsyncError<RoundScoresDto>)
                AdminErrorBanner(
                  message:
                      ErrorPresenter.message(scoreState.error as AppError),
                ),
              if (scoreState is AsyncError<RoundScoresDto>)
                const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AdminPrimaryButton(
                      label: l10n.adminScoreRoundButton,
                      icon: Icons.calculate_rounded,
                      loading: scoreInFlight,
                      onPressed: scoreInFlight ? null : _scoreRound,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminSecondaryButton(
                      label: l10n.adminViewScoresButton,
                      icon: Icons.leaderboard_rounded,
                      loading: lookupInFlight,
                      onPressed: lookupInFlight ? null : _lookup,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (lookupState is AsyncError<RoundScoresDto>)
          AdminErrorBanner(
            message: ErrorPresenter.message(lookupState.error as AppError),
          ),
        Builder(builder: (context) {
          final scores = lookupState is AsyncData<RoundScoresDto>
              ? lookupState.value.scores
              : (scoreState is AsyncData<RoundScoresDto> ? scoreState.value.scores : null);
          if (scores == null) return const SizedBox.shrink();
          if (scores.isEmpty) {
            return AdminCard(
              child: AdminEmptyState(
                icon: Icons.leaderboard_rounded,
                title: 'لا توجد نتائج بعد',
              ),
            );
          }
          return AdminCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < scores.length; i++)
                  AdminListRow(
                    leadingIcon: Icons.emoji_events_rounded,
                    leadingColor: switch (i) {
                      0 => t.gold,
                      1 => t.silver,
                      2 => t.bronze,
                      _ => t.primary,
                    },
                    title: scores[i].participantId,
                    trailing: Text(
                      '${l10n.adminTotalPointsLabel}: ${scores[i].totalPoints}',
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.primary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xl),

        AdminSectionHeader(
          title: l10n.adminRoundReportSectionTitle,
          subtitle: 'شبكة تفصيلية بنتائج كل مشارك في كل مباراة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reportState is AsyncError<List<RoundReportRow>>)
                AdminErrorBanner(
                  message:
                      ErrorPresenter.message(reportState.error as AppError),
                ),
              if (reportState is AsyncError<List<RoundReportRow>>)
                const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                label: l10n.adminViewRoundReportButton,
                icon: Icons.table_chart_rounded,
                loading: reportInFlight,
                onPressed: reportInFlight ? null : _loadReport,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (reportState is AsyncData<List<RoundReportRow>>)
          Builder(builder: (context) {
            final rows = reportState.value;
            if (rows.isEmpty) {
              return AdminCard(
                child: AdminEmptyState(
                  icon: Icons.table_chart_rounded,
                  title: l10n.adminRoundReportSectionEmpty,
                ),
              );
            }
            return Column(
              children: [
                for (final row in rows) ...[
                  _RoundReportRowCard(row: row),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          }),
      ],
    );
  }
}

class _RoundReportRowCard extends StatelessWidget {
  const _RoundReportRowCard({required this.row});

  final RoundReportRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rankColor = switch (row.rank) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.primary,
    };

    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${row.rank}',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  row.participantId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${row.totalPoints}',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: t.primary,
                ),
              ),
            ],
          ),
          if (row.cells.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final cell in row.cells) _ReportCellChip(cell: cell),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportCellChip extends StatelessWidget {
  const _ReportCellChip({required this.cell});

  final RoundReportCell cell;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, label) = switch (cell.grade) {
      'exact_scoreline' => (t.gold, 'نتيجة مطابقة'),
      'correct_outcome' => (t.primary, 'نتيجة صحيحة'),
      'incorrect' => (t.error, 'خاطئ'),
      'missed' => (t.textMuted, 'لم يشارك'),
      _ => (t.textMuted, cell.grade),
    };

    final scoreText =
        cell.hasRawScore ? '${cell.homeGoals}-${cell.awayGoals}' : '—';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cell.isDouble) ...[
            Icon(Icons.star_rounded, size: 14, color: t.gold),
            const SizedBox(width: 4),
          ],
          Text(
            scoreText,
            style: context.text.bodyMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 14, color: color.withValues(alpha: 0.3)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${cell.points})',
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
