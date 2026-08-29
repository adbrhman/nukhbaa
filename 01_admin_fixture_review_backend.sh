#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd /home/dev/nukhbaa-backup-1787537565

echo "==> [1/6] إنشاء AdminGetFixtureScores (application)"
mkdir -p packages/application/lib/src/scoring
cat > packages/application/lib/src/scoring/admin_get_fixture_scores.dart << 'DARTEOF'
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the admin **fixture-scores read**, bypassing the
/// participant-of-season visibility gate that [GetFixtureScores] enforces
/// (docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// [AdminGetRoundScores], added so an admin can investigate a user's
/// complaint on any fixture regardless of the admin's own season
/// membership).
///
/// Unlike [AdminGetRoundScores] (gated on the round being
/// `RoundStatus.scored`), this carries NO fixture-status gate — mirroring
/// [GetFixtureScores]'s Option-3 live/partial philosophy: an empty list
/// before the fixture has been scored is a legitimate result, not an error.
///
/// Never throws; returns a typed [Result].
final class AdminGetFixtureScores {
  /// Creates the use-case over its collaborator.
  const AdminGetFixtureScores({
    required FixtureScoreRepository fixtureScoreRepository,
  }) : _fixtureScores = fixtureScoreRepository;

  final FixtureScoreRepository _fixtureScores;

  /// Lists every participant's [ParticipantFixtureScore] for [fixtureId],
  /// visible to any [PlatformRole.admin] regardless of season membership.
  Future<Result<List<ParticipantFixtureScore>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    return _fixtureScores.listByFixture(fixture);
  }
}
DARTEOF

echo "==> [2/6] إنشاء مسار GET /admin/fixtures/{id}/scores"
mkdir -p "apps/server/routes/admin/fixtures/[id]/scores"
cat > "apps/server/routes/admin/fixtures/[id]/scores/index.dart" << 'DARTEOF'
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/fixtures/{id}/scores` — the admin fixture-scores read: every
/// participant's already-computed score for a single fixture, regardless of
/// the admin's own season membership (docs/project-context.md, Axiom 4
/// Amendment; mirrors `GET /admin/rounds/{id}/scores`, admin-only, enforced
/// inside `AdminGetFixtureScores`).
///
/// Unlike the participant-facing
/// `GET /seasons/{id}/fixtures/{fixtureId}/scores` (season-membership
/// gated), this route carries NO such gate — added for admin investigation
/// of a user's complaint on any fixture. Also unlike
/// `GET /admin/rounds/{id}/scores` (blocked until the round is scored), this
/// carries no fixture-status gate either, mirroring `GetFixtureScores`'s
/// Option-3 live/partial philosophy: an empty array is a legitimate `200`,
/// not an error.
///
/// The whole `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this
/// handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetFixtureScores(
    principal: principal,
    fixtureId: id,
  );

  return switch (result) {
    Ok<List<ParticipantFixtureScore>>(:final value) => await _withDisplayNames(
      root,
      principal,
      id,
      value,
    ),
    Err<List<ParticipantFixtureScore>>(:final error) => errorResponse(error),
  };
}

