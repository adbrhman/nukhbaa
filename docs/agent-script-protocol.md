# Agent script protocol

How an AI assistant delivers code changes to this repository. Read this and
`docs/project-context.md` (the only project reference) before proposing
anything. The owner works from Termux on Android: an Arabic keyboard corrupts
typed English commands and long heredocs break, so every change arrives as one
downloadable bash script.

## 1. Before proposing a change

1. **Read the real tree, not memory.** Work from the uploaded zip or
   `raw.githubusercontent.com/adbrhman/nukhbaa/main/<path>` (pushed commits
   only). Verify every file, function, column and anchor you mention exists.
2. **Trace the whole chain** before judging: route -> use-case -> port ->
   adapter -> database -> `api_client` -> provider -> widget. Count the layers;
   one layer is rarely enough.
3. **Find the guards** a change must pass: `tooling/import_lint`
   (`allowedDependencies`), asserts, CI `--dart-define` plumbing
   (`.github/workflows/*.yml`), generated files (`apps/mobile/lib/l10n/`,
   `*.g.dart`).
4. **Measure before changing.** Numbers first (Supabase usage,
   `pg_stat_statements`, contrast ratios, the installed package source under
   `~/.pub-cache`). A setting not shown to cause the problem is not changed.
5. **One question** when a request has more than one reasonable reading. No
   guessing.

## 2. The script

One bash script per batch, named `NN_short_name.sh`, downloaded to
`/sdcard/Download`.

- **Guards first:** `whoami` is `dev`; `pubspec.yaml` and
  `docs/project-context.md` exist; no uncommitted changes in tracked files
  (`git status --porcelain --untracked-files=no`). Restore the generated l10n
  output (`git checkout -- apps/mobile/lib/l10n/`) before the guard when the
  batch does not touch l10n: any local `flutter` run regenerates it.
- **The patch** is a Python script, base64-encoded inside the bash script,
  ASCII only (escape non-ASCII text with `ascii()`), using `str.replace` on
  literal anchors built from the file's actual text:
  - every anchor must occur **exactly once**, checked for all files before any
    file is written;
  - an edit already applied is skipped, so a second run is harmless;
  - a new file is refused if it already exists with different content.
- **Rollback:** `trap ... ERR` restores modified files (`git checkout --`) and
  deletes new ones, so a failure leaves the tree as it was, with nothing
  committed.
- **Verification, in order:**
  1. `flutter pub get` only when a pubspec changed, then restore l10n;
  2. `dart format` on the touched files only;
  3. `dart analyze --fatal-warnings .`;
  4. `dart run tooling/import_lint/bin/import_lint.dart`;
  5. `flutter test --reporter=failures-only` for the new test, then the full
     suite of each affected package (`dart test` fails here under
     `resolution: workspace`).
- **Commit** with explicit file names. Never `git add -A`. Never push: pushing
  needs the owner's permission every session.

## 3. Tests

A test goes through the feature's real entry point: the adapter the
composition root wires, the real `AppTheme`, the real screen with its
providers overridden. A test that only checks a file exists, or that bypasses
the faulty function, reveals nothing.

## 4. Before sending

- Apply the patch to a copy of the repository **twice** (the second run must
  skip everything).
- Run the whole script on a git copy with stub `dart`/`flutter` binaries,
  once on the success path and once with a forced failure, to prove the
  rollback.
- Validate any YAML or JSON the patch touches or produces.
- State plainly what could not be tested (for example: no Dart SDK in the
  assistant's sandbox, so analysis and tests run only on the device).

## 5. Rules

- No placeholders, no TODOs, no mocks in production code.
- No new dependency and no architectural change without the owner's approval.
- A migration is additive only: no deletion of any user, account, points,
  fixture or prediction.

## 6. The reply

Arabic, short. Show only the changed lines, under each file name. Then the
run command:

```bash
f="$(ls -t /sdcard/Download/NN_short_name*.sh | head -1)"; echo "using: $f"; cp "$f" ~/fix.sh && cd ~/nukhbaa-backup-1787537565 && bash ~/fix.sh
```

After `DONE`, the owner pushes with `git push origin main` (Northflank
redeploys the server; CI builds the APK, installed through the in-app OTA
update).

## 7. Reference skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO=/home/dev/nukhbaa-backup-1787537565
[ "$(whoami)" = "dev" ] || { echo "wrong user"; exit 1; }
cd "$REPO"
[ -f pubspec.yaml ] && [ -f docs/project-context.md ] || { echo "not the repo root"; exit 1; }
git checkout -- apps/mobile/lib/l10n/
[ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --short; exit 1; }

NEW="path/to/new_file.dart"
MOD="path/to/changed_file.dart"
rollback() { git checkout -- $MOD 2>/dev/null || true; rm -f $NEW; }
trap rollback ERR

base64 -d > /tmp/patch.py <<'B64EOF'
...base64 of the Python patch...
B64EOF
python3 /tmp/patch.py && rm -f /tmp/patch.py

dart format $NEW $MOD
dart analyze --fatal-warnings .
dart run tooling/import_lint/bin/import_lint.dart
(cd apps/mobile && flutter test --reporter=failures-only)

git add $NEW $MOD
git commit -m "type(scope): what changed and why"
trap - ERR
echo "DONE. nothing pushed."
```
