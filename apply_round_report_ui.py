#!/usr/bin/env python3
"""
تطبيق: شاشة/منطق تقرير الجولة بلوحة المشرف (Flutter).
شغّله من جذر nukhbaa-main:  python3 apply_round_report_ui.py
"""
import os

ROOT = os.getcwd()


def replace(path, old, new, label):
    full = os.path.join(ROOT, path)
    with open(full, "r", encoding="utf-8") as f:
        content = f.read()
    if content.count(old) != 1:
        raise SystemExit(
            f"[FAIL] {label}: النص المطلوب غير موجود (أو مكرر) بالملف {path}"
        )
    content = content.replace(old, new, 1)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] {label}")


def write_new(path, content, label):
    full = os.path.join(ROOT, path)
    if os.path.exists(full):
        raise SystemExit(f"[FAIL] {label}: الملف موجود مسبقًا {path}")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] {label} (ملف جديد)")


def append(path, content, label):
    full = os.path.join(ROOT, path)
    with open(full, "r", encoding="utf-8") as f:
        existing = f.read()
    if content.strip() and content.strip() in existing:
        raise SystemExit(f"[FAIL] {label}: المحتوى موجود مسبقًا بالملف {path}")
    with open(full, "a", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] {label} (إلحاق)")


# ---------------------------------------------------------------------------
# 1) api_client: AdminApi.adminListRoundPredictions
# ---------------------------------------------------------------------------
replace(
    "packages/api_client/lib/src/admin_api.dart",
    "  Future<Result<ParticipantEntriesDto>> viewParticipantLedger(\n"
    "    String participantId, {\n"
    "    String? reason,\n"
    "  }) {\n"
    "    return _transport.getObject<ParticipantEntriesDto>(\n"
    "      '/admin/participants/$participantId/ledger',\n"
    "      query: reason == null ? null : {'reason': reason},\n"
    "      parse: ParticipantEntriesDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "}",
    "  Future<Result<ParticipantEntriesDto>> viewParticipantLedger(\n"
    "    String participantId, {\n"
    "    String? reason,\n"
    "  }) {\n"
    "    return _transport.getObject<ParticipantEntriesDto>(\n"
    "      '/admin/participants/$participantId/ledger',\n"
    "      query: reason == null ? null : {'reason': reason},\n"
    "      parse: ParticipantEntriesDto.fromJson,\n"
    "    );\n"
    "  }\n\n"
    "  /// `GET /admin/rounds/{roundId}/predictions` — the round-report bulk read:\n"
    "  /// every participant's raw predicted scorelines for a **scored** round.\n"
    "  /// [reason] is an optional justification recorded on the (mandatory) audit\n"
    "  /// entry for this read; the read itself is always audited server-side\n"
    "  /// regardless of whether one is supplied.\n"
    "  Future<Result<List<PredictionDto>>> adminListRoundPredictions(\n"
    "    String roundId, {\n"
    "    String? reason,\n"
    "  }) {\n"
    "    return _transport.getList<PredictionDto>(\n"
    "      '/admin/rounds/$roundId/predictions',\n"
    "      query: reason == null ? null : {'reason': reason},\n"
    "      parseElement: PredictionDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "}",
    "admin_api.dart: adminListRoundPredictions",
)

