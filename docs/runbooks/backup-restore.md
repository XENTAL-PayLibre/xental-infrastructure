# Runbook: Backup & restore

Automated Postgres backups run as the `db-backup` service (added by the backup
overlay): a nightly `pg_dump` of each database, uploaded to S3 (when `BACKUP_S3_BUCKET`
is set) and retained locally.

## Verify backups are running
```bash
cd /opt/xental-infrastructure
docker logs xental-db-backup --tail 20
docker exec xental-db-backup ls -lh /backups        # local copies
aws s3 ls s3://$BACKUP_S3_BUCKET/postgres/ --recursive | tail   # if S3 enabled
```

## On-demand backup
```bash
docker exec xental-db-backup /backup.sh            # runs the same dump now
```

## Restore a database
> Restoring overwrites data. Confirm the target env first.
```bash
cd /opt/xental-infrastructure
# 1. Fetch the dump (from S3 or local /backups)
aws s3 cp s3://$BACKUP_S3_BUCKET/postgres/<env>/xental-YYYYMMDD.sql.gz /tmp/restore.sql.gz
# 2. Drop+recreate is risky; prefer restoring into the existing DB:
gunzip -c /tmp/restore.sql.gz | \
  docker exec -i xental-postgres psql -U xental_admin -d xental
# 3. Restart the dependent app so connections reset
docker compose ... up -d --force-recreate xental-api
```
For a full cluster restore, stop the apps first, restore each DB, then start apps.

## Point-in-time / disaster recovery
- These are logical dumps (good for app-level restore + migration safety).
- For stronger RPO, migrate prod Postgres to **AWS RDS** (automated snapshots +
  PITR) — the compose just points `ConnectionStrings__Default` at the RDS endpoint.

## Test restores
Quarterly: restore the latest prod dump into staging and smoke-test. A backup you
haven't restored is not a backup.
