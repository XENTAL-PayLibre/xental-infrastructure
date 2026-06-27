# Runbook: Rollback

## Automatic (no action)
Every deploy health-checks and, on failure, redeploys the last known-good
release (`env/<env>.runtime.env.deployed`) and marks the run failed.

## Via GitHub Actions (preferred)
infra repo → Actions → **Rollback** → Run workflow:
- `environment`: staging | production
- `sha`: target app SHA, or empty to revert to the previous pins.

It rewrites `versions/<env>.env`, commits (audit trail), and redeploys through
the health-checked path.

## On the host (break-glass)
```bash
ssh -i ~/.ssh/xental_deploy ubuntu@<host-ip>
cd /opt/xental-infrastructure
scripts/rollback.sh <env>            # previous known-good release
scripts/rollback.sh <env> <sha>      # pin both apps to sha-<sha>
```

## Find a good SHA to roll back to
- GHCR package page lists `sha-<commit>` tags (immutable).
- `git log` in the app repo, or the infra `versions/<env>.env` history.

## Note on databases
Image rollback does NOT undo schema migrations — use expand/contract migrations
so an older app stays compatible. For data corruption, see backup-restore.md.
