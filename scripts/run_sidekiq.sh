#!/usr/bin/env bash
# Starts a Sidekiq worker process. .env is loaded automatically by
# dotenv-rails, so no prior `source` step is needed.
set -euo pipefail

bundle exec sidekiq -C config/sidekiq.yml
