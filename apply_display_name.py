#!/usr/bin/env python3
"""
Applies the participant displayName feature across all layers.
Run from repo root: python3 apply_display_name.py
Each patch fails loudly (prints error, stops) instead of corrupting a file
if its anchor text isn't found exactly once — safe to re-run after a fix.
"""
import re
import sys
from pathlib import Path

ROOT = Path(".")
errors = []


def patch_regex(path, pattern, replacement, flags=re.MULTILINE, required=1):
    p = ROOT / path
    if not p.exists():
        errors.append(f"MISSING FILE: {path}")
        return
    content = p.read_text(encoding="utf-8")
    matches = list(re.finditer(pattern, content, flags))
    if len(matches) != required:
        errors.append(
            f"{path}: expected {required} match(es), found {len(matches)} "
            f"for pattern: {pattern[:80]}..."
        )
        return
    new_content = re.sub(pattern, replacement, content, count=required, flags=flags)
    p.write_text(new_content, encoding="utf-8")
    print(f"OK  {path}")


def create_file(path, content):
    p = ROOT / path
    if p.exists():
        print(f"SKIP (exists) {path}")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print(f"NEW {path}")


def prepend(path, text):
    p = ROOT / path
    if not p.exists():
        errors.append(f"MISSING FILE: {path}")
        return
    content = p.read_text(encoding="utf-8")
    if text.strip() in content:
        print(f"SKIP (already present) {path}")
        return
    p.write_text(text + content, encoding="utf-8")
    print(f"OK  {path} (import prepended)")


# ---------------------------------------------------------------------------
# 1) ParticipantReader port
# ---------------------------------------------------------------------------
patch_regex(
    "packages/application/lib/src/ledger/ports/participant_reader.dart",
    r"Future<Result<Participant\?>>\s+findParticipantById\(ParticipantId id\);\s*\n\}",
    "Future<Result<Participant?>> findParticipantById(ParticipantId id);\n\n"
    "  /// Returns display names for the given participant [ids] (participant id\n"
    "  /// value -> `identity.users.display_name`). Ids with no matching participant\n"
    "  /// or user are simply absent from the map (never an error).\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(List<ParticipantId> ids);\n}",
)

# ---------------------------------------------------------------------------
# 2) PostgresParticipantReader implementation
# ---------------------------------------------------------------------------
patch_regex(
    "packages/infrastructure/lib/src/ledger/postgres_participant_reader.dart",
    r"final PostgresConnection _connection;\s*\n\s*\n\s*static const String _selectByIdSql = '''",
    "final PostgresConnection _connection;\n\n"
    "  static const String _selectDisplayNamesSql = '''\n"
    "SELECT p.id AS participant_id, u.display_name AS display_name\n"
    "FROM competition.participants p\n"
    "JOIN identity.users u ON u.id = p.user_id\n"
    "WHERE p.id = ANY(@ids)\n"
    "''';\n\n"
    "  @override\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(\n"
    "    List<ParticipantId> ids,\n"
    "  ) async {\n"
    "    if (ids.isEmpty) return const Result.ok({});\n"
    "    final result = await _connection.query(\n"
    "      _selectDisplayNamesSql,\n"
    "      parameters: {'ids': [for (final id in ids) id.value]},\n"
    "    );\n"
    "    return switch (result) {\n"
    "      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),\n"
    "      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok({\n"
    "        for (final row in value)\n"
    "          if (row['participant_id'] != null && row['display_name'] != null)\n"
    "            row['participant_id'].toString(): row['display_name'].toString(),\n"
    "      }),\n"
    "    };\n"
    "  }\n\n"
    "  static const String _selectByIdSql = '''",
)

# ---------------------------------------------------------------------------
# 3) Test fakes
# ---------------------------------------------------------------------------
patch_regex(
    "packages/application/test/admin/fakes.dart",
    r"void seed\(Participant participant\) =>\s*\n\s*_byId\[participant\.id\.value\] = participant;",
    "void seed(Participant participant) =>\n"
    "      _byId[participant.id.value] = participant;\n\n"
    "  @override\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(\n"
    "    List<ParticipantId> ids,\n"
    "  ) async {\n"
    "    final failure = _takeFailure();\n"
    "    if (failure != null) return Result.err(failure);\n"
    "    return Result.ok({\n"
    "      for (final id in ids)\n"
    "        if (_byId[id.value] != null) id.value: 'Test User',\n"
    "    });\n"
    "  }",
)

