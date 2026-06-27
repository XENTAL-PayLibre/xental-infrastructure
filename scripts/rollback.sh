#!/usr/bin/env bash
# Host-side manual rollback for one environment. Runs ON the EC2 host against
# the runtime env files shipped there. Two modes:
#
#   scripts/rollback.sh <env>            # redeploy the PREVIOUS known-good release
#                                        # (env/<env>.runtime.env.deployed.prev)
#   scripts/rollback.sh <env> <sha>      # pin BOTH apps to sha-<sha> and redeploy
#
# For a git-tracked, audited rollback prefer the "Rollback" GitHub Actions
# workflow, which reverts the version pins and re-ships. This script is the
# break-glass path when you are already on the host (via SSH).
set -euo pipefail

ENV_NAME="${1:?usage: rollback.sh <staging|production> [sha]}"
TARGET_SHA="${2:-}"
REPO_DIR="${REPO_DIR:-/opt/xental-infrastructure}"
cd "$REPO_DIR"

case "$ENV_NAME" in
  staging)    OVERRIDE=compose/docker-compose.staging.yml ;;
  production) OVERRIDE=compose/docker-compose.production.yml ;;
  *) echo "unknown environment: $ENV_NAME" >&2; exit 2 ;;
esac

BASE=compose/docker-compose.yml
INCOMING="env/${ENV_NAME}.runtime.env"
DEPLOYED="env/${ENV_NAME}.runtime.env.deployed"

deploy_with() {
  local ef="$1"
  local u t
  u="$(sed -n 's/^GHCR_USER=//p'  "$ef" | head -n1)"
  t="$(sed -n 's/^GHCR_TOKEN=//p' "$ef" | head -n1)"
  [[ -n "$t" ]] && echo "$t" | docker login ghcr.io -u "${u:-x-access-token}" --password-stdin || true
  docker compose --project-directory "$REPO_DIR" -f "$BASE" -f "$OVERRIDE" --env-file "$ef" pull
  docker compose --project-directory "$REPO_DIR" -f "$BASE" -f "$OVERRIDE" --env-file "$ef" up -d --remove-orphans
}

if [[ -n "$TARGET_SHA" ]]; then
  echo "==> Pinning ${ENV_NAME} apps to sha-${TARGET_SHA} and redeploying"
  src="${DEPLOYED:-$INCOMING}"; [[ -f "$src" ]] || src="$INCOMING"
  cp "$src" "$INCOMING"
  sed -i -E "s#^(XENTAL_API_IMAGE=ghcr.io/[^:]+):.*#\1:sha-${TARGET_SHA}#"   "$INCOMING"
  sed -i -E "s#^(PAYLIBRE_API_IMAGE=ghcr.io/[^:]+):.*#\1:sha-${TARGET_SHA}#" "$INCOMING"
  deploy_with "$INCOMING"
else
  echo "==> Rolling ${ENV_NAME} back to the previous known-good release"
  [[ -f "${DEPLOYED}.prev" ]] || { echo "no previous release recorded on host" >&2; exit 1; }
  deploy_with "${DEPLOYED}.prev"
  cp "${DEPLOYED}.prev" "$DEPLOYED"
fi

scripts/healthcheck.sh
