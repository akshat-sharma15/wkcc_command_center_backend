#!/usr/bin/env bash
# One-time (or reset) database initialization for local dev.
# Usage: source scripts/dev_env.sh && ./scripts/init_db.sh
set -euo pipefail

: "${PGHOST:?Run 'source scripts/dev_env.sh' first}"
: "${PRIMARY_DB_NAME:?Run 'source scripts/dev_env.sh' first}"

echo "==> Creating databases (primary, operations, command_center) if needed"
bundle exec rails db:create

echo "==> Running migrations across all three databases"
bundle exec rails db:migrate

echo "==> Seeding development data"
bundle exec rails db:seed

echo "==> Done. Start the app with: ./scripts/run_server.sh"
