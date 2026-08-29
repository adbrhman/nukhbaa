#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd /home/dev/nukhbaa-backup-1787537565

echo "==> [1/6] إنشاء fixture_report.dart (mobile, دمج نقي بلا شبكة)"
cat > apps/mobile/lib/features/admin/fixture_report.dart << 'DARTEOF'
import 'package:contracts/contracts.dart';

/// One participant's row in the fixture report: rank, total points for this
/// single fixture, the server-computed grade, and the raw predicted
/// scoreline from the admin's raw-predictions read.
///
/// Pure UI-layer merge — no network, no server logic. [rank] is 1-based,
/// assigned by [buildFixtureReport] after sorting by [points] descending
/// (ties keep the server's stable participant-id order, never re-sorted by
/// name — there is no display name guaranteed on this wire shape).
///
/// The per-fixture sibling of `RoundReportRow` (`round_report.dart`) — one
/// fixture means one grade/points pair per participant, so there is no
/// per-fixture cell list to wrap (unlike the round report's `cells`).
final class FixtureReportRow {
  const FixtureReportRow({
    required this.rank,
    required this.participantId,
    required this.grade,
    required this.points,
    this.displayName = '',
    this.homeGoals,
    this.awayGoals,
    this.isDouble = false,
  });

  final int rank;
  final String participantId;
  final String displayName;

  /// The stable wire token: `exact_scoreline` / `correct_outcome` /
  /// `incorrect` / `missed` / `pending`.
  final String grade;
  final int points;

  /// The raw predicted scoreline (nullable: a participant who never
  /// predicted this fixture is covered by a `missed` grade with no raw
  /// score).
  final int? homeGoals;
  final int? awayGoals;
  final bool isDouble;

  bool get hasRawScore => homeGoals != null && awayGoals != null;
}

/// Merges a scored fixture's [scores] (grades + points) with the admin's raw
/// [rawPredictions] (predicted scorelines) into a ranked [FixtureReportRow]
/// list, sorted by points descending. The per-fixture sibling of
/// `buildRoundReport` (`round_report.dart`).
List<FixtureReportRow> buildFixtureReport({
  required FixtureScoresDto scores,
  required List<FixturePredictionDto> rawPredictions,
}) {
  final rawByParticipant = <String, FixturePredictionDto>{
    for (final p in rawPredictions) p.participantId: p,
  };

  final sorted = [...scores.scores]
    ..sort((a, b) => b.points.compareTo(a.points));

  return [
    for (var i = 0; i < sorted.length; i++)
      _row(rank: i + 1, score: sorted[i], rawByParticipant: rawByParticipant),
  ];
}

FixtureReportRow _row({
  required int rank,
  required ParticipantFixtureScoreDto score,
  required Map<String, FixturePredictionDto> rawByParticipant,
}) {
  final raw = rawByParticipant[score.participantId];
  return FixtureReportRow(
    rank: rank,
    participantId: score.participantId,
    displayName: score.displayName,
    grade: score.grade,
    points: score.points,
    homeGoals: raw?.homeGoals,
    awayGoals: raw?.awayGoals,
    isDouble: raw?.isDouble ?? false,
  );
}
DARTEOF

echo "==> [2/6] إنشاء fixture_report_test.dart (نظير round_report_test.dart)"
cat > apps/mobile/test/features/admin/fixture_report_test.dart << 'DARTEOF'
import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/fixture_report.dart';

ParticipantFixtureScoreDto _score(
  String participantId,
  int points, {
  String grade = 'correct_outcome',
}) => ParticipantFixtureScoreDto(
  fixtureId: 'fx-1',
  participantId: participantId,
  rulesetVersion: 1,
  grade: grade,
  points: points,
);

FixturePredictionDto _prediction(
  String participantId, {
  int homeGoals = 1,
  int awayGoals = 1,
  bool isDouble = false,
}) => FixturePredictionDto(
  id: 'pred-$participantId',
  participantId: participantId,
  fixtureId: 'fx-1',
  submittedAt: '2026-08-01T12:00:00Z',
  homeGoals: homeGoals,
  awayGoals: awayGoals,
  isDouble: isDouble,
);