Future<Response> _withDisplayNames(
  CompositionRoot root,
  AuthenticatedUser principal,
  String fixtureId,
  List<ParticipantFixtureScore> scores,
) async {
  final namesResult = await root.adminGetParticipantDisplayNames(
    principal: principal,
    participantIds: [for (final s in scores) s.participantId.value],
  );
  final names = namesResult is Ok<Map<String, String>>
      ? namesResult.value
      : const <String, String>{};
  return Response.json(
    body: fixtureScoresToJson(fixtureId, scores, displayNames: names),
  );
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

# --- application.dart: تصدير الملف الجديد ---
replace_once(
    "packages/application/lib/application.dart",
    "export 'src/scoring/admin_get_participant_display_names.dart';",
    "export 'src/scoring/admin_get_fixture_scores.dart';\n"
    "export 'src/scoring/admin_get_participant_display_names.dart';",
    "application.dart export",
)

# --- composition_root.dart: 6 تعديلات ---
cr = "apps/server/lib/composition/composition_root.dart"

replace_once(
    cr,
    "    required this.getFixtureScores,\n    required this.getRoundLeaderboard,",
    "    required this.getFixtureScores,\n    required this.adminGetFixtureScores,\n    required this.getRoundLeaderboard,",
    "required params",
)

replace_once(
    cr,
    "    GetFixtureScores? getFixtureScores,\n    GetRoundLeaderboard? getRoundLeaderboard,",
    "    GetFixtureScores? getFixtureScores,\n    AdminGetFixtureScores? adminGetFixtureScores,\n    GetRoundLeaderboard? getRoundLeaderboard,",
    "optional constructor param",
)

replace_once(
    cr,
    "       getFixtureScores = getFixtureScores ?? _absentGetFixtureScores(),\n       getRoundLeaderboard =",
    "       getFixtureScores = getFixtureScores ?? _absentGetFixtureScores(),\n"
    "       adminGetFixtureScores =\n"
    "           adminGetFixtureScores ?? _absentAdminGetFixtureScores(),\n"
    "       getRoundLeaderboard =",
    "absent init",
)

replace_once(
    cr,
    '  static GetFixtureScores _absentGetFixtureScores() => GetFixtureScores(\n'
    '    competitionRepository: _unwiredCompetitionRepository,\n'
    '    fixturePredictionRepository: _unwiredFixturePredictionRepository,\n'
    '    fixtureScoreRepository: _unwiredFixtureScoreRepository,\n'
    '  );\n'
    '\n'
    '  /// Backs the "absent" [GetRoundLeaderboard]:',
    '  static GetFixtureScores _absentGetFixtureScores() => GetFixtureScores(\n'
    '    competitionRepository: _unwiredCompetitionRepository,\n'
    '    fixturePredictionRepository: _unwiredFixturePredictionRepository,\n'
    '    fixtureScoreRepository: _unwiredFixtureScoreRepository,\n'
    '  );\n'
    '\n'
    '  /// Backs the "absent" [AdminGetFixtureScores]: throws so a test that\n'
    '  /// reaches this admin-bypass path fails loudly instead of silently\n'
    '  /// touching a real database — mirrors [_absentAdminGetRoundScores].\n'
    '  static AdminGetFixtureScores _absentAdminGetFixtureScores() =>\n'
    '      AdminGetFixtureScores(\n'
    '        fixtureScoreRepository: _unwiredFixtureScoreRepository,\n'
    '      );\n'
    '\n'
    '  /// Backs the "absent" [GetRoundLeaderboard]:',
    "absent factory",
)

replace_once(
    cr,
    "  final GetFixtureScores getFixtureScores;\n\n  /// Reads a round's ranked standings",
    "  final GetFixtureScores getFixtureScores;\n\n"
    "  /// Admin fixture-scores read — same shape as [getFixtureScores] but\n"
    "  /// without the participant-of-season gate (added so an admin can\n"
    "  /// investigate a user's complaint on any fixture regardless of the\n"
    "  /// admin's own season membership).\n"
    "  final AdminGetFixtureScores adminGetFixtureScores;\n\n"
    "  /// Reads a round's ranked standings",
    "field declaration",
)

replace_once(
    cr,
    "      getFixtureScores: GetFixtureScores(\n"
    "        competitionRepository: competitionRepository,\n"
    "        fixturePredictionRepository: fixturePredictionRepository,\n"
    "        fixtureScoreRepository: fixtureScoreRepository,\n"
    "      ),\n"
    "      getRoundLeaderboard: GetRoundLeaderboard(",
    "      getFixtureScores: GetFixtureScores(\n"
    "        competitionRepository: competitionRepository,\n"
    "        fixturePredictionRepository: fixturePredictionRepository,\n"
    "        fixtureScoreRepository: fixtureScoreRepository,\n"
    "      ),\n"
    "      adminGetFixtureScores: AdminGetFixtureScores(\n"
    "        fixtureScoreRepository: fixtureScoreRepository,\n"
    "      ),\n"
    "      getRoundLeaderboard: GetRoundLeaderboard(",
    "production wiring",
)

# --- admin_api.dart: دالتان جديدتان ---
api = "packages/api_client/lib/src/admin_api.dart"
replace_once(
    api,
    "  Future<Result<RoundReportDto>> adminGetRoundReport(String roundId) {\n"
    "    return _transport.getObject<RoundReportDto>(\n"
    "      '/admin/rounds/$roundId/report',\n"
    "      parse: RoundReportDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "}",
    "  Future<Result<RoundReportDto>> adminGetRoundReport(String roundId) {\n"
    "    return _transport.getObject<RoundReportDto>(\n"
    "      '/admin/rounds/$roundId/report',\n"
    "      parse: RoundReportDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// `GET /admin/fixtures/{fixtureId}/scores` — the admin fixture-scores\n"
    "  /// read: every participant's computed score for a single fixture,\n"
    "  /// regardless of the admin's own season membership (mirrors\n"
    "  /// [adminGetRoundScores]; the per-fixture sibling, added for admin\n"
    "  /// investigation of a user's complaint on any fixture).\n"
    "  Future<Result<FixtureScoresDto>> adminGetFixtureScores(String fixtureId) {\n"
    "    return _transport.getObject<FixtureScoresDto>(\n"
    "      '/admin/fixtures/$fixtureId/scores',\n"
    "      parse: FixtureScoresDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// `GET /admin/fixtures/{fixtureId}/predictions` — every participant's raw\n"
    "  /// predicted scoreline for a fixture, regardless of season membership\n"
    "  /// (mirrors [adminListRoundPredictions]; the per-fixture sibling).\n"
    "  /// [reason] is an optional justification recorded on the (mandatory)\n"
    "  /// audit entry for this read; the read itself is always audited\n"
    "  /// server-side regardless of whether one is supplied.\n"
    "  Future<Result<List<FixturePredictionDto>>> adminListFixturePredictions(\n"
    "    String fixtureId, {\n"
    "    String? reason,\n"
    "  }) {\n"
    "    return _transport.getList<FixturePredictionDto>(\n"
    "      '/admin/fixtures/$fixtureId/predictions',\n"
    "      query: reason == null ? null : {'reason': reason},\n"
    "      parseElement: FixturePredictionDto.fromJson,\n"
    "    );\n"
    "  }\n"
    "}",
    "admin_api.dart new methods",
)
PYEOF

