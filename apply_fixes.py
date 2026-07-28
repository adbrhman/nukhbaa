#!/usr/bin/env python3
"""
apply_fixes.py — applies the 8 reviewed CI/CD/Docker fixes to the ACTUAL
current state of the repo, safely.

Run this from the repo root, on a fresh branch, AFTER `git pull` on main:

    git checkout main && git pull
    git checkout -b fix/ci-cd-glibc-cors-docs
    python3 apply_fixes.py

For every fix this script:
  - SKIPS with a note if the fix is already present (idempotent — safe to
    re-run).
  - APPLIES it if the expected "before" text is found exactly once.
  - WARNS (does NOT touch the file) if neither the "before" nor "after"
    text matches — this means the file has drifted since the last review
    (e.g. a newer commit touched it) and needs a manual look instead of a
    blind overwrite.

Nothing is committed or pushed by this script. Review `git diff` yourself,
then commit and push.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
REPORT = []


def patch(relpath: str, label: str, old: str, new: str):
    path = ROOT / relpath
    if not path.exists():
        REPORT.append(("MISSING", relpath, label, f"file not found: {relpath}"))
        return
    text = path.read_text(encoding="utf-8")

    if new in text:
        REPORT.append(("SKIP", relpath, label, "already applied"))
        return

    count = text.count(old)
    if count == 1:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        REPORT.append(("OK", relpath, label, "applied"))
    elif count == 0:
        REPORT.append(("WARN", relpath, label,
                        "expected 'before' text not found — file has drifted, review manually"))
    else:
        REPORT.append(("WARN", relpath, label,
                        f"'before' text matched {count} times (expected 1) — review manually"))


def full_replace_if_signature(relpath: str, label: str, old_signature: str, new_content: str):
    """For files meant to be replaced wholesale (Dockerfile), but only if the
    known-broken signature is still present — otherwise warn instead of
    clobbering unrelated changes."""
    path = ROOT / relpath
    if not path.exists():
        REPORT.append(("MISSING", relpath, label, f"file not found: {relpath}"))
        return
    text = path.read_text(encoding="utf-8")
    if new_content.strip() in text.strip():
        REPORT.append(("SKIP", relpath, label, "already applied"))
        return
    if old_signature in text:
        path.write_text(new_content, encoding="utf-8")
        REPORT.append(("OK", relpath, label, "applied (full replace)"))
    else:
        REPORT.append(("WARN", relpath, label,
                        "known broken signature not found — file has drifted, review manually before replacing"))


# ---------------------------------------------------------------------------
# Fix 1 — CI: run all Dart package tests via Melos (was hand-maintained list
# that silently excluded packages/api_client)
# ---------------------------------------------------------------------------
patch(
    ".github/workflows/build-verification.yml",
    "Fix 1: melos run test replaces hand-maintained package loop",
    old=(
        '      - name: Test — Dart packages\n'
        '        run: |\n'
        '          set -e\n'
        '          for p in packages/shared packages/domain packages/contracts \\\n'
        '                   packages/application packages/infrastructure \\\n'
        '                   tooling/import_lint apps/server; do\n'
        '            echo "::group::dart test $p"\n'
        '            (cd "$p" && dart test)\n'
        '            echo "::endgroup::"\n'
        '          done\n'
        '\n'
        '      - name: Test — apps/mobile (flutter)\n'
        '        working-directory: apps/mobile\n'
        '        run: flutter test --coverage\n'
    ),
    new=(
        '      # Single source of truth: the Melos scripts in the root pubspec.yaml.\n'
        '      # The previous hand-maintained package list silently EXCLUDED\n'
        '      # packages/api_client (5 test files, the entire HTTP transport layer),\n'
        '      # so "CI green" did not mean "melos run test green". Any future package\n'
        '      # is now picked up automatically via packageFilters: dirExists: test.\n'
        '      - name: Test — all Dart packages (melos)\n'
        '        run: dart run melos run test\n'
        '\n'
        '      - name: Test — apps/mobile (flutter, with coverage)\n'
        '        working-directory: apps/mobile\n'
        '        run: flutter test --coverage\n'
    ),
)

# ---------------------------------------------------------------------------
# Fix 3 — CI: build the server Docker image (was never built anywhere)
# ---------------------------------------------------------------------------
patch(
    ".github/workflows/build-verification.yml",
    "Fix 3: add build_server_image job",
    old=(
        '      - uses: actions/upload-artifact@v4\n'
        '        with:\n'
        '          name: nukhba-android-apk\n'
        '          path: apps/mobile/build/app/outputs/flutter-apk/*.apk\n'
        '          retention-days: 14\n'
    ),
    new=(
        '      - uses: actions/upload-artifact@v4\n'
        '        with:\n'
        '          name: nukhba-android-apk\n'
        '          path: apps/mobile/build/app/outputs/flutter-apk/*.apk\n'
        '          retention-days: 14\n'
        '\n'
        '  build_server_image:\n'
        '    name: Build server Docker image\n'
        '    runs-on: ubuntu-latest\n'
        '    needs: workspace\n'
        '    timeout-minutes: 30\n'
        '    steps:\n'
        '      - uses: actions/checkout@v4\n'
        '\n'
        '      - uses: docker/setup-buildx-action@v3\n'
        '\n'
        '      # Build only. Not pushed anywhere yet: the point is to keep the\n'
        '      # Dockerfile from rotting, and to catch the pub-workspace detachment\n'
        '      # (resolution: workspace inside build/) at PR time instead of at\n'
        '      # first deploy.\n'
        '      - name: Build image\n'
        '        uses: docker/build-push-action@v6\n'
        '        with:\n'
        '          context: .\n'
        '          push: false\n'
        '          load: true\n'
        '          tags: nukhba-server:ci\n'
        '          cache-from: type=gha\n'
        '          cache-to: type=gha,mode=max\n'
        '\n'
        '      # Proves the compiled exe actually links against the runtime image\'s\n'
        '      # glibc — the exact defect the debian->ubuntu base change fixes. The\n'
        '      # server exits non-zero without DB config, which is expected and fine;\n'
        '      # we only assert it is NOT a loader/glibc failure.\n'
        '      - name: Smoke-check the binary loads\n'
        '        run: |\n'
        '          set -o pipefail\n'
        '          out="$(docker run --rm --entrypoint /bin/sh nukhba-server:ci \\\n'
        '                 -c \'ldd /app/server\' 2>&1)" || true\n'
        '          echo "$out"\n'
        '          if echo "$out" | grep -qi \'not found\'; then\n'
        '            echo "::error::Missing shared library in runtime image (glibc mismatch)."\n'
        '            exit 1\n'
        '          fi\n'
    ),
)

# ---------------------------------------------------------------------------
# Fix 2 — Dockerfile: matching glibc runtime base + non-root user
# (full replace, but only if the known-broken debian:bookworm-slim runtime
# signature is still present)
# ---------------------------------------------------------------------------
DOCKERFILE_NEW = '''# syntax=docker/dockerfile:1
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app
COPY . .

# Resolve the whole pub workspace once from the root.
RUN flutter pub get

RUN dart pub global activate dart_frog_cli
ENV PATH="$PATH:/root/.pub-cache/bin"

WORKDIR /app/apps/server
RUN mkdir -p public && dart_frog build

# dart_frog build copies apps/server/pubspec.yaml verbatim into build/, so it
# still carries resolution: workspace while sitting OUTSIDE the workspace
# root, and its path deps no longer resolve. Detach it and pin the internal
# packages to absolute paths before resolving.
WORKDIR /app/apps/server/build
RUN sed -i '/^resolution:[[:space:]]*workspace[[:space:]]*$/d' pubspec.yaml && \\
    printf '%s\\n' \\
      'dependency_overrides:' \\
      '  shared:' \\
      '    path: /app/packages/shared' \\
      '  domain:' \\
      '    path: /app/packages/domain' \\
      '  contracts:' \\
      '    path: /app/packages/contracts' \\
      '  application:' \\
      '    path: /app/packages/application' \\
      '  infrastructure:' \\
      '    path: /app/packages/infrastructure' \\
      > pubspec_overrides.yaml && \\
    dart pub get && \\
    dart compile exe bin/server.dart -o server

# RUNTIME BASE MUST MATCH THE BUILD BASE'S glibc.
# ghcr.io/cirruslabs/flutter:3.44.0 -> cirruslabs/android-sdk:36
# -> cirruslabs/android-sdk:tools -> ubuntu:24.04  (glibc 2.39).
# The previous runtime was debian:bookworm-slim (glibc 2.36): the image built
# fine but dart compile exe output dies at startup with
# "version `GLIBC_2.38' not found". Dart does not support cross-glibc runs.
FROM ubuntu:24.04
RUN apt-get update && \\
    apt-get install -y --no-install-recommends ca-certificates && \\
    rm -rf /var/lib/apt/lists/*

# Do not run the API as root.
RUN useradd --system --uid 10001 --create-home --shell /usr/sbin/nologin nukhba
WORKDIR /app
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/server ./server
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/public ./public
USER nukhba

ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
'''
full_replace_if_signature(
    "Dockerfile",
    "Fix 2: matching glibc runtime base + non-root user",
    old_signature="FROM debian:bookworm-slim",
    new_content=DOCKERFILE_NEW,
)

# ---------------------------------------------------------------------------
# Fix 4 — .env.example: add NUKHBA_CORS_ALLOWED_ORIGINS, fix PORT
# ---------------------------------------------------------------------------
patch(
    ".env.example",
    "Fix 4: add NUKHBA_CORS_ALLOWED_ORIGINS, correct PORT var",
    old=(
        '# Server\n'
        'NUKHBA_ENV=development\n'
        'NUKHBA_PORT=8080\n'
    ),
    new=(
        '# Server\n'
        'NUKHBA_ENV=development\n'
        '# NOTE: the port is read by dart_frog from the standard PORT variable\n'
        '# (Cloud Run sets it automatically). NUKHBA_PORT is NOT read by anything.\n'
        'PORT=8080\n'
        '\n'
        "# CORS allow-list (comma-separated, scheme://host only — NO path, because the\n"
        "# browser's Origin header never includes one). Read by\n"
        '# apps/server/routes/_middleware.dart; when unset it falls back to the\n'
        '# hardcoded GitHub Pages origin + localhost. ALWAYS set it explicitly on the\n'
        '# hosting platform so a repo/username change cannot silently break the client.\n'
        'NUKHBA_CORS_ALLOWED_ORIGINS=https://adbrhman.github.io\n'
    ),
)

# ---------------------------------------------------------------------------
# Fix 5 — README.md: correct local-gate command + dangling docs/progress.md
# reference
# ---------------------------------------------------------------------------
patch(
    "README.md",
    "Fix 5a: correct local verification command in README",
    old=(
        '## البوابة المحلية (نفس CI)\n'
        '\n'
        '    flutter pub get\n'
        '    (cd apps/mobile && dart run build_runner build --delete-conflicting-outputs)\n'
        '    dart analyze --fatal-warnings .\n'
        '    dart format --output=none --set-exit-if-changed .\n'
        '    dart run tooling/import_lint/bin/import_lint.dart\n'
        '    dart pub global run melos run test\n'
    ),
    new=(
        '## البوابة المحلية (نفس CI)\n'
        '\n'
        '    flutter pub get\n'
        '    (cd apps/mobile && dart run build_runner build --delete-conflicting-outputs)\n'
        '    dart run melos run verify\n'
        '\n'
        '`melos run verify` هو الأمر الصحيح ويطابق تمامًا خطوات\n'
        '`.github/workflows/build-verification.yml` (format-check ثم analyze ثم\n'
        'import-lint ثم test ثم test-mobile). لا تستخدم `dart pub global run melos\n'
        'run test` — هذا الأمر ناقص ويفترض تثبيتًا عامًا لـ melos غير لازم أصلًا،\n'
        'لأن `melos` مُعرَّف كـ `dev_dependency` في `pubspec.yaml` الجذر ويُشغَّل عبر\n'
        '`dart run melos ...`.\n'
    ),
)
patch(
    "README.md",
    "Fix 5b: replace dangling docs/progress.md reference",
    old=(
        '## حالة المشروع\n'
        '\n'
        'المصدر الوحيد المعتمد: `docs/progress.md`. أي نسخة أخرى قديمة.\n'
    ),
    new=(
        '## حالة المشروع\n'
        '\n'
        '- `docs/next-task.md` — المهمة التالية والحالة الحالية.\n'
        '- `docs/project-context.md` — السياق المعماري الكامل.\n'
        '- حالة البناء الفعلية هي دائمًا آخر run في تبويب Actions، لا أي ملف توثيق.\n'
        '\n'
        'الواجهة المنشورة: https://adbrhman.github.io/nukhbaa/\n'
    ),
)

# ---------------------------------------------------------------------------
# Fix 6 — deploy-pages.yml: gate deploy on Build Verification success
# ---------------------------------------------------------------------------
patch(
    ".github/workflows/deploy-pages.yml",
    "Fix 6a: trigger on workflow_run instead of push",
    old=(
        'on:\n'
        '  push:\n'
        '    branches: [main]\n'
        '  workflow_dispatch: {}\n'
    ),
    new=(
        'on:\n'
        '  # Deploy ONLY after Build Verification has actually passed on main.\n'
        '  # Previously this ran in parallel with the gate, so a red test suite still\n'
        '  # published to the live site as long as flutter build web compiled.\n'
        '  workflow_run:\n'
        '    workflows: ["Build Verification"]\n'
        '    types: [completed]\n'
        '    branches: [main]\n'
        '  workflow_dispatch: {}\n'
    ),
)
patch(
    ".github/workflows/deploy-pages.yml",
    "Fix 6b: guard job on successful conclusion",
    old=(
        'jobs:\n'
        '  build_and_deploy:\n'
        '    runs-on: ubuntu-latest\n'
    ),
    new=(
        'jobs:\n'
        '  build_and_deploy:\n'
        "    if: >-\n"
        "      github.event_name == 'workflow_dispatch' ||\n"
        "      github.event.workflow_run.conclusion == 'success'\n"
        '    runs-on: ubuntu-latest\n'
    ),
)
patch(
    ".github/workflows/deploy-pages.yml",
    "Fix 6c: checkout the exact commit that passed CI",
    old='      - uses: actions/checkout@v4\n',
    new=(
        '      - uses: actions/checkout@v4\n'
        '        with:\n'
        "          ref: ${{ github.event.workflow_run.head_sha || github.ref }}\n"
    ),
)

# ---------------------------------------------------------------------------
# Fix 7 — docs/next-task.md: remove contradicting "Exact Next Command"
# ---------------------------------------------------------------------------
patch(
    "docs/next-task.md",
    "Fix 7a: remove contradicting Last Completed Step line",
    old=(
        '## Status: No outstanding tasks — verification completed 2026-07-27, see section above.\n'
        '\n'
        '**Last Completed Step:** Step 3 (build_runner, verified present).\n'
        '\n'
        '---\n'
    ),
    new=(
        '## Status: No outstanding tasks — verification completed 2026-07-27, see section above.\n'
        '\n'
        '---\n'
    ),
)
patch(
    "docs/next-task.md",
    "Fix 7b: remove dangerous Exact Next Command section",
    old=(
        '## Exact Next Command\n'
        '\n'
        '**Environment requirement:** Capable machine with ≥ 8 GB RAM  \n'
        '(NOT the old 985 MiB sandbox. GitHub Codespaces or local machine.)\n'
        '\n'
        '```bash\n'
        'dart pub get\n'
        'dart run build_runner build --delete-conflicting-outputs\n'
        'dart analyze --fatal-infos --fatal-warnings .\n'
    ),
    new=(
        '## الأمر الوحيد المعتمد للتحقق المحلي\n'
        '\n'
        '```bash\n'
        'flutter pub get\n'
        '(cd apps/mobile && dart run build_runner build --delete-conflicting-outputs)\n'
        'dart run melos run verify\n'
        '```\n'
        '\n'
        '`melos run verify` مطابق تمامًا لـ `.github/workflows/build-verification.yml`.\n'
        'لا تستخدم `--fatal-infos` محليًا: CI لا يستخدمه، و111 مشكلة info مقبولة حاليًا\n'
        'ومسجّلة كبند backlog منفصل.\n'
    ),
)

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
print("=" * 78)
for status, relpath, label, note in REPORT:
    print(f"[{status:7}] {relpath:45} {label}\n           -> {note}")
print("=" * 78)

n_ok = sum(1 for r in REPORT if r[0] == "OK")
n_skip = sum(1 for r in REPORT if r[0] == "SKIP")
n_warn = sum(1 for r in REPORT if r[0] == "WARN")
n_missing = sum(1 for r in REPORT if r[0] == "MISSING")
print(f"Applied: {n_ok}  Skipped(already applied): {n_skip}  "
      f"Needs manual review: {n_warn}  Missing files: {n_missing}")
print()
print("Note: Fix 8 (PWA icons) is intentionally NOT handled by this script —")
print("run generate_icons.py separately (requires `pip install pillow`).")

if n_warn or n_missing:
    sys.exit(1)