# ---------------------------------------------------------------------------
# 2) نموذج الدمج (ملف جديد بحت — قابل للاختبار)
# ---------------------------------------------------------------------------
write_new(
    "apps/mobile/lib/features/admin/round_report.dart",
    '''import 'package:contracts/contracts.dart';

/// One participant's row in the round report: total points, ranking, and the
/// per-fixture breakdown (grade + points from the scored read, plus the raw
/// predicted scoreline from the admin's raw-predictions read).
///
/// Pure UI-layer merge — no network, no server logic. [rank] is 1-based,
/// assigned by [buildRoundReport] after sorting by [totalPoints] descending
/// (ties keep the server's stable participant-id order, never re-sorted by
/// name — there is no display name on this wire shape).
final class RoundReportRow {
  const RoundReportRow({
    required this.rank,
    required this.participantId,
    required this.totalPoints,
    required this.cells,
  });

  final int rank;
  final String participantId;
  final int totalPoints;

  /// One cell per fixture, in the round's fixture order (Axiom 3: named by
  /// fixture id only).
  final List<RoundReportCell> cells;
}

/// One fixture's cell for one participant: the server-computed grade/points
/// (always present — the round is scored) plus the raw predicted scoreline
/// (nullable: a participant who predicted after this cell's fixture was
/// already covered by a `missed` grade never submitted a raw score for it).
final class RoundReportCell {
  const RoundReportCell({
    required this.fixtureId,
    required this.grade,
    required this.points,
    this.homeGoals,
    this.awayGoals,
    this.isDouble = false,
  });

  final String fixtureId;

  /// The stable wire token: `exact_scoreline` / `correct_outcome` /
  /// `incorrect` / `missed`.
  final String grade;
  final int points;
  final int? homeGoals;
  final int? awayGoals;
  final bool isDouble;

  bool get hasRawScore => homeGoals != null && awayGoals != null;
}

/// Merges a scored round's [scores] (grades + points) with the admin's raw
/// [rawPredictions] (predicted scorelines) into a ranked [RoundReportRow]
/// list, sorted by total points descending.
///
/// The fixture *column order* is taken from the first participant's
/// [RoundScoreDto.fixtureResults] (every participant's scored round shares
/// the same fixture set, in the same order — the round's frozen ruleset), so
/// every row renders the same columns even when a raw prediction for one of
/// them is missing.
List<RoundReportRow> buildRoundReport({
  required RoundScoresDto scores,
  required List<PredictionDto> rawPredictions,
}) {
  // participantId -> fixtureId -> raw FixtureScoreDto, for O(1) lookup while
  // building each row's cells.
  final rawByParticipant = <String, Map<String, FixtureScoreDto>>{};
  for (final prediction in rawPredictions) {
    final byFixture = <String, FixtureScoreDto>{
      for (final s in prediction.fixtureScores) s.fixtureId: s,
    };
    rawByParticipant[prediction.participantId] = byFixture;
  }

  final sorted = [...scores.scores]
    ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

  return [
    for (var i = 0; i < sorted.length; i++)
      _row(rank: i + 1, score: sorted[i], rawByParticipant: rawByParticipant),
  ];
}

RoundReportRow _row({
  required int rank,
  required RoundScoreDto score,
  required Map<String, Map<String, FixtureScoreDto>> rawByParticipant,
}) {
  final raw = rawByParticipant[score.participantId];
  return RoundReportRow(
    rank: rank,
    participantId: score.participantId,
    totalPoints: score.totalPoints,
    cells: [
      for (final fr in score.fixtureResults)
        RoundReportCell(
          fixtureId: fr.fixtureId,
          grade: fr.grade,
          points: fr.points,
          homeGoals: raw?[fr.fixtureId]?.homeGoals,
          awayGoals: raw?[fr.fixtureId]?.awayGoals,
          isDouble: raw?[fr.fixtureId]?.isDouble ?? false,
        ),
    ],
  );
}
''',
    "round_report.dart",
)

# ---------------------------------------------------------------------------
# 3) admin_providers.dart — استيراد + RoundReportController (إلحاق بالنهاية)
# ---------------------------------------------------------------------------
replace(
    "apps/mobile/lib/features/admin/admin_providers.dart",
    "import '../../core/providers.dart';\n\npart 'admin_providers.g.dart';",
    "import '../../core/providers.dart';\nimport 'round_report.dart';\n\n"
    "part 'admin_providers.g.dart';",
    "admin_providers.dart: import",
)

