# Deployment runbook

Step-by-step to provision the hosts, get the IPs for DNS, deploy the services,
and confirm that a push to either app repo triggers a deployment.

Follow the phases in order. **GitHub config (Phase 3) must exist before you push
to trigger (Phase 4)**, or the deploy run fails with "SSH_HOST not set".

---

## Prerequisites (on your machine)

- `aws` CLI authenticated (`aws sts get-caller-identity` works)
- `terraform` installed (`winget install Hashicorp.Terraform` or download)
- An SSH keypair for deploys:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/xental_deploy -C xental-deploy -N ""
cat ~/.ssh/xental_deploy.pub      # goes into Terraform (Phase 1)
```

---

## Phase 1 — Provision AWS and get the host IPs

```bash
cd xental-infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_region and paste ssh_public_key (the .pub above)
terraform init
terraform apply        # review, type yes  (creates 2 EC2 + EIPs + SG — billable)

terraform output host_public_ips
# => { "staging" = "A.B.C.D", "production" = "E.F.G.H" }
```

✅ **Those two IPs are what you put in DNS.** They are Elastic IPs, so they
survive instance restarts. Give the hosts ~2 minutes to finish installing Docker
(cloud-init).

Verify SSH + Docker are ready:

```bash
ssh -i ~/.ssh/xental_deploy ubuntu@A.B.C.D 'docker compose version'
```

---

## Phase 2 — DNS records (use the IPs from Phase 1)

Create **A records** (host → IP). Hostnames the stack expects (from
`env/*.env.example`):

| Record | → IP |
|--------|------|
| `xental-api.staging.<domain>` | staging IP |
| `paylibre-api.staging.<domain>` | staging IP |
| `traefik.staging.<domain>` | staging IP (dashboard) |
| `api.xental.<domain>` | production IP |
| `api.paylibre.<domain>` | production IP |

Then set the real domain in the repo and commit (replaces the `example.com`
placeholders), on both `main` and `staging`:

- `env/staging.env.example`: `DOMAIN`, `XENTAL_API_HOST`, `PAYLIBRE_API_HOST`
- `env/production.env.example`: same

> No domain yet? Skip this phase for now — you can still deploy and smoke-test via
> the host in Phase 5. TLS just won't issue until DNS exists.

---

## Phase 3 — Configure GitHub (one-time)

### A. Infra repo → `xental-infrastructure` → Settings → Environments
Create `staging` and `production` (add **required reviewers** on production).
For **each** environment:

**Variables**
| Name | Value |
|------|-------|
| `SSH_HOST` | that env's IP from Phase 1 |
| `SSH_USER` | `ubuntu` |

**Secrets**
| Name | Value |
|------|-------|
| `SSH_PRIVATE_KEY` | contents of `~/.ssh/xental_deploy` (private key) |
| `POSTGRES_PASSWORD` | strong random |
| `XENTAL_DB_PASSWORD` | strong random |
| `PAYLIBRE_DB_PASSWORD` | strong random |
| `REDIS_PASSWORD` | strong random |
| `GHCR_USER` | GitHub username/bot with package read |
| `GHCR_TOKEN` | PAT with `read:packages` |
| `TRAEFIK_DASHBOARD_AUTH` | **staging only**: `htpasswd -nbB admin 'pw'` output |

```bash
openssl rand -base64 24          # generate a strong value
htpasswd -nbB admin 'somePassword'   # staging dashboard auth
```

### B. Each app repo (`xental-backend`, `paylibre`) → Settings → Secrets → Actions
| Name | Value |
|------|-------|
| `INFRA_DISPATCH_TOKEN` | fine-grained PAT with **Contents: R/W + Actions: R/W** on `xental-infrastructure` |

This token is what makes a push fan out to the infra deploy. Without it the
build runs but the deploy is not triggered.

---

## Phase 4 — Trigger a deploy by pushing

Triggers on push to **`staging`** or **`main`** (not `dev`). Trivial change:

```bash
cd xental-backend
git checkout staging
git commit --allow-empty -m "ci: trigger staging deploy"
git push origin staging
```

Watch the chain:
1. **xental-backend → Actions → "Build & publish image"** → pushes
   `ghcr.io/xental-paylibre/xental-backend:staging` + `:sha-…`, then dispatches.
2. **xental-infrastructure → Actions → "Deploy staging"** starts automatically →
   pins the SHA, renders env, rsyncs over SSH, runs `deploy.sh`, ends on the
   health check.

✅ Run #2 starting on its own = a push triggers the deployment. Repeat from
`PayLibre` to prove the other repo triggers it too.

Production: push to `main` (or Actions → "Deploy production" → Run). It pauses
for reviewer approval, then deploys.

---

## Phase 5 — Verify the services are up

On the host:

```bash
ssh -i ~/.ssh/xental_deploy ubuntu@A.B.C.D
cd /opt/xental-infrastructure
docker compose -f compose/docker-compose.yml -f compose/docker-compose.staging.yml \
  --env-file env/staging.runtime.env ps
docker run --rm --network xental-internal curlimages/curl -fsS http://xental-api:8080/health
docker run --rm --network xental-internal curlimages/curl -fsS http://paylibre-api:8080/health
```

Once DNS + TLS are live: `curl https://xental-api.staging.<domain>/health`.

---

## Gotchas

- **Order:** do Phase 3 before Phase 4, or the deploy fails on a missing
  `SSH_HOST`/secret.
- **GHCR visibility:** the first image push creates a *private* package owned by
  your user. Either set `GHCR_TOKEN` to a token that can read it, or grant the
  org/repo read access in the GHCR package settings — otherwise the host's
  `docker pull` returns 401.
- **Branch scope:** only `staging` and `main` pushes deploy; `dev` does not.

See [README.md](README.md) for architecture, [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)
for the config/secrets model, and [docs/ROLLBACK.md](docs/ROLLBACK.md) for rollbacks.
