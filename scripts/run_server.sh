#!/usr/bin/env bash
# Starts the Rails API server (Puma, with code reloading).
set -euo pipefail

: "${PGHOST:?Run 'source scripts/dev_env.sh' first}"

bundle exec rails server -p "${PORT:-3001}"
