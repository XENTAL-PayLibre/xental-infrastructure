# Xental Infrastructure

Single source of truth for **running** the Xental platform. It composes the
images built by the application repos (`xental-backend`, `paylibre`, and future
frontends) into a complete, TLS-terminated stack and deploys it to AWS EC2 via
GitHub Actions.

- **Runtime:** Docker Compose on EC2 (one host per environment)
- **Registry:** GHCR (`ghcr.io/xental-paylibre/*`)
- **Ingress/TLS:** Traefik + Let's Encrypt
- **Environments:** `staging` (branch `staging`) and `production` (branch `main`)
- **Secrets:** GitHub Environment secrets (rendered at deploy time)
- **Deploy transport:** SSH (rsync the stack + rendered env, then run deploy.sh)
- **Provisioning:** Terraform (`terraform/`)

```
app repo push ─▶ build image ─▶ push GHCR ─▶ repository_dispatch
                                                   │
                                                   ▼
       infra deploy job (GitHub Environment): pin version
         → render env from GitHub secrets → rsync over SSH → host deploy.sh
                                                   │
                                                   ▼
                  EC2 host: docker compose pull/up → health-check
                                                   │
                                         auto-rollback on failure
```

## Layout

```
compose/      base + per-env docker-compose files
traefik/      static config + dynamic middlewares (TLS, security headers)
env/          layered, non-secret env templates (.example) — see docs/ENVIRONMENT.md
versions/     pinned image tags per env (auto-managed; the rollback ledger)
scripts/      render-env, deploy (health-check + auto-rollback), rollback, bootstrap, healthcheck
terraform/    AWS: EC2 hosts, SSH key, security group, host role
.github/      deploy-staging, deploy-prod (gated), rollback, reusable _deploy
docs/         ENVIRONMENT.md, ROLLBACK.md
```

## How a release flows

1. You merge to `staging` (or `main`) in an app repo.
2. That repo's `build.yml` builds the Docker image and pushes
   `:sha-<commit>` + `:staging`/`:prod` to GHCR, then fires `repository_dispatch`.
3. This repo's deploy job (scoped to the matching GitHub Environment) pins
   `versions/<env>.env` to `:sha-<commit>`, **renders the runtime env from
   GitHub secrets**, rsyncs the stack + env to the host over SSH, and runs
   `deploy.sh`.
4. `deploy.sh` pulls, brings the stack up, and health-checks — **auto-rolling
   back to the last-known-good release if anything is unhealthy**.

Production additionally waits on the `production` Environment's required
reviewers before step 3 runs.

---

# First-time bring-up (detailed)

Do this once. ~30–45 minutes. Commands assume a bash shell with `aws`,
`terraform`, `git`, and `ssh-keygen` installed and `aws` already authenticated
to your account.

## Step 0 — Prerequisites checklist
- An AWS account + a region (e.g. `eu-west-1`).
- The two app repos building images: `build.yml` is already committed to
  `xental-backend` and `paylibre`.
- A GHCR pull token (made in Step 4).
- (Optional, for TLS) a registered domain. The stack runs without one; only
  Let's Encrypt certificates need DNS — see Step 8.

## Step 1 — Create the deploy SSH key
```bash
ssh-keygen -t ed25519 -f ~/.ssh/xental_deploy -C "xental-deploy" -N ""
# Public half → Terraform.  Private half → GitHub secret (Step 5).
cat ~/.ssh/xental_deploy.pub
```

