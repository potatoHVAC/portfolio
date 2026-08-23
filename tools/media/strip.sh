#!/usr/bin/env bash

set -euo pipefail

if (( $# == 0 )); then
  echo "Usage: tools/media/strip.sh <image> [<image> ...]" >&2
  exit 2
fi

if ! command -v exiftool >/dev/null 2>&1; then
  echo "exiftool is required to strip image metadata" >&2
  exit 2
fi

exiftool -all= --icc_profile:all -overwrite_original -- "$@"