patch_regex(
    "packages/application/test/ledger/fakes.dart",
    r"void seed\(Participant p\) => _byId\[p\.id\.value\] = p;",
    "void seed(Participant p) => _byId[p.id.value] = p;\n\n"
    "  @override\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(\n"
    "    List<ParticipantId> ids,\n"
    "  ) async {\n"
    "    final failure = _takeFailure();\n"
    "    if (failure != null) return Result.err(failure);\n"
    "    return Result.ok({\n"
    "      for (final id in ids)\n"
    "        if (_byId[id.value] != null) id.value: 'Test User',\n"
    "    });\n"
    "  }",
)

# ---------------------------------------------------------------------------
# 4) New use-case
# ---------------------------------------------------------------------------
create_file(
    "packages/application/lib/src/scoring/admin_get_participant_display_names.dart",
    "import 'package:application/src/identity/authorization.dart';\n"
    "import 'package:application/src/ledger/ports/participant_reader.dart';\n"
    "import 'package:domain/domain.dart';\n"
    "import 'package:shared/shared.dart';\n\n"
    "final class AdminGetParticipantDisplayNames {\n"
    "  const AdminGetParticipantDisplayNames({\n"
    "    required ParticipantReader participantReader,\n"
    "  }) : _participants = participantReader;\n\n"
    "  final ParticipantReader _participants;\n\n"
    "  Future<Result<Map<String, String>>> call({\n"
    "    required AuthenticatedUser principal,\n"
    "    required List<String> participantIds,\n"
    "  }) async {\n"
    "    final auth = Authorization.requireRole(principal, PlatformRole.admin);\n"
    "    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);\n\n"
    "    final ids = <ParticipantId>[];\n"
    "    for (final raw in participantIds) {\n"
    "      final idResult = ParticipantId.tryParse(raw);\n"
    "      if (idResult is Err<ParticipantId>) return Result.err(idResult.error);\n"
    "      ids.add((idResult as Ok<ParticipantId>).value);\n"
    "    }\n"
    "    return _participants.findDisplayNames(ids);\n"
    "  }\n"
    "}\n",
)

# ---------------------------------------------------------------------------
# 5) CompositionRoot wiring
# ---------------------------------------------------------------------------
prepend(
    "apps/server/lib/composition/composition_root.dart",
    "import 'package:application/src/scoring/admin_get_participant_display_names.dart';\n",
)

patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"required this\.adminListRoundPredictions,\s*\n\s*\}\)\s*:\s*_connection\s*=\s*connection,",
    "required this.adminGetParticipantDisplayNames,\n"
    "    required this.adminListRoundPredictions,\n"
    "  }) : _connection = connection,",
)

patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"AdminListRoundPredictions\? adminListRoundPredictions,\s*\n\s*\}\)\s*:\s*checkHealth\s*=\s*checkHealth\s*\?\?\s*_absentCheckHealth\(\),",
    "AdminGetParticipantDisplayNames? adminGetParticipantDisplayNames,\n"
    "    AdminListRoundPredictions? adminListRoundPredictions,\n"
    "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),",
)

patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"postRoundToLedger = postRoundToLedger \?\? _absentPostRoundToLedger\(\),",
    "adminGetParticipantDisplayNames =\n"
    "           adminGetParticipantDisplayNames ??\n"
    "           _absentAdminGetParticipantDisplayNames(),\n"
    "       postRoundToLedger = postRoundToLedger ?? _absentPostRoundToLedger(),",
)

patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"final PostRoundToLedger postRoundToLedger;",
    "final AdminGetParticipantDisplayNames adminGetParticipantDisplayNames;\n\n"
    "  static AdminGetParticipantDisplayNames\n"
    "  _absentAdminGetParticipantDisplayNames() => AdminGetParticipantDisplayNames(\n"
    "    participantReader: _unwiredParticipantReader,\n"
    "  );\n\n"
    "  final PostRoundToLedger postRoundToLedger;",
)

patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"postRoundToLedger: PostRoundToLedger\(",
    "adminGetParticipantDisplayNames: AdminGetParticipantDisplayNames(\n"
    "        participantReader: participantReader,\n"
    "      ),\n"
    "      postRoundToLedger: PostRoundToLedger(",
)

# ---------------------------------------------------------------------------
# 6) contracts: RoundScoreDto
# ---------------------------------------------------------------------------
patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"const RoundScoreDto\(\{\s*\n\s*required this\.roundId,\s*\n\s*required this\.participantId,\s*\n\s*required this\.rulesetVersion,\s*\n\s*required this\.totalPoints,\s*\n\s*required this\.fixtureResults,\s*\n\s*this\.schemaVersion = currentSchemaVersion,\s*\n\s*\}\);",
    "const RoundScoreDto({\n"
    "    required this.roundId,\n"
    "    required this.participantId,\n"
    "    required this.rulesetVersion,\n"
    "    required this.totalPoints,\n"
    "    required this.fixtureResults,\n"
    "    this.displayName = '',\n"
    "    this.schemaVersion = currentSchemaVersion,\n"
    "  });",
)

patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"totalPoints: json\['total_points'\]! as int,\s*\n(\s*)fixtureResults: rawResults",
    "totalPoints: json['total_points']! as int,\n"
    r"\1displayName: (json['display_name'] as String?) ?? '',"
    "\n\\1fixtureResults: rawResults",
)

patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"final List<FixtureScoreResultDto> fixtureResults;",
    "final List<FixtureScoreResultDto> fixtureResults;\n\n"
    "  /// The participant's display name, joined server-side from\n"
    "  /// `identity.users.display_name`. Empty string when unavailable.\n"
    "  final String displayName;",
)

patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"'total_points': totalPoints,\s*\n(\s*)'fixture_results': \[for \(final r in fixtureResults\) r\.toJson\(\)\],",
    "'total_points': totalPoints,\n"
    r"\1'display_name': displayName,"
    "\n\\1'fixture_results': [for (final r in fixtureResults) r.toJson()],",
)

patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"other\.totalPoints == totalPoints &&\s*\n(\s*)_listEquals\(other\.fixtureResults, fixtureResults\) &&",
    "other.totalPoints == totalPoints &&\n"
    r"\1other.displayName == displayName &&"
    "\n\\1_listEquals(other.fixtureResults, fixtureResults) &&",
)

patch_regex(
    "packages/contracts/lib/src/scoring_dto.dart",
    r"totalPoints,\s*\n(\s*)Object\.hashAll\(fixtureResults\),",
    "totalPoints,\n"
    r"\1displayName,"
    "\n\\1Object.hashAll(fixtureResults),",
)

# ---------------------------------------------------------------------------
# 7) server mapper
# ---------------------------------------------------------------------------
patch_regex(
    "apps/server/lib/http/scoring_dto_mapper.dart",
    r"RoundScoreDto roundScoreToDto\(RoundScore score\) \{\s*\n\s*return RoundScoreDto\(\s*\n\s*roundId: score\.roundId\.value,\s*\n\s*participantId: score\.participantId\.value,\s*\n\s*rulesetVersion: score\.rulesetVersion,\s*\n\s*totalPoints: score\.totalPoints,\s*\n\s*fixtureResults: \[",
    "RoundScoreDto roundScoreToDto(RoundScore score, {String displayName = ''}) {\n"
    "  return RoundScoreDto(\n"
    "    roundId: score.roundId.value,\n"
    "    participantId: score.participantId.value,\n"
    "    rulesetVersion: score.rulesetVersion,\n"
    "    totalPoints: score.totalPoints,\n"
    "    displayName: displayName,\n"
    "    fixtureResults: [",
)

