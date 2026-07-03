#!/bin/bash
# First-boot initdb hook: create the Semaphore role + database alongside the
# Terrakube one (one shared postgres, two isolated databases). Runs only when
# PGDATA is empty — an existing cluster is never touched.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	CREATE USER ${SEMAPHORE_DB_USER} WITH PASSWORD '${SEMAPHORE_DB_PASS}';
	CREATE DATABASE ${SEMAPHORE_DB_NAME} OWNER ${SEMAPHORE_DB_USER};
	GRANT ALL PRIVILEGES ON DATABASE ${SEMAPHORE_DB_NAME} TO ${SEMAPHORE_DB_USER};
EOSQL
