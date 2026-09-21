#!/usr/bin/env bash
# One-time (or reset) database initialization for local dev.
# Usage: ./scripts/init_db.sh
# .env is loaded automatically by dotenv-rails, so no prior `source` step
# is needed.
set -euo pipefail

echo "==> Creating databases (primary, operations, command_center) if needed"
bundle exec rails db:create

echo "==> Running migrations across all three databases"
bundle exec rails db:migrate

echo "==> Seeding development data"
bundle exec rails db:seed

echo "==> Done. Start the app with: ./scripts/run_server.sh"
