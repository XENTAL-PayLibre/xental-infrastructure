#!/usr/bin/env bash
# Deploy (or roll back) the platform for one environment. Runs ON the target
# EC2 host. The GitHub Actions deploy job rsyncs the repo files + the rendered
# runtime env here over SSH, then invokes this script.
#
# The runtime env file (env/<env>.runtime.env) already contains everything —
# non-secret config, pinned image tags, and the secrets sourced from GitHub.
# The last-known-good copy is kept as env/<env>.runtime.env.deployed and is the
# automatic rollback target.
#
# Flow:
#   1. docker login GHCR (creds read from the runtime env)
#   2. pull + up -d with the incoming env
#   3. health-check; if it fails, AUTO-ROLLBACK to the last-known-good env
#
# Usage:  scripts/deploy.sh <staging|production>
set -euo pipefail

ENV_NAME="${1:?usage: deploy.sh <staging|production>}"
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

[[ -f "$INCOMING" ]] || { echo "ERROR: $INCOMING not present (was it shipped?)" >&2; exit 1; }

# Include the monitoring overlay (Alloy: metrics + logs) only when the runtime
# env points at a monitoring host.
MON_OVERLAY=()
if grep -qE '^MONITORING_HOST=.+' "$INCOMING"; then
  MON_OVERLAY=(-f compose/docker-compose.monitoring.yml)
fi

# Database backups run in every environment.
BACKUP_OVERLAY=(-f compose/docker-compose.backup.yml)

# Include the CrowdSec runtime-security overlay only when a bouncer key is set.
SEC_OVERLAY=()
if grep -qE '^CROWDSEC_BOUNCER_KEY=.+' "$INCOMING"; then
  SEC_OVERLAY=(-f compose/docker-compose.security.yml)
fi

deploy_with() {
  local ef="$1"
  # --project-directory pins relative bind-mount paths (./scripts, ./traefik)
  # to the repo root rather than the compose/ subdir where the files live.
  docker compose --project-directory "$REPO_DIR" -f "$BASE" -f "$OVERRIDE" "${MON_OVERLAY[@]}" "${BACKUP_OVERLAY[@]}" "${SEC_OVERLAY[@]}" --env-file "$ef" pull
  docker compose --project-directory "$REPO_DIR" -f "$BASE" -f "$OVERRIDE" "${MON_OVERLAY[@]}" "${BACKUP_OVERLAY[@]}" "${SEC_OVERLAY[@]}" --env-file "$ef" up -d --remove-orphans
}

ghcr_login_from() {
  local ef="$1" u t
  u="$(sed -n 's/^GHCR_USER=//p'  "$ef" | head -n1)"
  t="$(sed -n 's/^GHCR_TOKEN=//p' "$ef" | head -n1)"
  [[ -n "$t" ]] && echo "$t" | docker login ghcr.io -u "${u:-x-access-token}" --password-stdin || true
}

echo "==> Deploying ${ENV_NAME}"
ghcr_login_from "$INCOMING"
deploy_with "$INCOMING"

if scripts/healthcheck.sh; then
  echo "==> ${ENV_NAME} healthy; deploy succeeded."
  [[ -f "$DEPLOYED" ]] && cp "$DEPLOYED" "${DEPLOYED}.prev"  # keep one step of history
  cp "$INCOMING" "$DEPLOYED"          # mark this env as last-known-good
  docker image prune -f >/dev/null 2>&1 || true
else
  echo "!!! ${ENV_NAME} health checks FAILED." >&2
  if [[ -f "$DEPLOYED" ]]; then
    echo "    Auto-rolling back to the last-known-good release." >&2
    ghcr_login_from "$DEPLOYED"
    deploy_with "$DEPLOYED"
    if scripts/healthcheck.sh; then
      echo "==> Rollback restored the previous healthy version." >&2
    else
      echo "XXX Rollback ALSO failed — manual intervention required." >&2
    fi
  else
    echo "    No previous release to roll back to (first deploy)." >&2
  fi
  exit 1
fi
