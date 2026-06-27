# Rollback

Rollback is built into the pipeline at four levels, from fully automatic to
fully manual. All of them converge on the same idea: **the deployed version is
whatever `versions/<env>.env` says, and that file lives in git.**

## 1. Automatic rollback on a bad deploy (no action needed)

Every deploy runs `scripts/deploy.sh`, which:

1. snapshots the currently-deployed pins (`versions/<env>.env`) before changing anything,
2. rolls out the new images,
3. runs `scripts/healthcheck.sh` — hits `/health` on every app over the private network,
4. **if health checks fail, it restores the snapshot, redeploys the previous
   images, and exits non-zero** (the GitHub Actions run is marked failed).

So a release that doesn't come up healthy is reverted within the same job.

## 2. Manual rollback via GitHub Actions (recommended)

Run the **Rollback** workflow (Actions → Rollback → Run workflow):

- `environment`: `staging` or `production`
- `sha`: a specific app commit SHA to pin both apps to, **or leave empty** to
  revert to the immediately previous pins.

It rewrites `versions/<env>.env`, commits it (audit trail), pushes, and
redeploys through the same health-checked path. Production still passes through
the approval gate.

## 3. Manual rollback on the host

```bash
ssh-less:  use SSM Session Manager to open a shell on the host, then:
cd /opt/xental-infrastructure
sudo scripts/rollback.sh staging                # revert to previous pins
sudo scripts/rollback.sh production 1a2b3c4      # pin both apps to sha-1a2b3c4
```

## 4. Git revert (source-of-truth rollback)

Because each release is a commit to `versions/<env>.env`, you can always:

```bash
git revert <the-bad-pin-commit>
git push                      # the push triggers the env's deploy workflow
```

## Why immutable tags matter

CI pins images to `:sha-<commit>` (immutable), not just the moving `:staging` /
`:prod` tags. That guarantees a rollback target still resolves to the exact
image that was running, even after newer builds have moved the floating tags.

## Rolling back the database

Image rollback does **not** undo schema migrations. Apply
backward-compatible migrations (expand/contract) so an app rollback stays
compatible with the current schema. Restore from a Postgres backup only as a
last resort.
