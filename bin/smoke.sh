#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 IMAGE" >&2
  exit 2
fi

image=$1
container_name="portfolio-smoke-$$"
started=false
ready=false

cleanup() {
  status=$?
  trap - EXIT

  if [[ $started == true ]]; then
    if (( status != 0 )); then
      docker logs "$container_name" >&2 || true
    fi
    docker rm --force "$container_name" >/dev/null 2>&1 || true
  fi

  exit "$status"
}
trap cleanup EXIT

secret_key_base=$(openssl rand -hex 64)
docker run --detach \
  --name "$container_name" \
  --publish 127.0.0.1:8080:8080 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --env SECRET_KEY_BASE="$secret_key_base" \
  "$image" >/dev/null
started=true
unset secret_key_base

for _ in {1..60}; do
  if curl --fail --silent --max-time 2 \
    http://127.0.0.1:8080/up >/dev/null; then
    ready=true
    break
  fi

  if [[ $(docker inspect --format '{{.State.Running}}' "$container_name") != true ]]; then
    echo "container stopped before becoming ready" >&2
    exit 1
  fi

  sleep 1
done

if [[ $ready != true ]]; then
  echo "container did not become ready within 60 seconds" >&2
  exit 1
fi

curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:8080/ | grep --fixed-strings --quiet "speerd things"

echo "Smoke test passed: $image"
