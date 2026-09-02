import re
import subprocess

AR = "apps/mobile/lib/l10n/app_ar.arb"
EN = "apps/mobile/lib/l10n/app_en.arb"

SIMPLE_KEYS = ["adminSelectRoundLabel", "adminNoRoundsHint", "adminNoFixturesHint"]


def remove_simple_key_line(path, key):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    pattern = re.compile(r'^\s*"' + re.escape(key) + r'":')
    matches = [i for i, l in enumerate(lines) if pattern.match(l)]
    if len(matches) != 1:
        raise SystemExit("فشل: " + key + " في " + path + " ظهر " + str(len(matches)) + " مرة بدل 1")
    del lines[matches[0]]
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("حُذف " + key + " من " + path)


def remove_key_with_meta_block(path, key):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    key_pattern = re.compile(r'^\s*"' + re.escape(key) + r'":')
    key_idx = [i for i, l in enumerate(lines) if key_pattern.match(l)]
    if len(key_idx) != 1:
        raise SystemExit("فشل: " + key + " في " + path + " ظهر " + str(len(key_idx)) + " مرة بدل 1")
    start = key_idx[0]
    end = start
    meta_pattern = re.compile(r'^\s*"@' + re.escape(key) + r'":\s*\{')
    if meta_pattern.match(lines[start + 1]):
        depth = 0
        j = start + 1
        started = False
        while j < len(lines):
            depth += lines[j].count("{") - lines[j].count("}")
            started = True
            j += 1
            if started and depth == 0:
                break
        end = j - 1
    del lines[start:end + 1]
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("حُذف " + key + " (+meta إن وُجد) من " + path)


for k in SIMPLE_KEYS:
    remove_simple_key_line(AR, k)
    remove_simple_key_line(EN, k)

remove_key_with_meta_block(AR, "adminRoundOptionLabel")
remove_key_with_meta_block(EN, "adminRoundOptionLabel")

print("\n== flutter gen-l10n ==")
subprocess.run(["flutter", "gen-l10n"], cwd="apps/mobile")

print("\n== dart format l10n ==")
subprocess.run(["dart", "format", "lib/l10n"], cwd="apps/mobile")

print("\n== flutter analyze ==")
subprocess.run(["flutter", "analyze"], cwd="apps/mobile")

print("\n== git diff --stat ==")
subprocess.run(["git", "diff", "--stat", "--",
                 "apps/mobile/lib/l10n/",
                 "apps/mobile/lib/features/admin/widgets/admin_pickers.dart"])
