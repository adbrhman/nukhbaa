import subprocess
from datetime import datetime

# --- 1) home_screen.dart: valueOrNull -> value (Riverpod 3.0 rename) ---
p1 = "apps/mobile/lib/features/auth/home_screen.dart"
with open(p1, "r", encoding="utf-8") as f:
    s1 = f.read()

old1 = "    final fixtureCount = fixtures.valueOrNull?.length;\n    final seasonCount = seasons.valueOrNull?.length;\n"
new1 = "    final fixtureCount = fixtures.value?.length;\n    final seasonCount = seasons.value?.length;\n"
assert old1 in s1, f"NOT FOUND in {p1}"
s1 = s1.replace(old1, new1)
with open(p1, "w", encoding="utf-8") as f:
    f.write(s1)

# --- 2) nukhbaa_shell.dart: remove unused import ---
p2 = "apps/mobile/lib/features/auth/nukhbaa_shell.dart"
with open(p2, "r", encoding="utf-8") as f:
    s2 = f.read()

old2 = "import 'account_screen.dart';\nimport 'session_controller.dart';\nimport 'home_screen.dart';\n"
new2 = "import 'account_screen.dart';\nimport 'home_screen.dart';\n"
assert old2 in s2, f"NOT FOUND in {p2}"
s2 = s2.replace(old2, new2)
with open(p2, "w", encoding="utf-8") as f:
    f.write(s2)

# --- 3) session log ---
log_path = "docs/checkpoints/session-log.md"
ts = datetime.now().strftime("%H:%M")
entry = (
    f"- [{ts}] \u0625\u0635\u0644\u0627\u062d: \u0641\u0634\u0644 CI \u0641\u064a "
    "dart analyze --fatal-warnings (exit 3) \u2014 valueOrNull \u062d\u064f\u0630\u0641 \u0641\u064a "
    "Riverpod 3.x (\u0627\u0633\u062a\u0628\u062f\u0627\u0644 .value)\u060c \u0637\u064f\u0628\u0651\u0642 "
    "\u0641\u064a fixtures/seasons \u0628\u0640 _OverviewCard\u061b \u062d\u0630\u0641 \u0627\u0633\u062a\u064a\u0631\u0627\u062f "
    "session_controller.dart \u063a\u064a\u0631 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645 \u0641\u064a "
    "nukhbaa_shell.dart | \u0645\u0644\u0641: apps/mobile/lib/features/auth/home_screen.dart, "
    "apps/mobile/lib/features/auth/nukhbaa_shell.dart | \u0627\u062e\u062a\u0628\u0627\u0631: "
    "\u0628\u0627\u0646\u062a\u0638\u0627\u0631 dart analyze --fatal-warnings .\n"
)
with open(log_path, "a", encoding="utf-8") as f:
    f.write(entry)

# --- 4) git add + commit ---
subprocess.run(["git", "add",
    "apps/mobile/lib/features/auth/home_screen.dart",
    "apps/mobile/lib/features/auth/nukhbaa_shell.dart",
    "docs/checkpoints/session-log.md",
], check=True)

commit_msg = (
    "fix(mobile): \u0625\u0635\u0644\u0627\u062d \u0641\u0634\u0644 CI \u0641\u064a "
    "dart analyze --fatal-warnings\n\n"
    "- home_screen.dart: valueOrNull -> value (Riverpod 3.x \u062d\u0630\u0641 valueOrNull)\n"
    "- nukhbaa_shell.dart: \u062d\u0630\u0641 \u0627\u0633\u062a\u064a\u0631\u0627\u062f "
    "session_controller.dart \u063a\u064a\u0631 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645"
)
subprocess.run(["git", "-c", "core.editor=true", "commit", "-m", commit_msg], check=True)

print("DONE.")
