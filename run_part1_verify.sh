#!/usr/bin/env bash
set -euo pipefail
cd /root/nukhbaa

melos run verify 2>&1 | tail -40

git add -A
git commit -m "fix(prediction): auto-join season on first prediction submit"
git push origin main
