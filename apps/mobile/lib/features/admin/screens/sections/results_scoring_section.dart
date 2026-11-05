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

/// النتائج والاحتساب — زر واحد «اعتماد النتيجة» يسجّل نتيجة المباراة ثم
/// يحتسبها ويرحّلها للسجل ويعرض تقرير توقعات اللاعبين (script 214: كانت
/// أربعة أزرار تُضغط بالترتيب).
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

  /// True from the confirmation to the last step of one settle run: the
  /// button ignores a second tap meanwhile.
  bool _settling = false;

  /// The step under way, for the line under the button.
  String? _stage;

  /// How many steps of the latest run succeeded: 1 the result is recorded,
  /// 2 it is scored, 3 it is posted to the ledger. The banners of a step show
  /// only once the run reached it, so a banner of an earlier run never
  /// reads as this run's.
  int _reached = 0;

  /// Said when a run stopped after the result was saved: what is left, and
  /// that tapping the button again finishes it.
  String? _resume;

  /// The match the latest run was for: its banners show only while that
  /// match is the picked one.
  String? _runFixtureId;

  /// The match whose report is on screen.
  String? _reportFixtureId;

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

  void _stageIs(String? stage) {
    if (mounted) setState(() => _stage = stage);
  }

  /// One tap, four steps in order: record the result, score the match,
  /// post its points to the ledger, load the players' predictions report.
  /// Each step is idempotent on the server, so after a failure the same tap
  /// converges: it records the same score again and carries on from there.
  Future<void> _settleResult() async {
    if (_settling) return;
    final f = _fixtureId;
    final s = _resultSeasonId;
    final h = int.tryParse(_homeGoals.text.trim());
    final a = int.tryParse(_awayGoals.text.trim());
    if (f == null || s == null || h == null || a == null) return;
    final bool confirmed = await _confirm(
      title: 'اعتماد النتيجة؟',
      body:
          '${_nameOf(f)}: $h-$a\n\nتُسجَّل النتيجة، ثم تُحسب نقاط التوقعات '
          'وتُرحَّل إلى سجل النقاط، ثم يظهر تقرير توقعات اللاعبين. تأكد منها '
          'قبل الاعتماد: عليها تُحسب نقاط اللاعبين، وما رُحّل من قبل لا '
          'يتكرر.',
      action: 'اعتمد',
    );
    if (!confirmed) return;

    setState(() {
      _settling = true;
      _runFixtureId = f;
      _reached = 0;
      _resume = null;
      _reportFixtureId = null;
    });
    try {
      _stageIs('جارٍ تسجيل النتيجة…');
      await ref
          .read(recordFixtureResultControllerProvider.notifier)
          .record(fixtureId: f, seasonId: s, homeGoals: h, awayGoals: a);
      if (!mounted ||
          ref.read(recordFixtureResultControllerProvider)
              is! AsyncData<FixtureResultDto>) {
        return;
      }
      setState(() => _reached = 1);

      _stageIs('جارٍ احتساب نقاط التوقعات…');
      await ref.read(scoreFixtureControllerProvider.notifier).score(f, s);
      if (!mounted ||
          ref.read(scoreFixtureControllerProvider)
              is! AsyncData<FixtureScoresDto>) {
        _resumeLine('احتساب النقاط');
        return;
      }
      setState(() => _reached = 2);

      _stageIs('جارٍ الترحيل إلى سجل النقاط…');
      await ref.read(postFixtureToLedgerControllerProvider.notifier).post(f, s);
      if (!mounted ||
          ref.read(postFixtureToLedgerControllerProvider)
              is! AsyncData<PostFixtureToLedgerResponseDto>) {
        _resumeLine('الترحيل إلى السجل');
        return;
      }
      setState(() => _reached = 3);

      _stageIs('جارٍ تجهيز تقرير التوقعات…');
      await ref.read(fixtureReportControllerProvider.notifier).load(f);
      if (mounted) setState(() => _reportFixtureId = f);
    } finally {
      if (mounted) {
        setState(() {
          _settling = false;
          _stage = null;
        });
      }
    }
  }

  /// Names the step a run stopped at, after the result was already saved.
  void _resumeLine(String step) {
    if (!mounted) return;
    setState(
      () => _resume =
          'النتيجة محفوظة، وتوقّف الاعتماد عند «$step». اضغط «اعتماد '
          'النتيجة» مرة أخرى ليكمل: ما تمّ لا يتكرر.',
    );
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

    // With an empty or non-numeric score the button stays off, so a tap is
    // never swallowed silently; and it is off while a run is under way.
    final bool canSettle = !_settling && _fixtureId != null && _goalsAreValid;
    final bool reportShown =
        _reportFixtureId != null && _reportFixtureId == _fixtureId;
    final bool sameRun = _runFixtureId != null && _runFixtureId == _fixtureId;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminRecordResultSectionTitle,
          subtitle:
              'اختر المسابقة والموسم ثم المباراة، واعتمد نتيجتها بزر واحد',
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
                enabled: !_settling,
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
                  enabled: !_settling,
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
                  enabled: !_settling,
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
                      enabled: !_settling,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AdminTextField(
                      key: const Key('admin.results.awayGoals'),
                      controller: _awayGoals,
                      hint: l10n.adminAwayGoalsLabel,
                      keyboardType: TextInputType.number,
                      enabled: !_settling,
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
              if (sameRun && resultState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(resultState!.error),
                ),
              if (sameRun && resultState is AsyncData)
                AdminSuccessBanner(
                  key: const Key('admin.results.recorded'),
                  message:
                      'سُجّلت النتيجة: '
                      '${_nameOf(resultState!.value!.fixtureId)} '
                      '${resultState.value!.homeGoals}-'
                      '${resultState.value!.awayGoals}',
                ),
              if (sameRun && _reached >= 1 && scoreFixtureState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(scoreFixtureState!.error),
                ),
              if (sameRun &&
                  _reached >= 2 &&
                  scoreFixtureState is AsyncData<FixtureScoresDto>)
                AdminSuccessBanner(
                  message:
                      'تم الاحتساب — عدد التوقعات المحتسبة: '
                      '${scoreFixtureState.value.scores.length}',
                ),
              if (sameRun &&
                  _reached >= 2 &&
                  postFixtureLedgerState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(
                    postFixtureLedgerState!.error,
                  ),
                ),
              if (sameRun &&
                  _reached >= 3 &&
                  postFixtureLedgerState
                      is AsyncData<PostFixtureToLedgerResponseDto>)
                AdminSuccessBanner(
                  message:
                      'تم الترحيل — قيود جديدة: '
                      '${postFixtureLedgerState.value.appendedEntries.length} '
                      '(صفر يعني أنّ المباراة مُرحّلة مسبقًا)',
                ),
              if (sameRun && _reached >= 3 && fixtureReportState is AsyncError)
                AdminErrorBanner(
                  message: ErrorPresenter.messageOf(fixtureReportState!.error),
                ),
              if (sameRun && _resume != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    _resume!,
                    key: const Key('admin.results.resume'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.tokens.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              AdminPrimaryButton(
                key: const Key('admin.results.record'),
                label: 'اعتماد النتيجة',
                icon: Icons.scoreboard_rounded,
                loading: _settling,
                onPressed: canSettle ? _settleResult : null,
              ),
              if (_stage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _stage!,
                  key: const Key('admin.results.stage'),
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: context.tokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportShown &&
            fixtureReportState is AsyncData<List<FixtureReportRow>>)
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
