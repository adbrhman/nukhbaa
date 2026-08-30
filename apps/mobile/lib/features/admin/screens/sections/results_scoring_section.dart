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
import '../../fixture_report.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// النتائج والاحتساب — تسجيل نتيجة مباراة، احتساب المباراة، ترحيلها
/// للسجل، وتقرير المباراة التفصيلي.
///
/// معرّف المباراة يُختار من قوائم منسدلة (المسابقة ← الموسم ← الجولة ←
/// المباراة)، وليس بإدخال UUID يدوي — مطابقةً لنمط
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

  void _scoreFixture() {
    final f = _fixtureId;
    if (f == null) return;
    ref.read(scoreFixtureControllerProvider.notifier).score(f);
  }

  void _postFixtureToLedger() {
    final f = _fixtureId;
    if (f == null) return;
    ref.read(postFixtureToLedgerControllerProvider.notifier).post(f);
  }

  void _loadFixtureReport() {
    final f = _fixtureId;
    if (f == null) return;
    ref.read(fixtureReportControllerProvider.notifier).load(f);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultState = ref.watch(recordFixtureResultControllerProvider);
    final scoreFixtureState = ref.watch(scoreFixtureControllerProvider);
    final postFixtureLedgerState = ref.watch(
      postFixtureToLedgerControllerProvider,
    );
    final fixtureReportState = ref.watch(fixtureReportControllerProvider);
    final resultInFlight = resultState is AsyncLoading;
    final fixtureReportInFlight = fixtureReportState is AsyncLoading;

    final bool canRecord = !resultInFlight && _fixtureId != null;
    final bool canScoreFixture =
        _fixtureId != null && scoreFixtureState is! AsyncLoading;
    final bool canPostFixtureLedger =
        _fixtureId != null && postFixtureLedgerState is! AsyncLoading;

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
              const SizedBox(height: AppSpacing.md),
              if (scoreFixtureState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    scoreFixtureState!.error as AppError,
                  ),
                ),
              if (postFixtureLedgerState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    postFixtureLedgerState!.error as AppError,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: AdminPrimaryButton(
                      label: l10n.adminScoreFixtureButton,
                      icon: Icons.calculate_rounded,
                      loading: scoreFixtureState is AsyncLoading,
                      onPressed: canScoreFixture ? _scoreFixture : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminSecondaryButton(
                      label: l10n.adminPostFixtureLedgerButton,
                      icon: Icons.receipt_long_rounded,
                      loading: postFixtureLedgerState is AsyncLoading,
                      onPressed: canPostFixtureLedger
                          ? _postFixtureToLedger
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (fixtureReportState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    fixtureReportState!.error as AppError,
                  ),
                ),
              if (fixtureReportState is AsyncError)
                const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                label: l10n.adminViewFixtureReportButton,
                icon: Icons.table_chart_rounded,
                loading: fixtureReportInFlight,
                onPressed: fixtureReportInFlight || _fixtureId == null
                    ? null
                    : _loadFixtureReport,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (fixtureReportState is AsyncData<List<FixtureReportRow>>)
          Builder(
            builder: (context) {
              final rows = fixtureReportState.value;
              if (rows.isEmpty) {
                return AdminCard(
                  child: AdminEmptyState(
                    icon: Icons.table_chart_rounded,
                    title: l10n.adminFixtureReportSectionEmpty,
                  ),
                );
              }
              return Column(
                children: [
                  for (final row in rows) ...[
                    _FixtureReportRowCard(row: row),
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

class _FixtureReportRowCard extends StatelessWidget {
  const _FixtureReportRowCard({required this.row});

  final FixtureReportRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rankColor = switch (row.rank) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.primary,
    };
    final (gradeColor, gradeLabel) = switch (row.grade) {
      'exact_scoreline' => (t.gold, 'نتيجة مطابقة'),
      'correct_outcome' => (t.primary, 'نتيجة صحيحة'),
      'incorrect' => (t.error, 'خاطئ'),
      'missed' => (t.textMuted, 'لم يشارك'),
      'pending' => (t.textSecondary, 'بانتظار النتيجة'),
      _ => (t.textMuted, row.grade),
    };
    final scoreText = row.hasRawScore
        ? '${row.homeGoals}-${row.awayGoals}'
        : '—';

    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
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
          if (row.isDouble) ...[
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
          Container(
            width: 1,
            height: 14,
            color: gradeColor.withValues(alpha: 0.3),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            gradeLabel,
            style: context.text.labelSmall?.copyWith(
              color: gradeColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${row.points})',
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
