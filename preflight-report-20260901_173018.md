# Preflight Report — Tue Sep  1 17:30:18 EEST 2026

فرع العمل: `chore/monthly-fixture-preflight-20260901`

## 1. Team/League presence
- وُجدت مراجع Team/League — راجعها قبل بناء أي شيء جديد:
apps/mobile/lib/core/branding/team_branding.dart:24:final class TeamBranding {
apps/mobile/lib/features/auth/nukhbaa_shell.dart:280:class TeamLogo extends StatelessWidget {
apps/mobile/lib/features/competition/team_registry.dart:29:class TeamBrand {

## 2. Season month-boundary logic
8:/// Phase 7.2: the competition model is calendar-driven and monthly -- a
9:/// season is a calendar-bounded window ([startAt]/[endAt]), not a
18:    required this.startAt,
19:    required this.endAt,
28:    required this.startAt,
29:    required this.endAt,
33:  /// length-checked (1-60 chars). [startAt]/[endAt] must both be UTC
34:  /// instants with endAt strictly after startAt.
39:    required DateTime startAt,
40:    required DateTime endAt,
59:    if (!startAt.isUtc || !endAt.isUtc) {
63:          'Season startAt/endAt must be UTC instants',
67:    if (!endAt.isAfter(startAt)) {
71:          'Season endAt must be after startAt',
80:        startAt: startAt,
81:        endAt: endAt,
91:  final DateTime startAt;
92:  final DateTime endAt;
94:  /// Whether [nowUtc] falls inside this season's window — [startAt]
95:  /// inclusive, [endAt] exclusive.
104:  bool isCurrentAt(DateTime nowUtc) =>
105:      !nowUtc.isBefore(startAt) && nowUtc.isBefore(endAt);
113:      other.startAt == startAt &&
114:      other.endAt == endAt;
117:  int get hashCode => Object.hash(id, competitionId, label, startAt, endAt);
122:      '"$label", $startAt - $endAt)';

## 3. Round leftovers (consumers still importing round)
apps/server/routes/rounds/[id]/ledger/index.dart:37:/// (`routes/rounds/_middleware.dart`), which provides the verified
apps/server/routes/rounds/[id]/leaderboard/index.dart:25:/// (`routes/rounds/_middleware.dart`), which provides the [AuthenticatedUser];
apps/server/routes/rounds/[id]/predictions/all.dart:23:/// (`routes/rounds/_middleware.dart`), which provides the [AuthenticatedUser];
apps/server/routes/rounds/[id]/predictions/index.dart:31:/// `routes/rounds/_middleware.dart`, which provides the verified
apps/server/routes/rounds/[id]/score/index.dart:30:/// (`routes/rounds/_middleware.dart`), which provides the verified
apps/server/routes/rounds/[id]/scores/index.dart:23:/// (`routes/rounds/_middleware.dart`), which provides the [AuthenticatedUser];
apps/server/routes/rounds/[id]/report/index.dart:18:/// (`routes/rounds/_middleware.dart`).
apps/server/routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart:81:/// `routes/rounds/[id]/predictions/index.dart`'s `_parseScores`. A present but
apps/server/test/routes/ledger_routes_test.dart:14:import '../../routes/rounds/[id]/ledger/index.dart' as post_ledger_route;
apps/server/test/routes/round_predictions_test.dart:10:import '../../routes/rounds/[id]/predictions/all.dart' as all;
apps/server/test/routes/round_predictions_test.dart:12:import '../../routes/rounds/[id]/predictions/index.dart' as index;
apps/server/test/routes/rounds_browse_test.dart:10:import '../../routes/rounds/[id]/fixtures/index.dart' as fixtures_route;
apps/server/test/routes/rounds_browse_test.dart:14:import '../../routes/rounds/[id]/index.dart' as round_route;
apps/server/test/routes/scoring_routes_test.dart:13:import '../../routes/rounds/[id]/score/index.dart' as score_route;
apps/server/test/routes/scoring_routes_test.dart:15:import '../../routes/rounds/[id]/scores/index.dart' as scores_route;
apps/server/test/routes/seasons_rounds_browse_test.dart:14:import '../../routes/seasons/[id]/rounds/index.dart' as rounds_route;
apps/server/test/routes/social_routes_test.dart:12:import '../../routes/groups/[id]/rounds/[roundId]/reactions/index.dart'
packages/api_client/lib/src/competition_api.dart:22:///     (`routes/rounds/[id]/index.dart`; `404 competition.round_not_found`)
packages/api_client/lib/src/competition_api.dart:24:///     (`routes/rounds/[id]/fixtures/index.dart` GET branch, display order,
packages/api_client/lib/src/leaderboards_api.dart:11:///     (`routes/rounds/[id]/leaderboard/index.dart`).
packages/api_client/lib/src/prediction_api.dart:12:///     -> `List<PredictionDto>` (`routes/rounds/[id]/predictions/all.dart`).
packages/application/lib/application.dart:19:export 'src/competition/browse_round_fixtures.dart';
packages/application/lib/application.dart:27:export 'src/competition/link_fixture_to_round.dart';
packages/application/lib/src/scoring/score_rounds_for_fixture.dart:2:import 'package:application/src/scoring/score_round.dart';
packages/domain/lib/src/competition/round.dart:1:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/competition/round.dart:2:import 'package:domain/src/competition/round_status.dart';
packages/domain/lib/src/competition/round_fixture.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/competition/round_fixture_card.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/competition/round_sequencing.dart:1:import 'package:domain/src/competition/round.dart';
packages/domain/lib/src/competition/round_sequencing.dart:2:import 'package:domain/src/competition/round_status.dart';
packages/domain/lib/src/leaderboard/round_leaderboard.dart:1:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/leaderboard/round_leaderboard.dart:2:import 'package:domain/src/leaderboard/round_leaderboard_entry.dart';
packages/domain/lib/src/leaderboard/round_leaderboard.dart:3:import 'package:domain/src/scoring/round_score.dart';
packages/domain/lib/src/leaderboard/round_leaderboard_entry.dart:2:import 'package:domain/src/scoring/round_score.dart';
packages/domain/lib/src/ledger/point_entry.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/notification/notification_subject.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/prediction/prediction.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/prediction/prediction.dart:3:import 'package:domain/src/competition/round_status.dart';
packages/domain/lib/src/scoring/round_score.dart:2:import 'package:domain/src/competition/round_id.dart';
packages/domain/lib/src/scoring/scoring.dart:8:import 'package:domain/src/scoring/round_score.dart';
packages/domain/lib/src/scoring/round_report_entry.dart:3:import 'package:domain/src/scoring/round_score.dart';
packages/domain/lib/src/social/reaction.dart:1:import 'package:domain/src/competition/round_id.dart';

## 4. Stray backup files (.bak*) — احذفها يدوياً بعد المراجعة
apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart.bak_20260823_022904

## 5. Toolchain availability
/data/data/com.termux/files/usr/bin/dart
Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "android_arm64"
/root/flutter/bin/flutter
Flutter 3.44.0 • channel [user-branch] • unknown source
Framework • revision 559ffa3f75 (4 months ago) • 2026-05-15 14:13:13 -0700
Engine • hash fcf463a2242790d1fdcd9d044f533080f5022e18 (revision 4c525dac5e) (3 months ago) • 2026-05-15 19:00:04.000Z
Tools • Dart 3.12.0 • DevTools 2.57.0

## Next (يدوي)
1. احسم قرار Team/League في docs/project-context.md.
2. راجع الأقسام 2–4 أعلاه قبل أي تعديل.
3. شغّل التحقق فقط على جهاز فيه Dart/Flutter.
