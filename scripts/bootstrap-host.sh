#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu EC2 host. Idempotent — safe to re-run.
# Run as root (or via SSM, which runs as root) on the target instance:
#
#   ENV_NAME=staging GIT_REMOTE=https://github.com/XENTAL-PayLibre/xental-infrastructure.git \
#     bash bootstrap-host.sh
#
# Assumes the instance has an IAM role granting SSM + ssm:GetParameter on
# /xental/<env>/* (provisioned by Terraform). A read-only GitHub token is read
# from SSM by a git credential helper, so no token is ever written to disk.
set -euo pipefail

ENV_NAME="${ENV_NAME:?set ENV_NAME=staging|production}"
GIT_REMOTE="${GIT_REMOTE:?set GIT_REMOTE=<infra repo https url>}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
REPO_DIR="/opt/xental-infrastructure"
BRANCH="$([[ "$ENV_NAME" == production ]] && echo main || echo staging)"

echo "==> Installing Docker, compose plugin, git, awscli"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update
fi

echo "==> Configuring git credential helper (reads token from SSM at runtime)"
git config --system credential.helper \
  "!f() { echo username=x-access-token; echo \"password=\$(aws ssm get-parameter \
--name /xental/${ENV_NAME}/GITHUB_TOKEN --with-decryption --region ${AWS_REGION} \
--query Parameter.Value --output text)\"; }; f"

echo "==> Cloning/refreshing infra repo at ${REPO_DIR} (branch ${BRANCH})"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone --branch "$BRANCH" "$GIT_REMOTE" "$REPO_DIR"
else
  git -C "$REPO_DIR" fetch --prune origin
  git -C "$REPO_DIR" checkout "$BRANCH"
  git -C "$REPO_DIR" reset --hard "origin/${BRANCH}"
fi

# Persist the environment name so deploy.sh invoked by SSM knows its target.
echo "$ENV_NAME" > /opt/xental-environment
chmod 0644 /opt/xental-environment

echo "==> Bootstrap complete for ${ENV_NAME}. Run scripts/deploy.sh ${ENV_NAME} to deploy."
