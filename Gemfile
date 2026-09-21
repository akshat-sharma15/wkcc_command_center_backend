source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Pinned: json 3.x's keyword-only `JSON.parse(source, **options)` signature
# breaks ActiveSupport::JSON.decode's positional call, causing every JSON
# request body to fail with `ArgumentError: wrong number of arguments`.
# Ruby 3.3 ships json ~> 2.9 by default; pin to that line explicitly so a
# transitive dependency can't silently pull in 3.x again.
gem "json", "~> 2.9"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Redis client (Rails cache, Sidekiq, and the Stage 3+ event pub/sub channel
# all share the same isolated Redis instance via different logical DB indices)
gem "redis", "~> 5.3"

# Background jobs (event ingestion, simulator, notifications in later stages).
# Pinned: Sidekiq 7.3.x's scheduler thread breaks silently against
# connection_pool 3.0+ (keyword-only `pop` vs Sidekiq's positional call).
gem "sidekiq", "~> 7.3"
gem "connection_pool", "~> 2.5"

# Lightweight pagination for index actions.
gem "pagy", "~> 9.0"

# Rack CORS for cross-origin requests (the Superset frontend dev server runs
# on a different origin and will eventually consume the SSE stream directly).
gem "rack-cors"

group :development, :test do
  # Auto-loads .env into ENV on boot (rails server/console/sidekiq/rspec),
  # so `source scripts/dev_env.sh` is no longer required for day-to-day
  # commands — only for bundle install's pg_config PATH and raw psql/
  # redis-cli. Intentionally excluded from :production — env vars there
  # come from the real deployment environment, never a checked-in file.
  gem "dotenv-rails", "~> 3.1"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
end

group :test do
  gem "webmock", "~> 3.24"
end
