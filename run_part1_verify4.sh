#!/usr/bin/env bash
set -euo pipefail
cd /root/nukhbaa

dart format apps/mobile/lib/features/prediction/prediction_controller.dart

melos run verify 2>&1 | tail -60

git add -A
git commit -m "fix(prediction): auto-join season on first prediction submit"
git push origin main
