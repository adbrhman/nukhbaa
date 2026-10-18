library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_providers.dart';
import '../../fixture_report.dart';
import '../../widgets/admin_awaiting_results.dart';
import '../../widgets/admin_live_score_corrections.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// النتائج والاحتساب — تسجيل نتيجة مباراة، احتساب المباراة، ترحيلها
/// للسجل، وتقرير المباراة التفصيلي.
///
/// معرّف المباراة يُختار من قوائم منسدلة (المسابقة ← الموسم ← المباراة)،
/// وليس بإدخال UUID يدوي — مطابقةً لنمط `FixtureScheduleSection` (Axiom 4
/// Amendment: بلا Round — راجع 7.10 في docs/project-context.md).
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
  String? _fixtureId;

  /// The picked matches by name ("Arsenal × Chelsea"), for the
  /// confirmations and the results (audit L-11: the success line used to
  /// show the match's id).
  final Map<String, String> _names = <String, String>{};

  @override
  void initState() {
    super.initState();
    // The record button's enabled state depends on these two fields, and a
    // TextEditingController does not rebuild anything on its own -- so the
    // button has to be told when the score is typed.
    _homeGoals.addListener(_onGoalsChanged);
    _awayGoals.addListener(_onGoalsChanged);
  }

  void _onGoalsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _homeGoals.removeListener(_onGoalsChanged);
    _awayGoals.removeListener(_onGoalsChanged);
    _homeGoals.dispose();
    _awayGoals.dispose();
    super.dispose();
  }

  /// Whether the two score fields currently hold a recordable result.
  bool get _goalsAreValid {
    final int? home = int.tryParse(_homeGoals.text.trim());
    final int? away = int.tryParse(_awayGoals.text.trim());
    return home != null && away != null && home >= 0 && away >= 0;
  }

  static String _teamsOf(SeasonFixtureCardDto fixture) =>
      '${fixture.homeTeam ?? 'غير محدد'} × ${fixture.awayTeam ?? 'غير محدد'}';

  void _remember(SeasonFixtureCardDto fixture) =>
      _names[fixture.fixtureId] = _teamsOf(fixture);

  String _nameOf(String fixtureId) => _names[fixtureId] ?? 'المباراة';

  /// Asks before a command that changes players' points (audit L-11).
  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('admin.results.confirm'),
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.results.confirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('admin.results.confirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _recordResult() async {
    final f = _fixtureId;
    final s = _resultSeasonId;
    final h = int.tryParse(_homeGoals.text.trim());
    final a = int.tryParse(_awayGoals.text.trim());
    if (f == null || s == null || h == null || a == null) return;
    final bool confirmed = await _confirm(
      title: 'تسجيل النتيجة؟',
      body:
          '${_nameOf(f)}: $h-$a\n\nتأكد منها قبل الحفظ: عليها تُحسب نقاط '
          'اللاعبين.',
      action: 'سجّل',
    );
    if (!confirmed) return;
    await ref
        .read(recordFixtureResultControllerProvider.notifier)
        .record(fixtureId: f, seasonId: s, homeGoals: h, awayGoals: a);
  }

  Future<void> _scoreFixture() async {
    final f = _fixtureId;
    final s = _resultSeasonId;
    if (f == null || s == null) return;
    final bool confirmed = await _confirm(
      title: 'احتساب المباراة؟',
      body:
          '${_nameOf(f)}\n\nتُحسب نقاط توقعات المباراة من نتيجتها '
          'المسجّلة.',
      action: 'احسب',
    );
    if (!confirmed) return;
    await ref.read(scoreFixtureControllerProvider.notifier).score(f, s);
  }

  Future<void> _postFixtureToLedger() async {
    final f = _fixtureId;
    final s = _resultSeasonId;
    if (f == null || s == null) return;
    final bool confirmed = await _confirm(
      title: 'الترحيل إلى السجل؟',
      body:
          '${_nameOf(f)}\n\nتُرحَّل نقاط المباراة إلى سجل النقاط، وما رُحّل '
          'من قبل لا يتكرر.',
      action: 'رحّل',
    );
    if (!confirmed) return;
    await ref.read(postFixtureToLedgerControllerProvider.notifier).post(f, s);
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

    // Was `!resultInFlight && _fixtureId != null`: with an empty or
    // non-numeric score the button stayed live, and tapping it returned
    // silently from _recordResult with nothing on screen to explain why.
    final bool canRecord =
        !resultInFlight && _fixtureId != null && _goalsAreValid;
    final bool canScoreFixture =
        _fixtureId != null && scoreFixtureState is! AsyncLoading;
    final bool canPostFixtureLedger =
        _fixtureId != null && postFixtureLedgerState is! AsyncLoading;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminRecordResultSectionTitle,
          subtitle: 'اختر المسابقة والموسم ثم المباراة وسجّل نتيجتها',
        ),
        const AdminLiveScoreCorrections(),
        AdminAwaitingResults(
          onPick: (CurrentMonthFixtureItemDto item) => setState(() {
            _resultCompetitionId = item.competitionId;
            _resultSeasonId = item.fixture.seasonId;
            _fixtureId = item.fixture.fixtureId;
            _remember(item.fixture);
            _homeGoals.clear();
            _awayGoals.clear();
          }),
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
                    _fixtureId = null;
                  }),
                ),
              ],
              if (_resultSeasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.results.record',
                  seasonId: _resultSeasonId!,
                  enabled: !resultInFlight,
                  selectedId: _fixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {
                    _fixtureId = fixture.fixtureId;
                    _remember(fixture);
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AdminTextField(
                      key: const Key('admin.results.homeGoals'),
                      controller: _homeGoals,
                      hint: l10n.adminHomeGoalsLabel,
                      keyboardType: TextInputType.number,
                      enabled: !resultInFlight,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminTextField(
                      key: const Key('admin.results.awayGoals'),
                      controller: _awayGoals,
                      hint: l10n.adminAwayGoalsLabel,
                      keyboardType: TextInputType.number,
                      enabled: !resultInFlight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.adminResultRuleHint,
                key: const Key('admin.results.ruleHint'),
                style: context.text.bodySmall?.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (resultState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(resultState!.error),
                ),
              if (resultState is AsyncData)
                AdminSuccessBanner(
                  key: const Key('admin.results.recorded'),
                  message:
                      'سُجّلت النتيجة: '
                      '${_nameOf(resultState!.value!.fixtureId)} '
                      '${resultState.value!.homeGoals}-'
                      '${resultState.value!.awayGoals}',
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.results.record'),
                label: l10n.adminRecordResultButton,
                icon: Icons.scoreboard_rounded,
                loading: resultInFlight,
                onPressed: canRecord ? _recordResult : null,
              ),
              const SizedBox(height: AppSpacing.md),
              if (scoreFixtureState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(scoreFixtureState!.error),
                ),
              if (scoreFixtureState is AsyncData<FixtureScoresDto>)
                AdminSuccessBanner(
                  message:
                      'تم الاحتساب — عدد التوقعات المحتسبة: '
                      '${scoreFixtureState.value.scores.length}',
                ),
              if (postFixtureLedgerState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(
                    postFixtureLedgerState!.error,
                  ),
                ),
              if (postFixtureLedgerState
                  is AsyncData<PostFixtureToLedgerResponseDto>)
                AdminSuccessBanner(
                  message:
                      'تم الترحيل — قيود جديدة: '
                      '${postFixtureLedgerState.value.appendedEntries.length} '
                      '(صفر يعني أنّ المباراة مُرحّلة مسبقًا)',
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AdminPrimaryButton(
                      key: const Key('admin.results.score'),
                      label: l10n.adminScoreFixtureButton,
                      icon: Icons.calculate_rounded,
                      loading: scoreFixtureState is AsyncLoading,
                      onPressed: canScoreFixture ? _scoreFixture : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminSecondaryButton(
                      key: const Key('admin.results.post'),
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
                  message: ErrorPresenter.messageOf(fixtureReportState!.error),
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

/// الاحتياط حين لا يصل اسم معروض من الخادم: مقطع قصير من المعرّف بدل
/// UUID كامل يملأ السطر.
String _shortId(String participantId) => participantId.length <= 8
    ? participantId
    : '${participantId.substring(0, 8)}…';

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
              row.displayName.isNotEmpty
                  ? row.displayName
                  : _shortId(row.participantId),
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