void main() {
  test('ranks participants by points descending', () {
    final scores = FixtureScoresDto(
      fixtureId: 'fx-1',
      scores: [
        _score('p-low', 3),
        _score('p-high', 10, grade: 'exact_scoreline'),
      ],
    );
    final raw = [
      _prediction('p-low'),
      _prediction('p-high', homeGoals: 2, awayGoals: 0, isDouble: true),
    ];

    final rows = buildFixtureReport(scores: scores, rawPredictions: raw);

    expect(rows, hasLength(2));
    expect(rows[0].participantId, 'p-high');
    expect(rows[0].rank, 1);
    expect(rows[0].homeGoals, 2);
    expect(rows[0].awayGoals, 0);
    expect(rows[0].isDouble, isTrue);
    expect(rows[1].participantId, 'p-low');
    expect(rows[1].rank, 2);
  });

  test(
    'a row with no matching raw prediction has null scores (missed fixture)',
    () {
      const scores = FixtureScoresDto(
        fixtureId: 'fx-1',
        scores: [
          ParticipantFixtureScoreDto(
            fixtureId: 'fx-1',
            participantId: 'p1',
            rulesetVersion: 1,
            grade: 'missed',
            points: 0,
          ),
        ],
      );

      final rows = buildFixtureReport(scores: scores, rawPredictions: const []);

      expect(rows.single.hasRawScore, isFalse);
      expect(rows.single.grade, 'missed');
    },
  );

  test('an empty scored fixture produces an empty report', () {
    const scores = FixtureScoresDto(fixtureId: 'fx-1', scores: []);
    final rows = buildFixtureReport(scores: scores, rawPredictions: const []);
    expect(rows, isEmpty);
  });
}
DARTEOF

echo "==> [3/6] تعديلات نصية دقيقة (python) على الملفات القائمة"
python3 << 'PYEOF'
import sys

