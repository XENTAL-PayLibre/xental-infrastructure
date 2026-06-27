# Runbook: Secret rotation

Secrets live in **GitHub Environment secrets** (per env) on `xental-infrastructure`,
plus `INFRA_DISPATCH_TOKEN` in the app repos. Rotating = update the secret, then
redeploy so the host re-renders its runtime env.

## General procedure
```bash
gh secret set <NAME> --env <staging|production> \
  --repo XENTAL-PayLibre/xental-infrastructure --body "<new-value>"
# then redeploy that environment (Actions -> Deploy <env>)
```
The deploy re-renders `env/<env>.runtime.env` from the new secret and recreates
the affected containers.

## DB / Redis passwords
`POSTGRES_PASSWORD`, `XENTAL_DB_PASSWORD`, `PAYLIBRE_DB_PASSWORD`, `REDIS_PASSWORD`.
- The app DB users' passwords are applied at first DB init. To rotate an existing
  DB user password, update it in Postgres too:
  ```sql
  ALTER ROLE xental_app WITH PASSWORD '<new>';
  ```
  then set the matching GitHub secret and redeploy.
- Redis password change → set secret + redeploy (recreates redis + apps).

## GHCR token (`GHCR_TOKEN`)
Create a new `read:packages` token, `gh secret set GHCR_TOKEN ...` on both envs,
redeploy. Revoke the old token in GitHub.

## Dispatch token (`INFRA_DISPATCH_TOKEN`, app repos)
Create a new classic token (`public_repo`), set on both app repos, delete the old.

## SSH deploy key (`SSH_PRIVATE_KEY`)
1. `ssh-keygen -t ed25519 -f ~/.ssh/xental_deploy_new -N ""`
2. Add the new public key to the hosts (Terraform `ssh_public_key` → `terraform apply`,
   or append to `~ubuntu/.ssh/authorized_keys` on each host).
3. `gh secret set SSH_PRIVATE_KEY --env <env> ... --body "$(cat ~/.ssh/xental_deploy_new)"`
4. Verify a deploy works, then remove the old key from the hosts.

## Slack webhook (observability)
Update `SLACK_WEBHOOK_URL` in `xental-observability/.env` on the monitoring host,
then `docker compose up -d --force-recreate slack-url-init alertmanager`.

## After any rotation
- Redeploy and confirm health (deploy.md).
- Revoke/delete the old credential at its source.
