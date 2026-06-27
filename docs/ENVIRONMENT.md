# Environment & secrets management

A single, consistent model governs configuration for **every** service —
the application backends (xental, paylibre), future frontends, and the
infrastructure stack itself (Traefik, Postgres, Redis).

## Principles

1. **Non-secret config is in git; secrets live in GitHub Environment secrets.**
   No secret value is ever committed.
2. **One namespaced variable space.** Every variable is `<SERVICE>_<KEY>` or a
   clearly shared key (`DOMAIN`, `ACME_EMAIL`, `ENVIRONMENT`).
3. **Layered precedence**, rendered into one runtime file per environment.
4. **Image versions are pinned in git** (`versions/<env>.env`) so the deployed
   state is auditable and revertible.

## The layers (low → high precedence)

| # | Source | In git? | Contains |
|---|--------|---------|----------|
| 1 | `env/common.env.example` | yes | shared non-secret defaults (image pins, db/user names) |
| 2 | `env/<env>.env.example` | yes | env-specific non-secret config (domains, hosts, ASPNETCORE_ENVIRONMENT) |
| 3 | `versions/<env>.env` | yes | pinned application image tags (auto-managed by CI) |
| 4 | **GitHub Environment secrets** | **no** | DB/Redis passwords, GHCR creds, dashboard auth |

The deploy job (scoped to the `staging` or `production` GitHub Environment)
exports the layer-4 secrets into the process environment and runs
`scripts/render-env.sh <env>`, which concatenates layers 1→4 into
`env/<env>.runtime.env` (chmod 600, git-ignored). Because `--env-file` keeps the
last definition of a duplicated key, later layers win.

```
common.env.example ─┐
<env>.env.example  ─┼─ render-env.sh ─▶ env/<env>.runtime.env ──(rsync over SSH)──▶ host ─▶ docker compose --env-file
versions/<env>.env ─┤        ▲
GitHub secrets ─────┘   injected as env vars by the deploy job
```

The runtime file is created on the GitHub runner, shipped to the host over SSH
(encrypted), and never committed.

## Where each value lives

In each GitHub Environment (`staging`, `production`) of **xental-infrastructure**:

**Environment secrets**
- `POSTGRES_PASSWORD`, `XENTAL_DB_PASSWORD`, `PAYLIBRE_DB_PASSWORD`, `REDIS_PASSWORD`
- `GHCR_USER`, `GHCR_TOKEN` (read-only `packages` token to pull images)
- `TRAEFIK_DASHBOARD_AUTH` (staging only; `htpasswd -nbB user 'pw'` output)
- `SSH_PRIVATE_KEY` (private half of the key in Terraform `ssh_public_key`)

**Environment variables** (non-secret)
- `SSH_HOST` (the env's Elastic IP), `SSH_USER` (`ubuntu`)

In each **app repo** (`xental-backend`, `paylibre`):
- `INFRA_DISPATCH_TOKEN` secret — PAT to trigger the infra deploy.

## Variable catalogue (in the rendered runtime file)

**Shared**: `ENVIRONMENT`, `DOMAIN`, `ACME_EMAIL`
**Image pins**: `TRAEFIK_IMAGE`, `POSTGRES_IMAGE`, `REDIS_IMAGE`, `XENTAL_API_IMAGE`, `PAYLIBRE_API_IMAGE`
**Routing**: `XENTAL_API_HOST`, `PAYLIBRE_API_HOST`
**App runtime**: `XENTAL_ASPNETCORE_ENVIRONMENT`, `PAYLIBRE_ASPNETCORE_ENVIRONMENT`
**Database** (names in git, passwords from secrets): `POSTGRES_USER`, `POSTGRES_PASSWORD`*, `XENTAL_DB_NAME/USER`, `XENTAL_DB_PASSWORD`*, `PAYLIBRE_DB_NAME/USER`, `PAYLIBRE_DB_PASSWORD`*
**Redis**: `REDIS_PASSWORD`*
**GHCR**: `GHCR_USER`, `GHCR_TOKEN`*
**Traefik (staging)**: `TRAEFIK_DASHBOARD_AUTH`*

`*` = secret (GitHub Environment secret). The apps' `ConnectionStrings__Default`
/ `ConnectionStrings__Redis` are composed in compose from these parts, so the
apps receive ordinary .NET config keys.

## Adding a new service (e.g. a frontend)

1. Add its non-secret keys to `env/common.env.example` / `env/<env>.env.example`.
2. Add any secrets as GitHub Environment secrets and to the `render-env.sh`
   `REQUIRED_SECRETS`/`OPTIONAL_SECRETS` list.
3. Add a service block + Traefik labels in `compose/docker-compose.yml`.
4. Add its image pin to `versions/<env>.env` (CI maintains it).

## Local validation (offline, no secrets)

```bash
SKIP_SECRETS=1 scripts/render-env.sh staging
docker compose -f compose/docker-compose.yml -f compose/docker-compose.staging.yml \
  --env-file env/staging.runtime.env config -q
```
