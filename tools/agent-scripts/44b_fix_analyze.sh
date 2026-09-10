#!/usr/bin/env bash
# 44b_fix_analyze.sh
# Paste at:  dev@localhost:~/nukhbaa-backup-1787537565$
#
# Clears the two analyzer failures that stopped 44_me_seasons.sh before it
# could commit, then re-runs the full gate and commits 44's work together
# with this fix (44 left the files in the working tree, uncommitted).
set -euo pipefail

REPO=/home/dev/nukhbaa-backup-1787537565
[ "$(whoami)" = "dev" ] || { echo "wrong user: $(whoami) -- run inside proot ubuntu"; exit 1; }
cd "$REPO" || { echo "no repo at $REPO"; exit 1; }
[ -f pubspec.yaml ] || { echo "not the monorepo root"; exit 1; }

base64 -d > 44b_fix_analyze.py <<'B64EOF'
IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiJUd28gYW5hbHl6ZXIgZmFpbHVyZXMgZnJvbSB0aGUgbGFzdCB0d28gc2NyaXB0cy4K
CjEuIGBjb25zdCBMaXN0TXlTZWFzb25SZWNvcmRzKC4uLilgIC0tIGBfdW53aXJlZExlYWRlcmJvYXJkUmVwb3NpdG9yeWAgaXMg
YQogICBgc3RhdGljIGZpbmFsYCwgbm90IGEgYGNvbnN0YCwgc28gdGhlIGNvbnN0cnVjdG9yIGNhbm5vdCBiZSBjb25zdC1pbnZv
a2VkLgogICBFdmVyeSBzaWJsaW5nIGBfYWJzZW50KmAgZmFjdG9yeSBjYWxscyBpdHMgY29uc3RydWN0b3Igbm9uLWNvbnN0IGZv
ciB0aGUKICAgc2FtZSByZWFzb247IHRoaXMgb25lIGp1c3QgY29waWVkIGEgYGNvbnN0YCBpbi4KCjIuIGBpbXBvcnQgJ2F2YXRh
cl91cmwuZGFydCdgIC0tIGEgcmVsYXRpdmUgaW1wb3J0IGluc2lkZSBgbGliL2AsIHdoaWNoCiAgIGBhbHdheXNfdXNlX3BhY2th
Z2VfaW1wb3J0c2AgcmVqZWN0cy4gRXZlcnkgb3RoZXIgaW1wb3J0IGluIHRoYXQgZmlsZSBpcyBhCiAgIHBhY2thZ2U6IFVSSS4K
IiIiCmltcG9ydCBvcwppbXBvcnQgc3lzCgpST09UID0gb3MucGF0aC5hYnNwYXRoKG9zLnBhdGguZGlybmFtZShfX2ZpbGVfXykp
CgoKZGVmIHBhdGNoKHJlbCwgcGFpcnMpOgogICAgcGF0aCA9IG9zLnBhdGguam9pbihST09ULCByZWwpCiAgICBpZiBub3Qgb3Mu
cGF0aC5pc2ZpbGUocGF0aCk6CiAgICAgICAgc3lzLmV4aXQoIk1JU1NJTkc6ICIgKyByZWwpCiAgICBzcmMgPSBvcGVuKHBhdGgs
IGVuY29kaW5nPSJ1dGYtOCIpLnJlYWQoKQogICAgZm9yIGksIChvbGQsIG5ldykgaW4gZW51bWVyYXRlKHBhaXJzLCAxKToKICAg
ICAgICBpZiBuZXcgaW4gc3JjIGFuZCBvbGQgbm90IGluIHNyYzoKICAgICAgICAgICAgcHJpbnQoIiAgc2tpcCAgJXMgWyVkXSAo
YWxyZWFkeSBhcHBsaWVkKSIgJSAocmVsLCBpKSkKICAgICAgICAgICAgY29udGludWUKICAgICAgICBpZiBzcmMuY291bnQob2xk
KSAhPSAxOgogICAgICAgICAgICBzeXMuZXhpdCgiQU5DSE9SIHglZCBpbiAlcyBbZWRpdCAlZF0iICUgKHNyYy5jb3VudChvbGQp
LCByZWwsIGkpKQogICAgICAgIHNyYyA9IHNyYy5yZXBsYWNlKG9sZCwgbmV3LCAxKQogICAgb3BlbihwYXRoLCAidyIsIGVuY29k
aW5nPSJ1dGYtOCIpLndyaXRlKHNyYykKICAgIHByaW50KCIgIG9rICAgICIgKyByZWwpCgoKcGF0Y2goImFwcHMvc2VydmVyL2xp
Yi9jb21wb3NpdGlvbi9jb21wb3NpdGlvbl9yb290LmRhcnQiLCBbKAogICAgIiIiICBzdGF0aWMgTGlzdE15U2Vhc29uUmVjb3Jk
cyBfYWJzZW50TGlzdE15U2Vhc29uUmVjb3JkcygpID0+CiAgICAgIGNvbnN0IExpc3RNeVNlYXNvblJlY29yZHMoCiAgICAgICAg
bGVhZGVyYm9hcmRSZXBvc2l0b3J5OiBfdW53aXJlZExlYWRlcmJvYXJkUmVwb3NpdG9yeSwKICAgICAgKTsiIiIsCiAgICAiIiIg
IHN0YXRpYyBMaXN0TXlTZWFzb25SZWNvcmRzIF9hYnNlbnRMaXN0TXlTZWFzb25SZWNvcmRzKCkgPT4KICAgICAgTGlzdE15U2Vh
c29uUmVjb3JkcygKICAgICAgICBsZWFkZXJib2FyZFJlcG9zaXRvcnk6IF91bndpcmVkTGVhZGVyYm9hcmRSZXBvc2l0b3J5LAog
ICAgICApOyIiIiwKKV0pCgpwYXRjaCgiYXBwcy9zZXJ2ZXIvbGliL2h0dHAvbGVhZGVyYm9hcmRfZHRvX21hcHBlci5kYXJ0Iiwg
WygKICAgICJcbmltcG9ydCAnYXZhdGFyX3VybC5kYXJ0JztcbiIsCiAgICAiaW1wb3J0ICdwYWNrYWdlOnNlcnZlci9odHRwL2F2
YXRhcl91cmwuZGFydCc7XG4iLAopXSkKCnByaW50KCJhbGwgcGF0Y2hlcyBhcHBsaWVkIikK
B64EOF