def replace_once(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        print(f"FAIL [{label}] في {path}: توقعت تطابقًا واحدًا، وجدت {count}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK [{label}] -> {path}")

# --- admin_providers.dart: استيراد ---
ap = "apps/mobile/lib/features/admin/admin_providers.dart"
replace_once(
    ap,
    "import '../../core/providers.dart';\nimport 'round_report.dart';",
    "import '../../core/providers.dart';\nimport 'fixture_report.dart';\nimport 'round_report.dart';",
    "admin_providers import",
)

# --- admin_providers.dart: FixtureReportController ---
replace_once(
    ap,
    "    state = AsyncValue.data(\n"
    "      buildRoundReport(scores: scores, rawPredictions: predictions),\n"
    "    );\n"
    "  }\n"
    "}\n"
    "\n"
    "/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.",
    "    state = AsyncValue.data(\n"
    "      buildRoundReport(scores: scores, rawPredictions: predictions),\n"
    "    );\n"
    "  }\n"
    "}\n"
    "\n"
    "/// Owns the fixture-report bulk read: fetches `GET /admin/fixtures/{id}/scores`\n"
    "/// and `GET /admin/fixtures/{id}/predictions` (both `AdminApi`, the second\n"
    "/// itself audited) concurrently — admin-only, no season-participation gate\n"
    "/// (mirrors [RoundReportController]; the per-fixture sibling, added so an\n"
    "/// admin can review any fixture's predictions/scores regardless of the\n"
    "/// admin's own season membership, for investigating user complaints).\n"
    "/// Modelled as a controller for the same reason as [RoundReportController].\n"
    "@riverpod\n"
    "class FixtureReportController extends _$FixtureReportController {\n"
    "  AdminApi get _adminApi => ref.read(adminApiProvider);\n"
    "\n"
    "  @override\n"
    "  AsyncValue<List<FixtureReportRow>>? build() => null;\n"
    "\n"
    "  /// Loads the report for [fixtureId]. [reason] is an optional justification\n"
    "  /// recorded on the raw-predictions audit entry.\n"
    "  ///\n"
    "  /// Both calls run concurrently; either failing surfaces its error and skips\n"
    "  /// the merge (same all-or-nothing rationale as [RoundReportController]).\n"
    "  Future<void> load(String fixtureId, {String? reason}) async {\n"
    "    state = const AsyncValue.loading();\n"
    "    final results = await (\n"
    "      _adminApi.adminGetFixtureScores(fixtureId),\n"
    "      _adminApi.adminListFixturePredictions(fixtureId, reason: reason),\n"
    "    ).wait;\n"
    "    final scoresResult = results.$1;\n"
    "    final predictionsResult = results.$2;\n"
    "\n"
    "    if (scoresResult is Err<FixtureScoresDto>) {\n"
    "      state = AsyncValue.error(scoresResult.error, StackTrace.current);\n"
    "      return;\n"
    "    }\n"
    "    if (predictionsResult is Err<List<FixturePredictionDto>>) {\n"
    "      state = AsyncValue.error(predictionsResult.error, StackTrace.current);\n"
    "      return;\n"
    "    }\n"
    "\n"
    "    final scores = (scoresResult as Ok<FixtureScoresDto>).value;\n"
    "    final predictions =\n"
    "        (predictionsResult as Ok<List<FixturePredictionDto>>).value;\n"
    "    state = AsyncValue.data(\n"
    "      buildFixtureReport(scores: scores, rawPredictions: predictions),\n"
    "    );\n"
    "  }\n"
    "}\n"
    "\n"
    "/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.",
    "FixtureReportController",
)

# --- results_scoring_section.dart: استيراد ---
rs = "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"
replace_once(
    rs,
    "import '../../admin_providers.dart';\nimport '../../round_report.dart';",
    "import '../../admin_providers.dart';\nimport '../../fixture_report.dart';\nimport '../../round_report.dart';",
    "results_scoring_section import",
)

# --- results_scoring_section.dart: دالة _loadFixtureReport ---
replace_once(
    rs,
    "  void _postFixtureToLedger() {\n"
    "    final f = _fixtureId;\n"
    "    if (f == null) return;\n"
    "    ref.read(postFixtureToLedgerControllerProvider.notifier).post(f);\n"
    "  }\n"
    "\n"
    "  void _scoreRound() {",
    "  void _postFixtureToLedger() {\n"
    "    final f = _fixtureId;\n"
    "    if (f == null) return;\n"
    "    ref.read(postFixtureToLedgerControllerProvider.notifier).post(f);\n"
    "  }\n"
    "\n"
    "  void _loadFixtureReport() {\n"
    "    final f = _fixtureId;\n"
    "    if (f == null) return;\n"
    "    ref.read(fixtureReportControllerProvider.notifier).load(f);\n"
    "  }\n"
    "\n"
    "  void _scoreRound() {",
    "_loadFixtureReport method",
)

# --- results_scoring_section.dart: watch state ---
replace_once(
    rs,
    "    final scoreFixtureState = ref.watch(scoreFixtureControllerProvider);\n"
    "    final postFixtureLedgerState = ref.watch(\n"
    "      postFixtureToLedgerControllerProvider,\n"
    "    );\n"
    "    final resultInFlight = resultState is AsyncLoading;\n"
    "    final scoreInFlight = scoreState is AsyncLoading;\n"
    "    final lookupInFlight = lookupState is AsyncLoading;\n"
    "    final reportInFlight = reportState is AsyncLoading;",
    "    final scoreFixtureState = ref.watch(scoreFixtureControllerProvider);\n"
    "    final postFixtureLedgerState = ref.watch(\n"
    "      postFixtureToLedgerControllerProvider,\n"
    "    );\n"
    "    final fixtureReportState = ref.watch(fixtureReportControllerProvider);\n"
    "    final resultInFlight = resultState is AsyncLoading;\n"
    "    final scoreInFlight = scoreState is AsyncLoading;\n"
    "    final lookupInFlight = lookupState is AsyncLoading;\n"
    "    final reportInFlight = reportState is AsyncLoading;\n"
    "    final fixtureReportInFlight = fixtureReportState is AsyncLoading;",
    "watch fixtureReportState",
)

# --- results_scoring_section.dart: زر + عرض تقرير المباراة ---
replace_once(
    rs,
    "                  Expanded(\n"
    "                    child: AdminSecondaryButton(\n"
    "                      label: l10n.adminPostFixtureLedgerButton,\n"
    "                      icon: Icons.receipt_long_rounded,\n"
    "                      loading: postFixtureLedgerState is AsyncLoading,\n"
    "                      onPressed: canPostFixtureLedger\n"
    "                          ? _postFixtureToLedger\n"
    "                          : null,\n"
    "                    ),\n"
    "                  ),\n"
    "                ],\n"
    "              ),\n"
    "            ],\n"
    "          ),\n"
    "        ),\n"
    "        const SizedBox(height: AppSpacing.xl),",
    "                  Expanded(\n"
    "                    child: AdminSecondaryButton(\n"
    "                      label: l10n.adminPostFixtureLedgerButton,\n"
    "                      icon: Icons.receipt_long_rounded,\n"
    "                      loading: postFixtureLedgerState is AsyncLoading,\n"
    "                      onPressed: canPostFixtureLedger\n"
    "                          ? _postFixtureToLedger\n"
    "                          : null,\n"
    "                    ),\n"
    "                  ),\n"
    "                ],\n"
    "              ),\n"
    "              const SizedBox(height: AppSpacing.md),\n"
    "              if (fixtureReportState is AsyncError)\n"
    "                AdminErrorBanner(\n"
    "                  message: ErrorPresenter.message(\n"
    "                    fixtureReportState!.error as AppError,\n"
    "                  ),\n"
    "                ),\n"
    "              if (fixtureReportState is AsyncError)\n"
    "                const SizedBox(height: AppSpacing.sm),\n"
    "              AdminSecondaryButton(\n"
    "                label: l10n.adminViewFixtureReportButton,\n"
    "                icon: Icons.table_chart_rounded,\n"
    "                loading: fixtureReportInFlight,\n"
    "                onPressed: fixtureReportInFlight || _fixtureId == null\n"
    "                    ? null\n"
    "                    : _loadFixtureReport,\n"
    "              ),\n"
    "            ],\n"
    "          ),\n"
    "        ),\n"
    "        const SizedBox(height: AppSpacing.md),\n"
    "        if (fixtureReportState is AsyncData<List<FixtureReportRow>>)\n"
    "          Builder(\n"
    "            builder: (context) {\n"
    "              final rows = fixtureReportState.value;\n"
    "              if (rows.isEmpty) {\n"
    "                return AdminCard(\n"
    "                  child: AdminEmptyState(\n"
    "                    icon: Icons.table_chart_rounded,\n"
    "                    title: l10n.adminFixtureReportSectionEmpty,\n"
    "                  ),\n"
    "                );\n"
    "              }\n"
    "              return Column(\n"
    "                children: [\n"
    "                  for (final row in rows) ...[\n"
    "                    _FixtureReportRowCard(row: row),\n"
    "                    const SizedBox(height: AppSpacing.sm),\n"
    "                  ],\n"
    "                ],\n"
    "              );\n"
    "            },\n"
    "          ),\n"
    "        const SizedBox(height: AppSpacing.xl),",
    "زر وعرض تقرير المباراة",
)

# --- results_scoring_section.dart: ودجت _FixtureReportRowCard ---
replace_once(
    rs,
    "          const SizedBox(width: 6),\n"
    "          Text(\n"
    "            '(${cell.points})',\n"
    "            style: context.text.labelSmall?.copyWith(color: t.textSecondary),\n"
    "          ),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }\n"
    "}",
    "          const SizedBox(width: 6),\n"
    "          Text(\n"
    "            '(${cell.points})',\n"
    "            style: context.text.labelSmall?.copyWith(color: t.textSecondary),\n"
    "          ),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }\n"
    "}\n"
    "\n"
    "class _FixtureReportRowCard extends StatelessWidget {\n"
    "  const _FixtureReportRowCard({required this.row});\n"
    "\n"
    "  final FixtureReportRow row;\n"
    "\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    final t = context.tokens;\n"
    "    final rankColor = switch (row.rank) {\n"
    "      1 => t.gold,\n"
    "      2 => t.silver,\n"
    "      3 => t.bronze,\n"
    "      _ => t.primary,\n"
    "    };\n"
    "    final (gradeColor, gradeLabel) = switch (row.grade) {\n"
    "      'exact_scoreline' => (t.gold, 'نتيجة مطابقة'),\n"
    "      'correct_outcome' => (t.primary, 'نتيجة صحيحة'),\n"
    "      'incorrect' => (t.error, 'خاطئ'),\n"
    "      'missed' => (t.textMuted, 'لم يشارك'),\n"
    "      'pending' => (t.textSecondary, 'بانتظار النتيجة'),\n"
    "      _ => (t.textMuted, row.grade),\n"
    "    };\n"
    "    final scoreText = row.hasRawScore\n"
    "        ? '${row.homeGoals}-${row.awayGoals}'\n"
    "        : '—';\n"
    "\n"
    "    return AdminCard(\n"
    "      padding: const EdgeInsets.all(AppSpacing.md),\n"
    "      child: Row(\n"
    "        children: [\n"
    "          Container(\n"
    "            width: 34,\n"
    "            height: 34,\n"
    "            alignment: Alignment.center,\n"
    "            decoration: BoxDecoration(\n"
    "              color: rankColor.withValues(alpha: 0.14),\n"
    "              borderRadius: BorderRadius.circular(10),\n"
    "            ),\n"
    "            child: Text(\n"
    "              '${row.rank}',\n"
    "              style: context.text.titleMedium?.copyWith(\n"
    "                fontWeight: FontWeight.w800,\n"
    "                color: rankColor,\n"
    "              ),\n"
    "            ),\n"
    "          ),\n"
    "          const SizedBox(width: AppSpacing.md),\n"
    "          Expanded(\n"
    "            child: Text(\n"
    "              row.participantId,\n"
    "              maxLines: 1,\n"
    "              overflow: TextOverflow.ellipsis,\n"
    "              style: context.text.bodyLarge?.copyWith(\n"
    "                color: t.textPrimary,\n"
    "                fontWeight: FontWeight.w600,\n"
    "              ),\n"
    "            ),\n"
    "          ),\n"
    "          const SizedBox(width: AppSpacing.sm),\n"
    "          if (row.isDouble) ...[\n"
    "            Icon(Icons.star_rounded, size: 14, color: t.gold),\n"
    "            const SizedBox(width: 4),\n"
    "          ],\n"
    "          Text(\n"
    "            scoreText,\n"
    "            style: context.text.bodyMedium?.copyWith(\n"
    "              color: t.textPrimary,\n"
    "              fontWeight: FontWeight.w700,\n"
    "            ),\n"
    "          ),\n"
    "          const SizedBox(width: AppSpacing.sm),\n"
    "          Container(\n"
    "            width: 1,\n"
    "            height: 14,\n"
    "            color: gradeColor.withValues(alpha: 0.3),\n"
    "          ),\n"
    "          const SizedBox(width: AppSpacing.sm),\n"
    "          Text(\n"
    "            gradeLabel,\n"
    "            style: context.text.labelSmall?.copyWith(\n"
    "              color: gradeColor,\n"
    "              fontWeight: FontWeight.w700,\n"
    "            ),\n"
    "          ),\n"
    "          const SizedBox(width: 6),\n"
    "          Text(\n"
    "            '(${row.points})',\n"
    "            style: context.text.labelSmall?.copyWith(color: t.textSecondary),\n"
    "          ),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }\n"
    "}",
    "_FixtureReportRowCard widget",
)

# --- app_ar.arb ---
replace_once(
    "apps/mobile/lib/l10n/app_ar.arb",
    '  "adminRoundReportSectionEmpty": "لا يوجد تقرير لهذه الجولة بعد",',
    '  "adminRoundReportSectionEmpty": "لا يوجد تقرير لهذه الجولة بعد",\n'
    '  "adminViewFixtureReportButton": "عرض تقرير المباراة",\n'
    '  "adminFixtureReportSectionEmpty": "لا يوجد تقرير لهذه المباراة بعد",',
    "app_ar.arb",
)

# --- app_en.arb ---
replace_once(
    "apps/mobile/lib/l10n/app_en.arb",
    '  "adminRoundReportSectionEmpty": "No report for this round yet",',
    '  "adminRoundReportSectionEmpty": "No report for this round yet",\n'
    '  "adminViewFixtureReportButton": "View fixture report",\n'
    '  "adminFixtureReportSectionEmpty": "No report for this fixture yet",',
    "app_en.arb",
)
PYEOF

echo "==> [4/6] flutter gen-l10n + build_runner (apps/mobile)"
GEN_OK=1
(cd apps/mobile && flutter gen-l10n && flutter pub run build_runner build --delete-conflicting-outputs) || GEN_OK=0

echo "==> [5/6] flutter analyze + flutter test (apps/mobile)"
ANALYZE_OK=1
TEST_OK=1
if [ "$GEN_OK" -eq 1 ]; then
  flutter analyze apps/mobile || ANALYZE_OK=0
  flutter test apps/mobile || TEST_OK=0
else
  ANALYZE_OK=0
  TEST_OK=0
fi

if [ "$GEN_OK" -eq 1 ] && [ "$ANALYZE_OK" -eq 1 ] && [ "$TEST_OK" -eq 1 ]; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi
TS="$(date +%H:%M)"

echo "==> [6/6] تحديث docs/checkpoints/session-log.md (بلا commit/push تلقائي)"
{
  echo "- [$TS] إضافة: fixture_report.dart + FixtureReportController + زر/عرض تقرير المباراة في ResultsScoringSection (نطاق _fixtureId) + مفتاحا ARB جديدان | ملفات: apps/mobile/lib/features/admin/fixture_report.dart, apps/mobile/test/features/admin/fixture_report_test.dart, apps/mobile/lib/features/admin/admin_providers.dart, apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb | اختبار: $TEST_STATUS"
} >> docs/checkpoints/session-log.md

if [ "$GEN_OK" -eq 0 ] || [ "$ANALYZE_OK" -eq 0 ] || [ "$TEST_OK" -eq 0 ]; then
  echo ""
  echo "!! توقف: gen-l10n/build_runner أو analyze أو test فشل. راجع المخرجات أعلاه قبل أي commit."
  exit 1
fi

echo ""
echo "== تم بنجاح =="
echo "git status:"
git status --short
echo ""
echo "لا يوجد commit تلقائي (بطلبك). راجع الـdiff، وإن رضيت نفّذ يدويًا:"
cat << 'MSG'
git add -A
git commit -m "feat(admin): fixture report — mobile-only, mirrors round report

- fixture_report.dart: pure UI-layer merge (FixtureReportRow +
  buildFixtureReport), per-fixture sibling of round_report.dart. No cells
  wrapper — one fixture means one grade/points pair per participant.
- fixture_report_test.dart: 3 unit tests mirroring round_report_test.dart
  (rank by points desc, missing raw prediction, empty report).
- admin_providers.dart: FixtureReportController — concurrent
  adminGetFixtureScores + adminListFixturePredictions fetch, merged via
  buildFixtureReport. Mirrors RoundReportController; uses the
  AdminGetFixtureScores backend layer added in the previous batch.
- results_scoring_section.dart: 'تقرير المباراة' button + report display,
  added to the EXISTING fixture-scoped card (same _fixtureId/
  _resultSeasonId scope as score/post-ledger buttons) — deliberately not a
  new section tied to _roundId, per the round-cleanup-deferred directive.
  New _FixtureReportRowCard widget.
- app_ar.arb / app_en.arb: 2 new keys (adminViewFixtureReportButton,
  adminFixtureReportSectionEmpty).

Closes the mobile-UI gap left by the previous AdminGetFixtureScores batch:
the admin can now actually see a fixture's full participant
predictions+scores in the app, regardless of season membership. No Round
code touched, removed, or migrated."
MSG
