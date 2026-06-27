#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu EC2 host. Idempotent — safe to re-run.
# Installs Docker + the compose plugin, creates the deploy directory, and adds
# the login user to the docker group so the SSH deploy can run docker without
# sudo. The infra files + rendered env are rsynced in by the deploy workflow;
# nothing is cloned here and no secrets are stored on disk.
#
# Run as root on the instance (Terraform user_data does this automatically):
#   DEPLOY_USER=ubuntu bash bootstrap-host.sh
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
REPO_DIR="/opt/xental-infrastructure"

echo "==> Installing Docker + compose plugin"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "==> Granting ${DEPLOY_USER} docker access + preparing ${REPO_DIR}"
usermod -aG docker "$DEPLOY_USER" || true
mkdir -p "$REPO_DIR/env"
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$REPO_DIR"

echo "==> Bootstrap complete. The deploy workflow will rsync files here and run scripts/deploy.sh."
