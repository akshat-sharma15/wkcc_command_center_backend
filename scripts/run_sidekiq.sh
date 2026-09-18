#!/usr/bin/env bash
# Starts a Sidekiq worker process.
set -euo pipefail

: "${REDIS_SIDEKIQ_URL:?Run 'source scripts/dev_env.sh' first}"

bundle exec sidekiq -C config/sidekiq.yml
