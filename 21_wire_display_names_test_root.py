#!/usr/bin/env python3
"""21_wire_display_names_test_root.

The route now reads root.adminGetParticipantDisplayNames, and the absent
stub _UnwiredParticipantReader THROWS StateError (it does not return Err),
so the `is Ok` fallback never sees it. Same contract the scores route
already relies on: the route degrades on Err, the test root wires the
dependency. An empty InMemoryParticipantReader yields Ok({}) -> no names
-> the payload is byte-identical to before, so every existing expectation
still holds.
"""
import subprocess
import sys
from pathlib import Path

DRY = "--dry" in sys.argv

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"missing project root: {ROOT}"

REL = "apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart"
p = ROOT / REL
assert p.is_file(), f"missing file: {p}"
src = p.read_text(encoding="utf-8")

OLD = """    final root = CompositionRoot.forTesting(
      adminListFixturePredictions: AdminListFixturePredictions(
        fixturePredictionRepository: predictions,
        auditRecorder: recorder,
      ),
    );"""

NEW = """    final root = CompositionRoot.forTesting(
      adminListFixturePredictions: AdminListFixturePredictions(
        fixturePredictionRepository: predictions,
        auditRecorder: recorder,
      ),
      // The route joins display names onto the payload; the absent stub
      // throws rather than returning Err, so this slice must be wired. An
      // empty reader resolves no names, which is exactly the degraded case
      // the route is specified to tolerate -- the payload keeps its
      // pre-join shape.
      adminGetParticipantDisplayNames: AdminGetParticipantDisplayNames(
        participantReader: InMemoryParticipantReader(),
      ),
    );"""

n = src.count(OLD)
assert n == 1, f"anchor matched {n} times"
p.write_text(src.replace(OLD, NEW), encoding="utf-8")
print(f"ok {REL}")


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    if DRY:
        return
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


run(f"dart format {REL}")
run("cd apps/server && flutter test --reporter=failures-only")
run("cd packages/contracts && flutter test --reporter=failures-only")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib/features/admin")
run("cd apps/mobile && flutter test --reporter=failures-only")

if not DRY:
    LOG = ROOT / "docs/checkpoints/session-log.md"
    LOG.write_text(
        LOG.read_text(encoding="utf-8")
        + "\n2026-09-05 \u2014 20+21_predictions_display_name: "
        "\u00ab\u0627\u0644\u062a\u0648\u0642\u0639\u0627\u062a\u00bb \u0641\u064a "
        "\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0634\u0631\u0641 \u0635\u0627\u0631\u062a "
        "\u062a\u0639\u0631\u0636 \u0627\u0644\u0627\u0633\u0645. displayName "
        "\u0623\u064f\u0636\u064a\u0641 \u0625\u0644\u0649 FixturePredictionDto "
        "\u0628\u0646\u0641\u0633 \u0634\u0643\u0644 ParticipantFixtureScoreDto "
        "(\u0627\u062e\u062a\u064a\u0627\u0631\u064a\u060c \u0627\u0641\u062a\u0631\u0627\u0636\u064a "
        "''\u060c \u0648\u064a\u064f\u062d\u0630\u0641 \u0645\u0646 JSON \u0639\u0646\u062f "
        "\u0641\u0631\u0627\u063a\u0647)\u060c \u0648\u0627\u0644\u0631\u0628\u0637 \u0641\u064a "
        "\u0645\u0633\u0627\u0631 GET /admin/fixtures/{id}/predictions \u0639\u0628\u0631 "
        "AdminGetParticipantDisplayNames \u0646\u0641\u0633\u0647 \u0627\u0644\u0630\u064a "
        "\u064a\u0633\u062a\u062e\u062f\u0645\u0647 \u0645\u0633\u0627\u0631 scores. "
        "\u0627\u0644\u0645\u0641\u0627\u062c\u0623\u0629: "
        "_UnwiredParticipantReader \u064a\u0631\u0645\u064a StateError \u0648\u0644\u0627 "
        "\u064a\u0639\u064a\u062f Err\u060c \u0641\u0627\u0646\u0643\u0633\u0631\u062a "
        "\u0623\u0631\u0628\u0639\u0629 \u0627\u062e\u062a\u0628\u0627\u0631\u0627\u062a "
        "\u0645\u0633\u0627\u0631\u061b \u0627\u0644\u062d\u0644\u0651 \u0631\u0628\u0637 "
        "InMemoryParticipantReader \u0641\u0627\u0631\u063a \u0641\u064a "
        "\u062c\u0630\u0631 \u0627\u0644\u0627\u062e\u062a\u0628\u0627\u0631 (\u0644\u0627 "
        "\u0627\u0628\u062a\u0644\u0627\u0639 \u0627\u0633\u062a\u062b\u0646\u0627\u0621 "
        "\u0641\u064a \u0627\u0644\u0645\u0633\u0627\u0631) \u2014 "
        "\u0648\u0647\u0648 \u0646\u0641\u0633 \u0639\u0642\u062f \u0645\u0633\u0627\u0631 "
        "scores. \u0644\u0627 \u064a\u0648\u062c\u062f \u0628\u0639\u062f "
        "\u0627\u062e\u062a\u0628\u0627\u0631 \u064a\u0624\u0643\u0651\u062f "
        "\u0638\u0647\u0648\u0631 \u0627\u0633\u0645 \u0641\u0639\u0644\u064a. "
        "\u2014 packages/contracts/lib/src/fixture_prediction_dto.dart, "
        "apps/server/lib/http/fixture_prediction_dto_mapper.dart, "
        "apps/server/routes/admin/fixtures/[id]/predictions/index.dart, "
        "apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart, "
        "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart\n",
        encoding="utf-8",
    )

run("git add packages/contracts/lib/src/fixture_prediction_dto.dart "
    "apps/server/lib/http/fixture_prediction_dto_mapper.dart "
    "'apps/server/routes/admin/fixtures/[id]/predictions/index.dart' "
    "apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart "
    "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart "
    "docs/checkpoints/session-log.md")
run('git commit -m "feat(admin): join participant display name onto raw predictions read"')
print("done - no push")