append(
    "apps/mobile/lib/features/admin/admin_providers.dart",
    '''
/// Owns the round-report bulk read: fetches `GET /rounds/{id}/scores`
/// (`CompetitionApi`) and `GET /admin/rounds/{id}/predictions` (`AdminApi`,
/// itself audited) concurrently for a **scored** round, then merges them via
/// [buildRoundReport] into a ranked, per-fixture breakdown. Modelled as a
/// controller (rather than a `FutureProvider`) for the same reason as
/// [RoundScoresLookupController]: an admin explicitly triggers the report, it
/// is not a passive view a screen loads on entry — and the raw-predictions
/// half is itself an audited cross-user read that must not fire silently.
@riverpod
class RoundReportController extends _$RoundReportController {
  CompetitionApi get _competitionApi => ref.read(competitionApiProvider);
  AdminApi get _adminApi => ref.read(adminApiProvider);

  @override
  AsyncValue<List<RoundReportRow>>? build() => null;

  /// Loads the report for the scored round [roundId]. [reason] is an
  /// optional justification recorded on the raw-predictions audit entry.
  ///
  /// Both calls run concurrently; either failing surfaces its error and skips
  /// the merge (a round-report is all-or-nothing — a half-merged report with
  /// missing raw scores or missing grades would mislead the admin).
  Future<void> load(String roundId, {String? reason}) async {
    state = const AsyncValue.loading();
    final results = await (
      _competitionApi.getRoundScores(roundId),
      _adminApi.adminListRoundPredictions(roundId, reason: reason),
    ).wait;
    final scoresResult = results.$1;
    final predictionsResult = results.$2;

    if (scoresResult is Err<RoundScoresDto>) {
      state = AsyncValue.error(scoresResult.error, StackTrace.current);
      return;
    }
    if (predictionsResult is Err<List<PredictionDto>>) {
      state = AsyncValue.error(predictionsResult.error, StackTrace.current);
      return;
    }

    final scores = (scoresResult as Ok<RoundScoresDto>).value;
    final predictions = (predictionsResult as Ok<List<PredictionDto>>).value;
    state = AsyncValue.data(
      buildRoundReport(scores: scores, rawPredictions: predictions),
    );
  }
}
''',
    "admin_providers.dart: RoundReportController",
)

# ---------------------------------------------------------------------------
# 4) admin_dashboard_screen.dart — استيراد + إدراج القسم + الودجت
# ---------------------------------------------------------------------------
replace(
    "apps/mobile/lib/features/admin/admin_dashboard_screen.dart",
    "import 'package:contracts/contracts.dart';\n"
    "import 'package:flutter/material.dart';\n"
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
    "import 'package:shared/shared.dart';\n"
    "import '../../core/design/app_spacing.dart';\n"
    "import '../../core/design/app_tokens.dart';\n"
    "import '../../core/error/error_presenter.dart';\n"
    "import '../../l10n/app_localizations.dart';\n"
    "import '../competition/widgets/async_list_view.dart';\n"
    "import 'admin_providers.dart';",
    "import 'package:contracts/contracts.dart';\n"
    "import 'package:flutter/material.dart';\n"
    "import 'package:flutter/services.dart' show Clipboard, ClipboardData;\n"
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
    "import 'package:shared/shared.dart';\n"
    "import '../../core/design/app_spacing.dart';\n"
    "import '../../core/design/app_tokens.dart';\n"
    "import '../../core/error/error_presenter.dart';\n"
    "import '../../l10n/app_localizations.dart';\n"
    "import '../competition/widgets/async_list_view.dart';\n"
    "import 'admin_providers.dart';\n"
    "import 'round_report.dart';",
    "admin_dashboard_screen.dart: imports",
)

replace(
    "apps/mobile/lib/features/admin/admin_dashboard_screen.dart",
    "          else if (scoreState is AsyncData<RoundScoresDto>)\n"
    "            for (final s in scoreState.value.scores)\n"
    "              ListTile(\n"
    "                key: Key(\n"
    "                  'admin.scoring.score.score.${scoreState.value.roundId}.${s.participantId}',\n"
    "                ),\n"
    "                title: Text(s.participantId),\n"
    "                trailing: Text(\n"
    "                  '${l10n.adminTotalPointsLabel}: ${s.totalPoints}',\n"
    "                ),\n"
    "              ),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }",
    "          else if (scoreState is AsyncData<RoundScoresDto>)\n"
    "            for (final s in scoreState.value.scores)\n"
    "              ListTile(\n"
    "                key: Key(\n"
    "                  'admin.scoring.score.score.${scoreState.value.roundId}.${s.participantId}',\n"
    "                ),\n"
    "                title: Text(s.participantId),\n"
    "                trailing: Text(\n"
    "                  '${l10n.adminTotalPointsLabel}: ${s.totalPoints}',\n"
    "                ),\n"
    "              ),\n"
    "          const Divider(height: AppSpacing.x3l),\n"
    "          _RoundReportSection(roundIdController: _roundIdController),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }",
    "admin_dashboard_screen.dart: insert section",
)

