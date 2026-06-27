# Environment & secrets management

A single, consistent model governs configuration for **every** service —
the application backends (xental, paylibre), future frontends, and the
infrastructure stack itself (Traefik, Postgres, Redis).

## Principles

1. **Non-secret config is in git; secrets never are.** Real secret values live
   only in **AWS SSM Parameter Store** (`SecureString`, KMS-encrypted).
2. **One namespaced variable space.** Every variable is `<SERVICE>_<KEY>` or a
   clearly shared key (`DOMAIN`, `ACME_EMAIL`, `ENVIRONMENT`). No collisions
   between services.
3. **Layered precedence**, rendered into one runtime file per environment.
4. **Image versions are pinned in git** (`versions/<env>.env`) so the deployed
   state is auditable and revertible.

## The layers (low → high precedence)

| # | Source | Tracked in git? | Contains |
|---|--------|-----------------|----------|
| 1 | `env/common.env.example` | yes | shared non-secret defaults (image pins, db/user names) |
| 2 | `env/<env>.env.example` | yes | env-specific non-secret config (domains, hosts, ASPNETCORE_ENVIRONMENT) |
| 3 | `versions/<env>.env` | yes | pinned application image tags (auto-managed by CI) |
| 4 | `/xental/<env>/*` in SSM | **no** | secrets: DB/Redis passwords, GHCR + GitHub tokens, dashboard auth |

`scripts/render-env.sh <env>` concatenates layers 1→4 into
`env/<env>.runtime.env` (chmod 600, git-ignored). Because `--env-file` keeps the
last definition of a duplicated key, later layers win. `docker compose` then
reads only that runtime file.

```
common.env.example ─┐
<env>.env.example  ─┼─ render-env.sh ─▶ env/<env>.runtime.env ─▶ docker compose --env-file
versions/<env>.env ─┤                         ▲
SSM /xental/<env>/* ┘                         (secrets decrypted here, never on disk in git)
```

## Variable catalogue

**Shared**: `ENVIRONMENT`, `DOMAIN`, `ACME_EMAIL`
**Image pins**: `TRAEFIK_IMAGE`, `POSTGRES_IMAGE`, `REDIS_IMAGE`, `XENTAL_API_IMAGE`, `PAYLIBRE_API_IMAGE`
**Routing**: `XENTAL_API_HOST`, `PAYLIBRE_API_HOST`
**App runtime**: `XENTAL_ASPNETCORE_ENVIRONMENT`, `PAYLIBRE_ASPNETCORE_ENVIRONMENT`
**Database (names in git, passwords in SSM)**: `POSTGRES_USER`, `POSTGRES_PASSWORD`*, `XENTAL_DB_NAME/USER`, `XENTAL_DB_PASSWORD`*, `PAYLIBRE_DB_NAME/USER`, `PAYLIBRE_DB_PASSWORD`*
**Redis**: `REDIS_PASSWORD`*
**Traefik (staging)**: `TRAEFIK_DASHBOARD_AUTH`* (htpasswd `user:hash`)
**Deploy creds (SSM)**: `GITHUB_TOKEN`* (repo clone), `GHCR_USER`, `GHCR_TOKEN`* (image pulls)

`*` = secret, stored in SSM only.

## Setting a secret

```bash
aws ssm put-parameter --overwrite --type SecureString \
  --name /xental/staging/POSTGRES_PASSWORD --value 'S3cretValue'
```

The app `ConnectionStrings__Default` / `ConnectionStrings__Redis` are **composed
in compose** from these parts, so the apps receive ordinary .NET config keys and
need no knowledge of this layering.

## Adding a new service (e.g. a frontend)

1. Add its non-secret config keys to `env/common.env.example` / `env/<env>.env.example`.
2. Add any secrets to SSM under `/xental/<env>/<NAME>`.
3. Add a service block + Traefik labels in `compose/docker-compose.yml`.
4. Add its image pin to `versions/<env>.env` (CI will maintain it).

That's it — the render + deploy pipeline picks it up with no special-casing.
