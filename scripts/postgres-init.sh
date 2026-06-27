#!/usr/bin/env bash
# Runs once on first Postgres start (mounted into docker-entrypoint-initdb.d).
# Creates a dedicated database + least-privilege user per application service,
# using values passed through the container environment.
set -euo pipefail

create_db_and_user() {
  local db="$1" user="$2" password="$3"
  echo "Provisioning database '$db' / user '$user'"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${user}') THEN
        CREATE ROLE ${user} LOGIN PASSWORD '${password}';
      END IF;
    END
    \$\$;
SQL
  # CREATE DATABASE cannot run inside a DO block / transaction.
  if ! psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" --username "$POSTGRES_USER" | grep -q 1; then
    createdb --username "$POSTGRES_USER" --owner "$user" "$db"
  fi
}

create_db_and_user "$XENTAL_DB_NAME"   "$XENTAL_DB_USER"   "$XENTAL_DB_PASSWORD"
create_db_and_user "$PAYLIBRE_DB_NAME" "$PAYLIBRE_DB_USER" "$PAYLIBRE_DB_PASSWORD"
