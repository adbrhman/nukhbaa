#!/usr/bin/env bash
# Uploads the 36 UEFA Europa League 2026/27 crest PNGs to the `team-logos`
# Supabase Storage bucket, renamed from their source filenames to
# `<slug>.png` (the exact path europa_2026_27_crests.sql's crest_url
# values already point at — computed deterministically, not looked up).
#
# Prerequisites:
#   - Migration 0026 (team-logos bucket) applied to the target project.
#   - `supabase login` already run (or SUPABASE_ACCESS_TOKEN exported) —
#     this needs an authenticated CLI session; it cannot run in a sandbox
#     with no Supabase credentials, which is why this is a standalone
#     script instead of something run inline as part of this task.
#
# Usage:
#   ./upload_europa_2026_27_crests.sh /path/to/36-png-folder
#
# The folder must contain the 36 files named exactly as the `filename`
# column in ../seed_assets/europa-league-2026-27-teams.csv (verified
# against the official UEFA 2026/27 list).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CSV="$SCRIPT_DIR/../seed_assets/europa-league-2026-27-teams.csv"
SOURCE_DIR="${1:-}"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
  echo "Usage: $0 <path-to-36-png-folder>" >&2
  exit 1
fi

if [[ ! -f "$CSV" ]]; then
  echo "CSV not found at $CSV" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

count=0
while IFS=, read -r filename official_name common_name country slug; do
  [[ "$filename" == "filename" ]] && continue # header row
  src="$SOURCE_DIR/$filename"
  if [[ ! -f "$src" ]]; then
    echo "MISSING: $filename (slug=$slug, expected at $src)" >&2
    exit 1
  fi
  cp "$src" "$STAGING/$slug.png"
  count=$((count + 1))
done < "$CSV"

echo "Staged $count crests as <slug>.png; uploading to ss:///team-logos ..."

for f in "$STAGING"/*.png; do
  slug="$(basename "$f")"
  supabase storage cp "$f" "ss:///team-logos/$slug" \
    --linked \
    --content-type image/png
done

echo "Done — $count crests uploaded to the team-logos bucket."
echo "Verify: supabase storage ls ss:///team-logos --linked"