python3 44b_fix_analyze.py
rm -f 44b_fix_analyze.py

FILES="
packages/domain/lib/src/leaderboard/participant_season_record.dart
packages/domain/lib/domain.dart
packages/application/lib/src/leaderboard/ports/leaderboard_repository.dart
packages/application/lib/src/leaderboard/list_my_season_records.dart
packages/application/lib/application.dart
packages/application/test/leaderboard/fakes.dart
packages/infrastructure/lib/src/leaderboard/postgres_leaderboard_repository.dart
packages/contracts/lib/src/leaderboard_dto.dart
apps/server/lib/http/leaderboard_dto_mapper.dart
apps/server/lib/composition/composition_root.dart
apps/server/routes/me/seasons.dart
apps/server/test/routes/competition_route_harness.dart
"

echo "==> format"
dart format $FILES

echo "==> analyze"
dart analyze --fatal-warnings .

echo "==> import_lint"
dart run tooling/import_lint/bin/import_lint.dart

echo "==> tests"
(cd packages/domain    && flutter test --reporter=failures-only)
(cd packages/contracts && flutter test --reporter=failures-only)
(cd apps/server        && flutter test --reporter=failures-only)

echo "==> commit"
git add $FILES
git commit -m "feat(api): GET /me/seasons -- per-season rank, points and accuracy counts"
git --no-pager log --stat -1

echo
echo "done. nothing pushed."
