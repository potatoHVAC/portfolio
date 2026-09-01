#!/usr/bin/env bash

set -euo pipefail

for command_name in exiftool ffprobe file jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to check media metadata" >&2
    exit 2
  fi
done

if (( $# == 0 )); then
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cd "$repo_root"
  targets=(app/assets/images public)
else
  targets=("$@")
fi

for target in "${targets[@]}"; do
  if [[ ! -e "$target" ]]; then
    echo "Metadata target does not exist: $target" >&2
    exit 2
  fi
done

failed=0
images_checked=0
videos_checked=0
captions_checked=0

check_image() {
  local path="$1"
  local metadata_json metadata_keys
  images_checked=$((images_checked + 1))
  if ! metadata_json="$(
    exiftool -G0:1 -a \
      -gps:all -exif:all -xmp:all -iptc:all \
      -j -- "$path"
  )"; then
    echo "Could not inspect metadata in $path" >&2
    failed=1
    return
  fi

  metadata_keys="$(
    printf '%s\n' "$metadata_json" \
      | jq --raw-output '.[0] | to_entries[] | select(.key != "SourceFile") | .key'
  )"
  if [[ -z "$metadata_keys" ]]; then
    return 0
  fi

  echo "Metadata found in $path:" >&2
  while IFS= read -r metadata_key; do
    printf '  %s\n' "$metadata_key" >&2
  done <<< "$metadata_keys"
  failed=1
}

check_video() {
  local path="$1"
  local probe forbidden_keys
  videos_checked=$((videos_checked + 1))
  if ! probe="$(
    ffprobe -v error -print_format json -show_format -show_streams -show_chapters -- "$path"
  )"; then
    echo "Could not inspect video in $path" >&2
    failed=1
    return
  fi
  if [[ "$(jq '.chapters | length' <<< "$probe")" != 0 ]]; then
    echo "Video chapters found in $path" >&2
    failed=1
  fi
  if ! jq --exit-status '
    ([.streams[] | select(.codec_type == "video")] | length == 1)
    and ([.streams[] | select(.codec_type == "audio")] | length <= 1)
    and ([.streams[] | select(.codec_type != "video" and .codec_type != "audio")] | length == 0)
    and ([.streams[] | select(.codec_type == "video")][0]
      | .codec_name == "h264" and .pix_fmt == "yuv420p")
    and (([.streams[] | select(.codec_type == "audio")] | length == 0)
      or ([.streams[] | select(.codec_type == "audio")][0]
        | .codec_name == "aac" and .profile == "LC" and .channels == 2))
  ' >/dev/null <<< "$probe"; then
    echo "Unexpected video streams in $path" >&2
    failed=1
  fi
  forbidden_keys="$(
    jq --raw-output '
      [.format, .streams[], .chapters[]?]
      | map(.tags // {} | keys[])
      | .[]
      | select(. != "compatible_brands")
      | select(. != "encoder")
      | select(. != "handler_name")
      | select(. != "language")
      | select(. != "major_brand")
      | select(. != "minor_version")
      | select(. != "vendor_id")
    ' <<< "$probe"
  )"
  if [[ -n "$forbidden_keys" ]]; then
    echo "Forbidden video metadata found in $path:" >&2
    while IFS= read -r metadata_key; do
      printf '  %s\n' "$metadata_key" >&2
    done <<< "$forbidden_keys"
    failed=1
  fi
}

check_caption() {
  local path="$1"
  captions_checked=$((captions_checked + 1))
  if ! LC_ALL=C head -c 7 -- "$path" | grep -q '^WEBVTT'; then
    echo "Caption does not begin with WEBVTT: $path" >&2
    failed=1
  fi
}

while IFS= read -r -d '' path; do
  mime_type="$(file --brief --mime-type -- "$path")"
  extension="${path##*.}"
  extension="${extension,,}"
  case "$extension" in
    avif|jpeg|jpg|png|tif|tiff|webp)
      if [[ "$mime_type" != image/* ]]; then
        echo "Image extension does not match content: $path ($mime_type)" >&2
        failed=1
      else
        check_image "$path"
      fi
      ;;
    m4v|mov|mp4)
      if [[ "$mime_type" != video/* && "$mime_type" != application/mp4 ]]; then
        echo "Video extension does not match content: $path ($mime_type)" >&2
        failed=1
      else
        check_video "$path"
      fi
      ;;
    vtt)
      if [[ "$mime_type" != text/* ]]; then
        echo "Caption extension does not match content: $path ($mime_type)" >&2
        failed=1
      else
        check_caption "$path"
      fi
      ;;
  esac
done < <(find "${targets[@]}" -type f -print0)

if (( failed != 0 )); then
  exit 1
fi

printf 'Metadata check passed: %d image(s), %d video(s), and %d caption(s) inspected.\n' \
  "$images_checked" "$videos_checked" "$captions_checked"