append(
    "apps/mobile/lib/features/admin/admin_dashboard_screen.dart",
    '''
/// The round-report section inside [_ResultsScoringTab]: merges
/// `GET /rounds/{id}/scores` with the admin-only
/// `GET /admin/rounds/{id}/predictions` (via [RoundReportController]) into a
/// ranked, per-fixture table (rank, participant, total points, and every
/// fixture's grade + predicted scoreline), plus a copy-to-share summary.
///
/// Reuses the same round-id field as the score lookup above it — the report
/// is scoped to the same round an admin just scored.
class _RoundReportSection extends ConsumerWidget {
  const _RoundReportSection({required this.roundIdController});

  final TextEditingController roundIdController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final AsyncValue<List<RoundReportRow>>? reportState = ref.watch(
      roundReportControllerProvider,
    );
    final bool inFlight =
        reportState is AsyncLoading<List<RoundReportRow>>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.adminRoundReportSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportState is AsyncError<List<RoundReportRow>>)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              ErrorPresenter.message(reportState.error as AppError),
              key: const Key('admin.scoring.report.error'),
              style: TextStyle(color: tokens.error),
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('admin.scoring.viewReport'),
                onPressed: inFlight ? null : () => _load(ref),
                child: Text(l10n.adminViewRoundReportButton),
              ),
            ),
            if (reportState is AsyncData<List<RoundReportRow>> &&
                reportState.value.isNotEmpty) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                key: const Key('admin.scoring.report.share'),
                onPressed: () => _share(context, reportState.value),
                child: Text(l10n.adminRoundReportShareButton),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (reportState is AsyncData<List<RoundReportRow>>)
          if (reportState.value.isEmpty)
            Text(l10n.adminRoundReportEmpty)
          else
            for (final row in reportState.value)
              _RoundReportRowCard(row: row, tokens: tokens, l10n: l10n),
      ],
    );
  }

  void _load(WidgetRef ref) {
    final roundId = roundIdController.text.trim();
    if (roundId.isEmpty) return;
    ref.read(roundReportControllerProvider.notifier).load(roundId);
  }

  void _share(BuildContext context, List<RoundReportRow> rows) {
    final l10n = AppLocalizations.of(context);
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(
        '${row.rank}. ${row.participantId} — ${row.totalPoints}',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.adminRoundReportCopiedMessage)),
    );
  }
}

class _RoundReportRowCard extends StatelessWidget {
  const _RoundReportRowCard({
    required this.row,
    required this.tokens,
    required this.l10n,
  });

  final RoundReportRow row;
  final AppTokens tokens;
  final AppLocalizations l10n;

  Color? _rankColor() => switch (row.rank) {
    1 => tokens.gold,
    2 => tokens.silver,
    3 => tokens.bronze,
    _ => null,
  };

  static String _gradeIcon(String grade) => switch (grade) {
    'exact_scoreline' => '✅',
    'correct_outcome' => '🟡',
    'incorrect' => '❌',
    'missed' => '⏳',
    _ => '?',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('admin.scoring.report.row.${row.participantId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _rankColor() ?? tokens.surfaceHigh,
                  child: Text(
                    '${row.rank}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    row.participantId,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${l10n.adminTotalPointsLabel}: ${row.totalPoints}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final cell in row.cells)
                  Chip(
                    key: Key(
                      'admin.scoring.report.cell.${row.participantId}.${cell.fixtureId}',
                    ),
                    label: Text(
                      cell.hasRawScore
                          ? '${_gradeIcon(cell.grade)} '
                                '${cell.homeGoals}-${cell.awayGoals} '
                                '(${cell.points})${cell.isDouble ? ' x2' : ''}'
                          : '${_gradeIcon(cell.grade)} (${cell.points})',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
''',
    "admin_dashboard_screen.dart: widgets",
)

# ---------------------------------------------------------------------------
# 5) l10n
# ---------------------------------------------------------------------------
replace(
    "apps/mobile/lib/l10n/app_ar.arb",
    '  "adminTotalPointsLabel": "مجموع النقاط",',
    '  "adminTotalPointsLabel": "مجموع النقاط",\n'
    '  "adminRoundReportSectionTitle": "تقرير الجولة",\n'
    '  "adminViewRoundReportButton": "عرض تقرير الجولة",\n'
    '  "adminRoundReportRankLabel": "الترتيب",\n'
    '  "adminRoundReportShareButton": "نسخ للمشاركة",\n'
    '  "adminRoundReportCopiedMessage": "تم النسخ، شاركه عبر واتساب",\n'
    '  "adminRoundReportEmpty": "لا يوجد مشاركون بهذه الجولة",',
    "app_ar.arb",
)

