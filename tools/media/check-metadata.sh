#!/usr/bin/env bash

set -euo pipefail

for command_name in exiftool file jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to check image metadata" >&2
    exit 2
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

failed=0
images_checked=0

while IFS= read -r -d '' path; do
  mime_type="$(file --brief --mime-type -- "$path")"
  [[ "$mime_type" == image/* ]] || continue

  images_checked=$((images_checked + 1))
  if ! metadata_json="$(
    exiftool -G0:1 -a \
      -gps:all -exif:all -xmp:all -iptc:all \
      -j -- "$path"
  )"; then
    echo "Could not inspect metadata in $path" >&2
    failed=1
    continue
  fi

  metadata_keys="$(
    printf '%s\n' "$metadata_json" \
      | jq --raw-output '.[0] | to_entries[] | select(.key != "SourceFile") | .key'
  )"
  [[ -n "$metadata_keys" ]] || continue

  echo "Metadata found in $path:" >&2
  while IFS= read -r metadata_key; do
    printf '  %s\n' "$metadata_key" >&2
  done <<< "$metadata_keys"
  failed=1
done < <(find app/assets/images public -type f -print0)

if (( failed != 0 )); then
  exit 1
fi

printf 'Metadata check passed: %d image(s) inspected.\n' "$images_checked"
