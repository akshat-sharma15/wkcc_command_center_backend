#!/usr/bin/env bash
# Source this file to load local dev environment variables into your shell:
#   source scripts/dev_env.sh
set -a
# shellcheck disable=SC1091
if [ -n "${ZSH_VERSION:-}" ]; then
	SCRIPT_PATH="${(%):-%N}"
else
	SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../.env"
set +a

# Derived Redis URLs (built from the discrete host/port/db vars in .env so
# there's a single source of truth for the connection parameters).
export REDIS_SIDEKIQ_URL="redis://${REDIS_HOST}:${REDIS_PORT}/${REDIS_SIDEKIQ_DB}"
export REDIS_CACHE_URL="redis://${REDIS_HOST}:${REDIS_PORT}/${REDIS_CACHE_DB}"
export REDIS_EVENTS_URL="redis://${REDIS_HOST}:${REDIS_PORT}/${REDIS_EVENTS_DB}"

# Locally-built toolchains (no Homebrew/Docker on this machine) + rbenv.
LOCAL_TOOLS="$HOME/local-tools"
export PATH="$HOME/.rbenv/shims:$LOCAL_TOOLS/Postgres.app/Contents/Versions/16/bin:$LOCAL_TOOLS/redis:$PATH"