replace(
    "apps/mobile/lib/l10n/app_en.arb",
    '  "adminTotalPointsLabel": "Total points",',
    '  "adminTotalPointsLabel": "Total points",\n'
    '  "adminRoundReportSectionTitle": "Round report",\n'
    '  "adminViewRoundReportButton": "View round report",\n'
    '  "adminRoundReportRankLabel": "Rank",\n'
    '  "adminRoundReportShareButton": "Copy to share",\n'
    '  "adminRoundReportCopiedMessage": "Copied — share it on WhatsApp",\n'
    '  "adminRoundReportEmpty": "No participants in this round",',
    "app_en.arb",
)

# ---------------------------------------------------------------------------
# 6) اختبار الدمج البحت
# ---------------------------------------------------------------------------
write_new(
    "apps/mobile/test/features/admin/round_report_test.dart",
    """import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/round_report.dart';

RoundScoreDto _score(
  String participantId,
  int total,
  List<FixtureScoreResultDto> results,
) => RoundScoreDto(
  roundId: 'round-1',
  participantId: participantId,
  rulesetVersion: 1,
  totalPoints: total,
  fixtureResults: results,
);

PredictionDto _prediction(
  String participantId,
  List<FixtureScoreDto> scores,
) => PredictionDto(
  id: 'pred-$participantId',
  participantId: participantId,
  roundId: 'round-1',
  submittedAt: '2026-08-01T12:00:00Z',
  fixtureScores: scores,
);

void main() {
  test('ranks participants by total points descending', () {
    final scores = RoundScoresDto(
      roundId: 'round-1',
      scores: [
        _score('p-low', 3, const [
          FixtureScoreResultDto(
            fixtureId: 'f1',
            grade: 'correct_outcome',
            points: 3,
          ),
        ]),
        _score('p-high', 10, const [
          FixtureScoreResultDto(
            fixtureId: 'f1',
            grade: 'exact_scoreline',
            points: 10,
          ),
        ]),
      ],
    );
    final raw = [
      _prediction('p-low', const [
        FixtureScoreDto(fixtureId: 'f1', homeGoals: 1, awayGoals: 1),
      ]),
      _prediction('p-high', const [
        FixtureScoreDto(
          fixtureId: 'f1',
          homeGoals: 2,
          awayGoals: 0,
          isDouble: true,
        ),
      ]),
    ];

    final rows = buildRoundReport(scores: scores, rawPredictions: raw);

    expect(rows, hasLength(2));
    expect(rows[0].participantId, 'p-high');
    expect(rows[0].rank, 1);
    expect(rows[0].cells.single.homeGoals, 2);
    expect(rows[0].cells.single.awayGoals, 0);
    expect(rows[0].cells.single.isDouble, isTrue);
    expect(rows[1].participantId, 'p-low');
    expect(rows[1].rank, 2);
  });

  test(
    'a cell with no matching raw prediction has null scores (missed fixture)',
    () {
      final scores = RoundScoresDto(
        roundId: 'round-1',
        scores: [
          _score('p1', 0, const [
            FixtureScoreResultDto(
              fixtureId: 'f1',
              grade: 'missed',
              points: 0,
            ),
          ]),
        ],
      );

      final rows = buildRoundReport(scores: scores, rawPredictions: const []);

      expect(rows.single.cells.single.hasRawScore, isFalse);
      expect(rows.single.cells.single.grade, 'missed');
    },
  );

  test('an empty scored round produces an empty report', () {
    const scores = RoundScoresDto(roundId: 'round-1', scores: []);
    final rows = buildRoundReport(scores: scores, rawPredictions: const []);
    expect(rows, isEmpty);
  });
}
""",
    "round_report_test.dart",
)

print("\nتم بنجاح. شغّل الآن من apps/mobile:")
print("  dart run build_runner build --delete-conflicting-outputs")
print("  flutter gen-l10n")
print("  flutter test test/features/admin/round_report_test.dart")
print("  flutter analyze")
