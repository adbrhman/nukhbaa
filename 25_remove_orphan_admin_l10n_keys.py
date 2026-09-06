#!/usr/bin/env python3
"""25_remove_orphan_admin_l10n_keys.

The eleven keys that only the deleted placeholder sections read. The
generated app_localizations*.dart are tracked in this repo, so they are
regenerated and committed alongside the ARB edit -- otherwise the getters
outlive their keys and the next gen-l10n produces an unrelated diff.
"""
import json
import subprocess
import sys
from pathlib import Path

DRY = "--dry" in sys.argv

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"missing project root: {ROOT}"

KEYS = [
    "adminDailyDoublesTab",
    "adminLeaderboardsTab",
    "adminCompetitionsTab",
    "adminTeamsTab",
    "adminSocialTab",
    "adminNotificationsTab",
    "adminReportsAnalyticsTab",
    "adminSystemHealthTab",
    "adminRolesPermissionsTab",
    "adminSettingsTab",
    "adminSectionComingSoon",
]

# Nothing in lib/ or test/ may still read them -- the generated files are the
# only expected hits, and they are about to be regenerated.
grep = subprocess.run(
    "grep -rn --include=*.dart -E '"
    + "|".join(KEYS)
    + "' apps/mobile/lib apps/mobile/test | grep -v 'lib/l10n/'",
    shell=True,
    cwd=ROOT,
    capture_output=True,
    text=True,
)
assert not grep.stdout.strip(), f"still referenced:\n{grep.stdout}"

for name in ("app_ar.arb", "app_en.arb"):
    p = ROOT / "apps/mobile/lib/l10n" / name
    assert p.is_file(), f"missing file: {p}"
    lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
    kept = []
    dropped = 0
    for line in lines:
        stripped = line.lstrip()
        if any(
            stripped.startswith(f'"{k}"') or stripped.startswith(f'"@{k}"')
            for k in KEYS
        ):
            dropped += 1
            continue
        kept.append(line)
    assert dropped == len(KEYS), f"{name}: dropped {dropped}, expected {len(KEYS)}"
    text = "".join(kept)
    json.loads(text)  # a trailing comma before } would fail here
    p.write_text(text, encoding="utf-8")
    print(f"ok {name} (-{dropped})")


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    if DRY:
        return
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


run("cd apps/mobile && flutter gen-l10n")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib")
run("cd apps/mobile && flutter test --reporter=failures-only")

if not DRY:
    LOG = ROOT / "docs/checkpoints/session-log.md"
    LOG.write_text(
        LOG.read_text(encoding="utf-8")
        + "\n2026-09-05 \u2014 25_remove_orphan_admin_l10n_keys: "
        "\u062d\u064f\u0630\u0641\u062a \u0623\u062d\u062f \u0639\u0634\u0631 "
        "\u0645\u0641\u062a\u0627\u062d ARB \u0644\u0645 \u064a\u0639\u062f "
        "\u0644\u0647\u0627 \u0642\u0627\u0631\u0626 \u0628\u0639\u062f "
        "\u062d\u0630\u0641 \u0627\u0644\u0623\u0642\u0633\u0627\u0645 "
        "\u0627\u0644\u0646\u0627\u0626\u0628\u0629 "
        "(adminDailyDoublesTab \u0648\u0625\u062e\u0648\u0627\u062a\u0647\u0627 "
        "\u0648adminSectionComingSoon) \u0645\u0646 app_ar.arb "
        "\u0648app_en.arb\u060c \u062b\u0645 "
        "\u0623\u064f\u0639\u064a\u062f \u062a\u0648\u0644\u064a\u062f "
        "app_localizations*.dart \u0644\u0623\u0646\u0647\u0627 "
        "\u0645\u064f\u062a\u062a\u0628\u064e\u0651\u0639\u0629 \u0641\u064a "
        "\u0627\u0644\u0645\u0633\u062a\u0648\u062f\u0639\u060c "
        "\u0641\u0644\u0648 \u062a\u064f\u0631\u0643\u062a "
        "\u0644\u0628\u0642\u064a\u062a "
        "\u0627\u0644\u0645\u064f\u0633\u062a\u0642\u0628\u0650\u0644\u0627\u062a "
        "\u0628\u0644\u0627 \u0645\u0641\u0627\u062a\u064a\u062d "
        "\u0648\u0623\u062e\u0631\u062c gen-l10n "
        "\u0627\u0644\u0642\u0627\u062f\u0645 \u0641\u0631\u0642\u064b\u0627 "
        "\u063a\u064a\u0631 \u0630\u064a \u0635\u0644\u0629. "
        "\u062a\u062d\u0642\u0651\u0642 \u0642\u0628\u0644 "
        "\u0627\u0644\u062d\u0630\u0641: \u0644\u0627 \u0645\u0631\u062c\u0639 "
        "\u0644\u0647\u0627 \u0641\u064a lib \u0623\u0648 test "
        "\u062e\u0627\u0631\u062c lib/l10n\u060c "
        "\u0648\u0627\u0644\u0645\u0644\u0641\u0627\u0646 "
        "\u064a\u064f\u062d\u0644\u0651\u0644\u0627\u0646 \u0643\u0640JSON "
        "\u0628\u0639\u062f \u0627\u0644\u062a\u0639\u062f\u064a\u0644 "
        "\u2014 apps/mobile/lib/l10n/app_ar.arb, "
        "apps/mobile/lib/l10n/app_en.arb, "
        "apps/mobile/lib/l10n/app_localizations.dart, "
        "apps/mobile/lib/l10n/app_localizations_ar.dart, "
        "apps/mobile/lib/l10n/app_localizations_en.dart\n",
        encoding="utf-8",
    )

run("git add apps/mobile/lib/l10n/app_ar.arb "
    "apps/mobile/lib/l10n/app_en.arb "
    "apps/mobile/lib/l10n/app_localizations.dart "
    "apps/mobile/lib/l10n/app_localizations_ar.dart "
    "apps/mobile/lib/l10n/app_localizations_en.dart "
    "docs/checkpoints/session-log.md")
run('git commit -m "chore(l10n): remove keys orphaned by the placeholder-section deletion"')
print("done - no push")