## Step 2 — Provision AWS with Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_region and paste ssh_public_key (the .pub above).
terraform init
terraform apply
```
Record the outputs:
```bash
terraform output host_public_ips   # { staging = "x.x.x.x", production = "y.y.y.y" }
terraform output ssh_user          # ubuntu
```
The hosts auto-install Docker on boot (cloud-init); give them ~2 minutes.

## Step 3 — Verify SSH reaches each host
```bash
ssh -i ~/.ssh/xental_deploy ubuntu@<staging-ip> 'docker --version && docker compose version'
```
If that prints versions, the host is ready. (If "permission denied", the key in
Terraform didn't match — re-check `ssh_public_key`.)

## Step 4 — Create a GHCR pull token
A machine token the hosts use to pull private images:
- GitHub → Settings → Developer settings → **Personal access tokens (classic)** →
  generate one with **`read:packages`** scope. Note the token and the username.
- (Or use a fine-grained token / bot account with package read access.)

## Step 5 — Configure GitHub Environments on `xental-infrastructure`
Repo → Settings → Environments → create **`staging`** and **`production`**.
On **production**, add **Required reviewers** (your approval gate).

For **each** environment add:

**Variables** (Settings → Environments → <env> → Environment variables)
| Name | Value |
|------|-------|
| `SSH_HOST` | that env's Elastic IP from Step 2 |
| `SSH_USER` | `ubuntu` |

**Secrets** (Settings → Environments → <env> → Environment secrets)
| Name | Value |
|------|-------|
| `SSH_PRIVATE_KEY` | contents of `~/.ssh/xental_deploy` (the private key) |
| `POSTGRES_PASSWORD` | strong random |
| `XENTAL_DB_PASSWORD` | strong random |
| `PAYLIBRE_DB_PASSWORD` | strong random |
| `REDIS_PASSWORD` | strong random |
| `GHCR_USER` | the GHCR username/bot from Step 4 |
| `GHCR_TOKEN` | the `read:packages` token from Step 4 |
| `TRAEFIK_DASHBOARD_AUTH` | **staging only**: output of `htpasswd -nbB admin '<pw>'` |

> Tip: generate a password with `openssl rand -base64 24`.

## Step 6 — Configure the app repos
In **each** of `xental-backend` and `paylibre` (Settings → Secrets and variables
→ Actions → New repository secret):
| Name | Value |
|------|-------|
| `INFRA_DISPATCH_TOKEN` | a fine-grained PAT with **Contents: read/write** and **Actions: read/write** on `xental-infrastructure` (lets the build notify infra) |

## Step 7 — First deploy
Two ways; either works.

**A. Manual (recommended for the very first run):**
1. Make sure images exist in GHCR. In each app repo, the `build.yml` already ran
   on the last push to `staging`/`main`; check Actions → it produced
   `ghcr.io/xental-paylibre/<svc>:staging`. If not, push any commit to `staging`.
2. In `xental-infrastructure` → Actions → **Deploy staging** → **Run workflow**
   (leave `service`/`sha` empty to deploy whatever the pins point at).
3. Watch the run: it renders the env, rsyncs to the host, and runs `deploy.sh`,
   which ends with the health check.

**B. Automatic:** push a commit to `staging` in an app repo. Its build pushes a
new image and dispatches `deploy-staging` here, which deploys that exact SHA.

## Step 8 — Smoke test
Until DNS exists, test on the host directly:
```bash
ssh -i ~/.ssh/xental_deploy ubuntu@<staging-ip>
cd /opt/xental-infrastructure
docker compose -f compose/docker-compose.yml -f compose/docker-compose.staging.yml \
  --env-file env/staging.runtime.env ps
# health over the internal network:
docker run --rm --network xental-internal curlimages/curl -fsS http://xental-api:8080/health
docker run --rm --network xental-internal curlimages/curl -fsS http://paylibre-api:8080/health
```

## Step 9 — Production
Once staging is green, repeat Step 7 for **Deploy production** (or push to `main`
in an app repo). The run pauses for your **required-reviewer approval**, then
deploys to the production host.

## Step 10 — DNS + TLS (when the domain is purchased)
1. Create A records pointing the hostnames at the Elastic IPs:
   `xental-api.staging.<domain>`, `paylibre-api.staging.<domain>`, and the prod
   equivalents (see `env/*.env.example`).
2. Update `DOMAIN` and the `*_HOST` values in `env/staging.env.example` /
   `env/production.env.example` and commit.
3. Redeploy. Traefik requests and renews Let's Encrypt certificates automatically;
   HTTPS is then live and HTTP is redirected to it.

---

## Local validation (offline, no secrets)
```bash
SKIP_SECRETS=1 scripts/render-env.sh staging
docker compose -f compose/docker-compose.yml -f compose/docker-compose.staging.yml \
  --env-file env/staging.runtime.env config -q
```

## Rolling back
See **docs/ROLLBACK.md** — automatic on failed health checks, plus the
**Rollback** workflow and host-side `scripts/rollback.sh`.

## Security note (SSH)
Port 22 is open with **key-only** auth (passwords disabled on Ubuntu by default;
the key lives only in GitHub secrets). To harden: narrow `ssh_ingress_cidr` in
Terraform to a known network and deploy from a self-hosted runner there, and/or
add fail2ban. Break-glass access is also available via AWS SSM Session Manager
(the host role includes it) without opening anything further.