patch_regex(
    "apps/server/lib/http/scoring_dto_mapper.dart",
    r"Map<String, Object\?> roundScoresToJson\(\s*\n\s*String roundId,\s*\n\s*List<RoundScore> scores,\s*\n\) \{\s*\n\s*return RoundScoresDto\(\s*\n\s*roundId: roundId,\s*\n\s*scores: \[for \(final score in scores\) roundScoreToDto\(score\)\],\s*\n\s*\)\.toJson\(\);\s*\n\}",
    "Map<String, Object?> roundScoresToJson(\n"
    "  String roundId,\n"
    "  List<RoundScore> scores, {\n"
    "  Map<String, String> displayNames = const {},\n"
    "}) {\n"
    "  return RoundScoresDto(\n"
    "    roundId: roundId,\n"
    "    scores: [\n"
    "      for (final score in scores)\n"
    "        roundScoreToDto(\n"
    "          score,\n"
    "          displayName: displayNames[score.participantId.value] ?? '',\n"
    "        ),\n"
    "    ],\n"
    "  ).toJson();\n"
    "}",
)

# ---------------------------------------------------------------------------
# 8) admin scores route
# ---------------------------------------------------------------------------
patch_regex(
    "apps/server/routes/admin/rounds/[id]/scores/index.dart",
    r"return switch \(result\) \{\s*\n\s*Ok<List<RoundScore>>\(:final value\) => Response\.json\(\s*\n\s*body: roundScoresToJson\(id, value\),\s*\n\s*\),\s*\n\s*Err<List<RoundScore>>\(:final error\) => errorResponse\(error\),\s*\n\s*\};\s*\n\}",
    "return switch (result) {\n"
    "    Ok<List<RoundScore>>(:final value) => await _withDisplayNames(\n"
    "      root,\n"
    "      principal,\n"
    "      id,\n"
    "      value,\n"
    "    ),\n"
    "    Err<List<RoundScore>>(:final error) => errorResponse(error),\n"
    "  };\n"
    "}\n\n"
    "Future<Response> _withDisplayNames(\n"
    "  CompositionRoot root,\n"
    "  AuthenticatedUser principal,\n"
    "  String roundId,\n"
    "  List<RoundScore> scores,\n"
    ") async {\n"
    "  final namesResult = await root.adminGetParticipantDisplayNames(\n"
    "    principal: principal,\n"
    "    participantIds: [for (final s in scores) s.participantId.value],\n"
    "  );\n"
    "  final names = namesResult is Ok<Map<String, String>>\n"
    "      ? namesResult.value\n"
    "      : const <String, String>{};\n"
    "  return Response.json(\n"
    "    body: roundScoresToJson(roundId, scores, displayNames: names),\n"
    "  );\n"
    "}",
)

# ---------------------------------------------------------------------------
# 9) mobile round_report.dart
# ---------------------------------------------------------------------------
patch_regex(
    "apps/mobile/lib/features/admin/round_report.dart",
    r"final class RoundReportRow \{\s*\n\s*const RoundReportRow\(\{\s*\n\s*required this\.rank,\s*\n\s*required this\.participantId,\s*\n\s*required this\.totalPoints,\s*\n\s*required this\.cells,\s*\n\s*\}\);\s*\n\s*\n\s*final int rank;\s*\n\s*final String participantId;\s*\n\s*final int totalPoints;",
    "final class RoundReportRow {\n"
    "  const RoundReportRow({\n"
    "    required this.rank,\n"
    "    required this.participantId,\n"
    "    required this.totalPoints,\n"
    "    required this.cells,\n"
    "    this.displayName = '',\n"
    "  });\n\n"
    "  final int rank;\n"
    "  final String participantId;\n"
    "  final int totalPoints;\n"
    "  final String displayName;",
)

patch_regex(
    "apps/mobile/lib/features/admin/round_report.dart",
    r"return RoundReportRow\(\s*\n\s*rank: rank,\s*\n\s*participantId: score\.participantId,\s*\n\s*totalPoints: score\.totalPoints,\s*\n\s*cells: \[",
    "return RoundReportRow(\n"
    "    rank: rank,\n"
    "    participantId: score.participantId,\n"
    "    totalPoints: score.totalPoints,\n"
    "    displayName: score.displayName,\n"
    "    cells: [",
)

# ---------------------------------------------------------------------------
if errors:
    print("\n---- FAILED PATCHES (nothing corrupted, fix anchors and re-run) ----")
    for e in errors:
        print(" -", e)
    sys.exit(1)
else:
    print("\nAll patches applied. Now run:")
    print("  melos run build_runner && flutter analyze")
