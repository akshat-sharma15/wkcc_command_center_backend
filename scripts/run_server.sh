#!/usr/bin/env bash
# Starts the Rails API server (Puma, with code reloading). .env is loaded
# automatically by dotenv-rails, so no prior `source` step is needed.
set -euo pipefail

bundle exec rails server
