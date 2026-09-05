#!/usr/bin/env bash
# Uploads the 18 Saudi Pro League 2026/27 crest PNGs to the
# `team-logos` Supabase Storage bucket, renamed from their source
# filenames to `<slug>.png` — the exact path saudi_2026_27_crests.sql's
# crest_url values already point at.
#
# Prerequisites: migration 0026 (team-logos bucket) applied, and
# `supabase login` already run (or SUPABASE_ACCESS_TOKEN exported) —
# this needs an authenticated CLI session, which is why this is a
# standalone script rather than something run inline in a sandbox with
# no Supabase credentials.
#
# Usage:
#   ./upload_saudi_2026_27_crests.sh /path/to/18-png-folder
#
# The folder must contain the 18 files named exactly as the `filename`
# column in ../seed_assets/saudi-2026-27-teams.csv.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CSV="$SCRIPT_DIR/../seed_assets/saudi-2026-27-teams.csv"
SOURCE_DIR="${1:-}"

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
  echo "Usage: $0 <path-to-18-png-folder>" >&2
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
