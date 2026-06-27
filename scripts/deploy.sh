#!/usr/bin/env bash
# Deploy (or roll back) the platform for one environment. Runs ON the target
# EC2 host, invoked by the GitHub Actions deploy workflow via AWS SSM.
#
# Flow:
#   1. snapshot the currently-deployed image pins  (rollback target)
#   2. fast-forward the infra repo to the env branch (new pins + compose)
#   3. render the runtime env (config + SSM secrets + pinned tags)
#   4. docker login GHCR, pull, up -d
#   5. health-check; if it fails, AUTO-ROLLBACK to the snapshot and exit 1
#
# Usage:  scripts/deploy.sh <staging|production>
set -euo pipefail

ENV_NAME="${1:?usage: deploy.sh <staging|production>}"
REPO_DIR="${REPO_DIR:-/opt/xental-infrastructure}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}"
export AWS_REGION
cd "$REPO_DIR"

case "$ENV_NAME" in
  staging)    BRANCH=staging; OVERRIDE=compose/docker-compose.staging.yml ;;
  production) BRANCH=main;     OVERRIDE=compose/docker-compose.production.yml ;;
  *) echo "unknown environment: $ENV_NAME" >&2; exit 2 ;;
esac

BASE=compose/docker-compose.yml
ENVFILE="env/${ENV_NAME}.runtime.env"
dc() { docker compose -f "$BASE" -f "$OVERRIDE" --env-file "$ENVFILE" "$@"; }

ssm() { aws ssm get-parameter --name "$1" --with-decryption \
          --region "$AWS_REGION" --query 'Parameter.Value' --output text 2>/dev/null || true; }

# 1. Snapshot current pins for rollback.
PREV_VERSIONS="$(mktemp)"
cp "versions/${ENV_NAME}.env" "$PREV_VERSIONS"

# 2. Sync infra repo to the env branch (credential helper reads token from SSM).
git fetch --prune origin
git checkout "$BRANCH"
git reset --hard "origin/${BRANCH}"

# 3. Render runtime env (non-secret layers + SSM secrets + pinned tags).
./scripts/render-env.sh "$ENV_NAME"

# 4. GHCR auth (creds from SSM, falling back to env).
GHCR_USER="${GHCR_USER:-$(ssm "/xental/${ENV_NAME}/GHCR_USER")}"
GHCR_TOKEN="${GHCR_TOKEN:-$(ssm "/xental/${ENV_NAME}/GHCR_TOKEN")}"
if [[ -n "$GHCR_TOKEN" ]]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-x-access-token}" --password-stdin
fi

rollout() { dc pull; dc up -d --remove-orphans; }

echo "==> Deploying ${ENV_NAME}"
rollout

if scripts/healthcheck.sh; then
  echo "==> ${ENV_NAME} healthy; deploy succeeded."
  docker image prune -f >/dev/null 2>&1 || true
  rm -f "$PREV_VERSIONS"
else
  echo "!!! ${ENV_NAME} health checks FAILED — auto-rolling back to previous pins." >&2
  cp "$PREV_VERSIONS" "versions/${ENV_NAME}.env"
  ./scripts/render-env.sh "$ENV_NAME"
  rollout
  rm -f "$PREV_VERSIONS"
  if scripts/healthcheck.sh; then
    echo "==> Rollback restored the previous healthy version." >&2
  else
    echo "XXX Rollback ALSO failed — manual intervention required." >&2
  fi
  exit 1
fi
