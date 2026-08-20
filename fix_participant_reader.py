#!/usr/bin/env python3
import re
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
    print(f"OK {path}")


patch_regex(
    "apps/server/lib/composition/composition_root.dart",
    r"final class _UnwiredParticipantReader implements ParticipantReader \{\s*\n\s*@override\s*\n\s*Future<Result<Participant\?>> findParticipantById\(ParticipantId id\) =>\s*\n\s*throw StateError\('A ledger use-case was not wired into this root'\);\s*\n\}",
    "final class _UnwiredParticipantReader implements ParticipantReader {\n"
    "  @override\n"
    "  Future<Result<Participant?>> findParticipantById(ParticipantId id) =>\n"
    "      throw StateError('A ledger use-case was not wired into this root');\n\n"
    "  @override\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(\n"
    "    List<ParticipantId> ids,\n"
    "  ) =>\n"
    "      throw StateError('A ledger use-case was not wired into this root');\n"
    "}",
)

patch_regex(
    "apps/server/test/routes/competition_route_harness.dart",
    r"Future<Result<Participant\?>> findParticipantById\(ParticipantId id\) async =>\s*\n\s*Result\.ok\(_byId\[id\.value\]\);\s*\n\}",
    "Future<Result<Participant?>> findParticipantById(ParticipantId id) async =>\n"
    "      Result.ok(_byId[id.value]);\n\n"
    "  @override\n"
    "  Future<Result<Map<String, String>>> findDisplayNames(\n"
    "    List<ParticipantId> ids,\n"
    "  ) async {\n"
    "    return Result.ok({\n"
    "      for (final id in ids)\n"
    "        if (_byId[id.value] != null) id.value: 'Test User',\n"
    "    });\n"
    "  }\n"
    "}",
)

if errors:
    print("\n---- FAILED PATCHES (nothing corrupted, fix anchors and re-run) ----")
    for e in errors:
        print(" -", e)
else:
    print("\nAll patches applied. Now run: dart analyze --fatal-warnings .")
