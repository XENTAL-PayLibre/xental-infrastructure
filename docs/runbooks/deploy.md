# Runbook: Deploy

## Normal release (automatic)
- **Staging:** merge/push to `staging` in an app repo (`xental-backend`/`paylibre`).
  Build → GHCR → auto-deploy to staging. Watch: app repo Actions → infra repo
  "Deploy staging".
- **Production:** push to `main` in an app repo. Build → GHCR → "Deploy production"
  **waits for approval** (Actions → review). Approve to roll out.

## Manual redeploy (no code change)
infra repo → Actions → **Deploy staging** / **Deploy production** → Run workflow
(leave inputs empty to redeploy the current pinned images).

## What a deploy does
Renders the runtime env from GitHub secrets → rsyncs the stack to the host over
SSH → `docker compose pull && up -d` → health-checks every service → **auto-rolls
back** to the last good release if health fails.

## Verify a deploy
```bash
ssh -i ~/.ssh/xental_deploy ubuntu@<host-ip>
cd /opt/xental-infrastructure
docker compose -f compose/docker-compose.yml -f compose/docker-compose.<env>.yml \
  --env-file env/<env>.runtime.env ps
docker run --rm --network xental-internal curlimages/curl -fsS http://xental-api:8080/health
```
Or externally: `curl https://<api-host>/health` (once DNS/TLS is set).

## Common failure modes
| Symptom | Cause | Fix |
|---|---|---|
| `startup_failure` immediately | org Actions token is read-only | Org → Settings → Actions → Workflow permissions → Read and write |
| `not found` on image pull | `:prod`/`:staging` image never built | push the app repo branch to build it; check GHCR |
| deploy step exit 255 | transient SSH drop | re-run the deploy workflow |
| `SSH_HOST not set` | env vars missing | set `SSH_HOST`/`SSH_USER` on the GitHub Environment |
| host unreachable | instance stopped | start it (see host-lifecycle.md) |
