#!/usr/bin/env bash
# Restores an operations DB dump produced by dump_operations_db.sh onto
# THIS machine's local Postgres (creates the database if it doesn't exist
# yet). WARNING: replaces any existing data in the target database.
#
# Usage: ./scripts/restore_operations_db.sh path/to/operations_db_*.dump
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 path/to/dump_file" >&2
  exit 1
fi

DUMP_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Reads only the specific keys this script needs, rather than `source`ing
# the whole .env - some values in there (e.g. GEMINI_API_KEY) aren't valid
# bash tokens and would break a full source.
env_var() {
  grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-
}
PGHOST="$(env_var PGHOST)"
PGPORT="$(env_var PGPORT)"
PGUSER="$(env_var PGUSER)"
export PGPASSWORD="$(env_var PGPASSWORD)"
OPERATIONS_DB_NAME="$(env_var OPERATIONS_DB_NAME)"
export PATH="$HOME/local-tools/Postgres.app/Contents/Versions/16/bin:$PATH"

echo "==> Ensuring database ${OPERATIONS_DB_NAME} exists on ${PGHOST}:${PGPORT}"
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$OPERATIONS_DB_NAME" 2>/dev/null || true

echo "==> Restoring ${DUMP_FILE} into ${OPERATIONS_DB_NAME} (replaces existing data there)"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$OPERATIONS_DB_NAME" \
  --clean --if-exists --no-owner --no-privileges "$DUMP_FILE"

echo "==> Done. Verify with:"
echo "      bundle exec rails runner 'puts Vehicle.count'"
