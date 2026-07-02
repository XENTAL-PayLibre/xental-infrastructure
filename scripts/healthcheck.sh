#!/usr/bin/env bash
# Verify every application service answers 200 on /health, reached over the
# private compose network via a throwaway curl container (so the app images
# need no curl of their own and nothing is published to the host).
#
# Exit 0 only if ALL services are healthy within the retry budget.
set -uo pipefail

NETWORK="${HEALTHCHECK_NETWORK:-xental-internal}"
CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.11.1}"
RETRIES="${HEALTHCHECK_RETRIES:-20}"
SLEEP="${HEALTHCHECK_SLEEP:-3}"

# service endpoints inside the network (name:port)
SERVICES=(
  "xental-api:8080"
  "paylibre-api:8080"
  "xental-frontend:3000"
)

check_one() {
  local target="$1" host="${1%%:*}" port="${1##*:}"
  for ((i = 1; i <= RETRIES; i++)); do
    if docker run --rm --network "$NETWORK" "$CURL_IMAGE" \
        -fsS --max-time 5 "http://${host}:${port}/health" >/dev/null 2>&1; then
      echo "  healthy: ${target} (attempt ${i})"
      return 0
    fi
    sleep "$SLEEP"
  done
  echo "  UNHEALTHY: ${target} after ${RETRIES} attempts" >&2
  return 1
}

rc=0
for s in "${SERVICES[@]}"; do
  check_one "$s" || rc=1
done
exit "$rc"
