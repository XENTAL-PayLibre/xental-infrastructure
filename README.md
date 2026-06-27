# Xental Infrastructure

Single source of truth for **running** the Xental platform. It composes the
images built by the application repos (`xental-backend`, `paylibre`, and future
frontends) into a complete, TLS-terminated stack and deploys it to AWS EC2 via
GitHub Actions.

- **Runtime:** Docker Compose on EC2 (one host per environment)
- **Registry:** GHCR (`ghcr.io/xental-paylibre/*`)
- **Ingress/TLS:** Traefik + Let's Encrypt
- **Environments:** `staging` (branch `staging`) and `production` (branch `main`)
- **Deploy transport:** GitHub OIDC → AWS SSM Run Command (no SSH, no static keys)
- **Provisioning:** Terraform (`terraform/`)

```
app repo push ─▶ build image ─▶ push GHCR ─▶ repository_dispatch
                                                   │
                                                   ▼
                          infra: pin version → OIDC → SSM → host deploy.sh
                                                   │
                                                   ▼
                       EC2 host: render env (+SSM secrets) → compose pull/up
                                                   │
                                          health-check → auto-rollback on failure
```

## Layout

```
compose/      base + per-env docker-compose files
traefik/      static config + dynamic middlewares (TLS, security headers)
env/          layered, non-secret env templates (.example) — see docs/ENVIRONMENT.md
versions/     pinned image tags per env (auto-managed; the rollback ledger)
scripts/      render-env, deploy (health-check + auto-rollback), rollback, bootstrap, healthcheck
terraform/    AWS: OIDC deploy role, EC2 hosts, security group, SSM secret skeletons
.github/      deploy-staging, deploy-prod (gated), rollback, reusable _deploy
docs/         ENVIRONMENT.md, ROLLBACK.md
```

## How a release flows

1. You merge to `staging` (or `main`) in an app repo.
2. That repo's `build.yml` builds the Docker image and pushes
   `:sha-<commit>` + `:staging`/`:prod` to GHCR.
3. It fires `repository_dispatch` → this repo's deploy workflow.
4. The workflow pins `versions/<env>.env` to `:sha-<commit>`, commits it, then
   assumes the AWS role via OIDC and runs `deploy.sh` on the host over SSM.
5. `deploy.sh` renders the runtime env (config + SSM secrets), pulls, brings the
   stack up, and health-checks — **auto-rolling back if anything is unhealthy**.

Production additionally waits on the `production` GitHub Environment's required
reviewers before step 4 runs.

## One-time setup

### 1. AWS (Terraform)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set region etc.
terraform init && terraform apply
```
Note the outputs: `github_deploy_role_arn`, `host_public_ips`, `instance_ids`.
> If the account has no GitHub OIDC provider yet, create it once (audience
> `sts.amazonaws.com`) or switch the data source in `iam.tf` to a resource.

### 2. Secrets (SSM)
Set the real values Terraform created as placeholders:
```bash
for k in POSTGRES_PASSWORD XENTAL_DB_PASSWORD PAYLIBRE_DB_PASSWORD REDIS_PASSWORD GHCR_TOKEN GITHUB_TOKEN; do
  aws ssm put-parameter --overwrite --type SecureString --name /xental/staging/$k --value '...'
done
aws ssm put-parameter --overwrite --type String --name /xental/staging/GHCR_USER --value 'xental-ci'
# repeat for /xental/production/* (no TRAEFIK_DASHBOARD_AUTH in prod)
```
- `GITHUB_TOKEN`: fine-grained, **read-only** contents on this repo (host clones/pulls).
- `GHCR_TOKEN`: read-only `packages` (host pulls images). `GHCR_USER`: any user/bot.
- `TRAEFIK_DASHBOARD_AUTH` (staging only): `htpasswd -nbB admin '<pw>'` output.

### 3. GitHub repo configuration (this repo)
- **Secret** `AWS_DEPLOY_ROLE_ARN` = the Terraform `github_deploy_role_arn` output.
- **Variable** `AWS_REGION` = your region (e.g. `eu-west-1`).
- **Environments**: create `staging` and `production`; add **required reviewers**
  to `production`.
- Create the `staging` branch (this repo) so staging deploys have a ref.

### 4. App repos (`xental-backend`, `paylibre`)
- **Secret** `INFRA_DISPATCH_TOKEN` = fine-grained PAT (or GitHub App token) with
  permission to dispatch this repo. (`build.yml` is already committed.)

### 5. DNS (once the domain is purchased)
Point A records at the Elastic IPs from Terraform, then update `DOMAIN` and the
`*_HOST` values in `env/staging.env.example` / `env/production.env.example`. Traefik
issues certificates automatically on the next deploy.

## Local validation

```bash
# Render an env offline (no secrets) and validate the compose files parse:
SKIP_SSM=1 scripts/render-env.sh production
docker compose -f compose/docker-compose.yml -f compose/docker-compose.production.yml \
  --env-file env/production.runtime.env config -q
```

See **docs/ENVIRONMENT.md** for the config/secrets model and **docs/ROLLBACK.md**
for rollback procedures.
