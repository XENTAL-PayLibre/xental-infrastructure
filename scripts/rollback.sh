#!/usr/bin/env bash
# Manual rollback for one environment. Two modes:
#
#   scripts/rollback.sh <env>                 # roll back to the PREVIOUS pins
#                                             # (reverts the last versions change)
#   scripts/rollback.sh <env> <sha>          # roll back BOTH apps to sha-<sha>
#
# This rewrites versions/<env>.env, commits it (so git stays the source of
# truth), pushes, and redeploys via deploy.sh (which still health-checks).
set -euo pipefail

ENV_NAME="${1:?usage: rollback.sh <staging|production> [sha]}"
TARGET_SHA="${2:-}"
REPO_DIR="${REPO_DIR:-/opt/xental-infrastructure}"
cd "$REPO_DIR"

case "$ENV_NAME" in
  staging)    BRANCH=staging ;;
  production) BRANCH=main ;;
  *) echo "unknown environment: $ENV_NAME" >&2; exit 2 ;;
esac

VERSIONS="versions/${ENV_NAME}.env"
git fetch --prune origin
git checkout "$BRANCH"
git reset --hard "origin/${BRANCH}"

if [[ -n "$TARGET_SHA" ]]; then
  echo "==> Pinning ${ENV_NAME} apps to sha-${TARGET_SHA}"
  sed -i -E "s#(XENTAL_API_IMAGE=ghcr.io/[^:]+):.*#\1:sha-${TARGET_SHA}#"   "$VERSIONS"
  sed -i -E "s#(PAYLIBRE_API_IMAGE=ghcr.io/[^:]+):.*#\1:sha-${TARGET_SHA}#" "$VERSIONS"
else
  echo "==> Reverting ${ENV_NAME} to the previous pins"
  # Restore the version of the file from the commit before the latest change.
  prev_commit="$(git log -n 2 --format='%H' -- "$VERSIONS" | tail -n 1)"
  [[ -n "$prev_commit" ]] || { echo "no prior version to roll back to" >&2; exit 1; }
  git checkout "$prev_commit" -- "$VERSIONS"
fi

git add "$VERSIONS"
git -c commit.gpgsign=false commit -m "rollback(${ENV_NAME}): ${TARGET_SHA:-previous pins}"
git push origin "$BRANCH"

exec scripts/deploy.sh "$ENV_NAME"
