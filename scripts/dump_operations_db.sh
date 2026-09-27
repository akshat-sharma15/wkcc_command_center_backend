#!/usr/bin/env bash
# Dumps the operations database (Vehicle, Hub, Location, Vendor, Trip,
# Package, ...) to a single portable file a teammate can restore onto
# their own local Postgres with restore_operations_db.sh.
#
# Usage: ./scripts/dump_operations_db.sh [output_file]
set -euo pipefail

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

OUT_FILE="${1:-$HOME/wkcc_exports/operations_db_$(date +%Y%m%dT%H%M%S).dump}"
mkdir -p "$(dirname "$OUT_FILE")"

echo "==> Dumping ${OPERATIONS_DB_NAME} from ${PGHOST}:${PGPORT} -> ${OUT_FILE}"
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -Fc --no-owner --no-privileges \
  -f "$OUT_FILE" "$OPERATIONS_DB_NAME"

echo "==> Done: $(du -h "$OUT_FILE" | cut -f1) written to $OUT_FILE"
echo "    Send this file to your teammate, then have them run:"
echo "      ./scripts/restore_operations_db.sh $(basename "$OUT_FILE")"
