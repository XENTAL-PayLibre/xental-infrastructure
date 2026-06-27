#!/bin/sh
# Dump each application database, gzip to the local /backups volume, optionally
# upload to S3, and prune old copies. Run by the db-backup service on a schedule.
set -eu

BACKUP_DIR=/backups
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for db in "$XENTAL_DB_NAME" "$PAYLIBRE_DB_NAME"; do
  out="$BACKUP_DIR/${db}-${TS}.sql.gz"
  echo "==> dumping $db"
  PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h postgres -U "$POSTGRES_USER" -d "$db" | gzip > "$out"
  echo "    wrote $out ($(du -h "$out" | cut -f1))"
  if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
    if command -v aws >/dev/null 2>&1; then
      aws s3 cp "$out" "s3://${BACKUP_S3_BUCKET}/postgres/${ENVIRONMENT}/$(basename "$out")" \
        && echo "    uploaded to s3://${BACKUP_S3_BUCKET}/postgres/${ENVIRONMENT}/" \
        || echo "    S3 upload FAILED (check host IAM role / bucket)"
    else
      echo "    aws cli not available; skipped S3 upload"
    fi
  fi
done

# Prune local copies older than retention.
find "$BACKUP_DIR" -name '*.sql.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
echo "==> backup complete"