echo "==> [4/6] flutter analyze"
ANALYZE_OK=1
flutter analyze packages/application apps/server packages/api_client || ANALYZE_OK=0

echo "==> [5/6] flutter test"
TEST_OK=1
flutter test packages/application apps/server packages/api_client || TEST_OK=0

if [ "$ANALYZE_OK" -eq 1 ] && [ "$TEST_OK" -eq 1 ]; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi
TS="$(date +%H:%M)"

echo "==> [6/6] تحديث docs/checkpoints/session-log.md (بلا commit/push تلقائي)"
{
  echo "- [$TS] إصلاح: AdminGetFixtureScores + مسار /admin/fixtures/{id}/scores + adminGetFixtureScores/adminListFixturePredictions في AdminApi | ملفات: packages/application/lib/src/scoring/admin_get_fixture_scores.dart, packages/application/lib/application.dart, apps/server/lib/composition/composition_root.dart, apps/server/routes/admin/fixtures/[id]/scores/index.dart, packages/api_client/lib/src/admin_api.dart | اختبار: $TEST_STATUS"
} >> docs/checkpoints/session-log.md

if [ "$ANALYZE_OK" -eq 0 ] || [ "$TEST_OK" -eq 0 ]; then
  echo ""
  echo "!! توقف: analyze أو test فشل. راجع المخرجات أعلاه قبل أي commit."
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
git commit -m "feat(admin): AdminGetFixtureScores + admin fixture scores/predictions read layer

- AdminGetFixtureScores (application): admin-only, no season-participation
  gate, no fixture-status gate (mirrors AdminGetRoundScores, live/partial
  per GetFixtureScores' Option-3 philosophy).
- composition_root.dart wiring (required param, optional param, absent
  fallback, field, production init).
- GET /admin/fixtures/{id}/scores route, mirrors /admin/rounds/{id}/scores
  (display-name merge included).
- AdminApi.adminGetFixtureScores + AdminApi.adminListFixturePredictions
  (client for the already-existing GET /admin/fixtures/{id}/predictions
  route).

Backend read-layer only — no mobile UI yet. Enables admin review of any
fixture's predictions/scores regardless of season membership, for
investigating user complaints."
MSG
