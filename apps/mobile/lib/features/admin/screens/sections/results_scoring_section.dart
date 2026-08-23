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
import '../../round_report.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// النتائج والاحتساب — تسجيل نتيجة مباراة، احتساب جولة،
/// عرض النتائج، وتقرير الجولة التفصيلي.
///
/// معرّف المباراة ومعرّف الجولة يُختاران من قوائم منسدلة (المسابقة ← الموسم
/// ← الجولة [← المباراة])، وليس بإدخال UUID يدوي — مطابقةً لنمط
/// `RoundAdministrationSection`/`FixtureScheduleSection`.
class ResultsScoringSection extends ConsumerStatefulWidget {
  const ResultsScoringSection({super.key});

  @override
  ConsumerState<ResultsScoringSection> createState() =>
      _ResultsScoringSectionState();
}

class _ResultsScoringSectionState extends ConsumerState<ResultsScoringSection> {
  final _homeGoals = TextEditingController();
  final _awayGoals = TextEditingController();

  // نطاق اختيار المباراة (لتسجيل النتيجة).
  String? _resultCompetitionId;
  String? _resultSeasonId;
  String? _resultRoundId;
  String? _fixtureId;

  // نطاق اختيار الجولة (للاحتساب/عرض النتائج/تقرير الجولة).
  String? _scoreCompetitionId;
  String? _scoreSeasonId;
  String? _roundId;

  @override
  void dispose() {
    _homeGoals.dispose();
    _awayGoals.dispose();
    super.dispose();
  }

  void _recordResult() {
    final f = _fixtureId;
    final h = int.tryParse(_homeGoals.text.trim());
    final a = int.tryParse(_awayGoals.text.trim());
    if (f == null || h == null || a == null) return;
    ref
        .read(recordFixtureResultControllerProvider.notifier)
        .record(fixtureId: f, homeGoals: h, awayGoals: a);
  }

  void _scoreRound() {
    final r = _roundId;
    if (r == null) return;
    ref.read(scoreRoundControllerProvider.notifier).score(r);
  }

  void _lookup() {
    final r = _roundId;
    if (r == null) return;
    ref.read(roundScoresLookupControllerProvider.notifier).lookup(r);
  }

  void _loadReport() {
    final r = _roundId;
    if (r == null) return;
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
    final resultInFlight = resultState is AsyncLoading;
    final scoreInFlight = scoreState is AsyncLoading;
    final lookupInFlight = lookupState is AsyncLoading;
    final reportInFlight = reportState is AsyncLoading;

    final bool canRecord = !resultInFlight && _fixtureId != null;
    final bool canScore = _roundId != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminRecordResultSectionTitle,
          subtitle: 'اختر المسابقة والموسم والجولة ثم المباراة وسجّل نتيجتها',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                key: const Key('admin.results.competitionField'),
                fieldKey: const Key('admin.results.competitionField.field'),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !resultInFlight,
                selectedId: _resultCompetitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _resultCompetitionId = competition.id;
                  _resultSeasonId = null;
                  _resultRoundId = null;
                  _fixtureId = null;
                }),
              ),
              if (_resultCompetitionId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonPickerField(
                  competitionId: _resultCompetitionId!,
                  enabled: !resultInFlight,
                  selectedId: _resultSeasonId,
                  onSelected: (String seasonId) => setState(() {
                    _resultSeasonId = seasonId;
                    _resultRoundId = null;
                    _fixtureId = null;
                  }),
                ),
              ],
              if (_resultSeasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                RoundPickerField(
                  keyPrefix: 'admin.results.record',
                  seasonId: _resultSeasonId!,
                  enabled: !resultInFlight,
                  selectedId: _resultRoundId,
                  onSelected: (RoundDto round) => setState(() {
                    _resultRoundId = round.id;
                    _fixtureId = null;
                  }),
                ),
              ],
              if (_resultRoundId != null) ...[
                const SizedBox(height: AppSpacing.md),
                FixturePickerField(
                  keyPrefix: 'admin.results.record',
                  roundId: _resultRoundId!,
                  enabled: !resultInFlight,
                  selectedId: _fixtureId,
                  onSelected: (RoundFixtureCardDto fixture) => setState(() {
                    _fixtureId = fixture.fixtureId;
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AdminTextField(
                      controller: _homeGoals,
                      hint: l10n.adminHomeGoalsLabel,
                      keyboardType: TextInputType.number,
                      enabled: !resultInFlight,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminTextField(
                      controller: _awayGoals,
                      hint: l10n.adminAwayGoalsLabel,
                      keyboardType: TextInputType.number,
                      enabled: !resultInFlight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (resultState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    resultState!.error as AppError,
                  ),
                ),
              if (resultState is AsyncData)
                AdminSuccessBanner(
                  message:
                      '${resultState!.value!.fixtureId}: ${resultState.value!.homeGoals}-${resultState.value!.awayGoals}',
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                label: l10n.adminRecordResultButton,
                icon: Icons.scoreboard_rounded,
                loading: resultInFlight,
                onPressed: canRecord ? _recordResult : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AdminSectionHeader(
          title: l10n.adminScoreRoundSectionTitle,
          subtitle: 'اختر المسابقة والموسم ثم الجولة لاحتساب توقعاتها',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompetitionPickerField(
                key: const Key('admin.results.score.competitionField'),
                fieldKey: const Key(
                  'admin.results.score.competitionField.field',
                ),
                label: l10n.adminSelectCompetitionLabel,
                enabled: !scoreInFlight && !lookupInFlight && !reportInFlight,
                selectedId: _scoreCompetitionId,
                onSelected: (CompetitionDto competition) => setState(() {
                  _scoreCompetitionId = competition.id;
                  _scoreSeasonId = null;
                  _roundId = null;
                }),
              ),
              if (_scoreCompetitionId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonPickerField(
                  competitionId: _scoreCompetitionId!,
                  enabled: !scoreInFlight && !lookupInFlight && !reportInFlight,
                  selectedId: _scoreSeasonId,
                  onSelected: (String seasonId) => setState(() {
                    _scoreSeasonId = seasonId;
                    _roundId = null;
                  }),
                ),
              ],
              if (_scoreSeasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                RoundPickerField(
                  keyPrefix: 'admin.results.score',
                  seasonId: _scoreSeasonId!,
                  enabled: !scoreInFlight && !lookupInFlight && !reportInFlight,
                  selectedId: _roundId,
                  onSelected: (RoundDto round) => setState(() {
                    _roundId = round.id;
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (scoreState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    scoreState!.error as AppError,
                  ),
                ),
              if (scoreState is AsyncError)
                const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AdminPrimaryButton(
                      label: l10n.adminScoreRoundButton,
                      icon: Icons.calculate_rounded,
                      loading: scoreInFlight,
                      onPressed: scoreInFlight || !canScore
                          ? null
                          : _scoreRound,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminSecondaryButton(
                      label: l10n.adminViewScoresButton,
                      icon: Icons.leaderboard_rounded,
                      loading: lookupInFlight,
                      onPressed: lookupInFlight || !canScore ? null : _lookup,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (lookupState is AsyncError)
          AdminErrorBanner(
            message: ErrorPresenter.message(lookupState!.error as AppError),
          ),
        Builder(
          builder: (context) {
            final scores = lookupState is AsyncData
                ? lookupState!.value!.scores
                : (scoreState is AsyncData ? scoreState!.value!.scores : null);
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
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        AdminSectionHeader(
          title: l10n.adminRoundReportSectionTitle,
          subtitle: 'شبكة تفصيلية بنتائج كل مشارك في كل مباراة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reportState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    reportState!.error as AppError,
                  ),
                ),
              if (reportState is AsyncError)
                const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                label: l10n.adminViewRoundReportButton,
                icon: Icons.table_chart_rounded,
                loading: reportInFlight,
                onPressed: reportInFlight || !canScore ? null : _loadReport,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportState is AsyncData<List<RoundReportRow>>)
          Builder(
            builder: (context) {
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
            },
          ),
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
      'pending' => (t.textSecondary, 'بانتظار النتيجة'),
      _ => (t.textMuted, cell.grade),
    };

    final scoreText = cell.hasRawScore
        ? '${cell.homeGoals}-${cell.awayGoals}'
        : '—';

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
