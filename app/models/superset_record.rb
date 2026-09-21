# Read-only access to the Superset metadata database's Flask-AppBuilder
# identity tables (ab_user/ab_role/ab_user_role). Deliberately NOT part of
# the migration-managed multi-database setup in config/database.yml (see
# ARCHITECTURE.md's "Deferred: read-only Superset identity lookup") — this
# app never runs migrations against Superset's database, so this
# connection is established directly via establish_connection, gated on
# whether the required env vars are actually present.
#
# Required environment variables (see .env.example):
#   SUPERSET_PGHOST
#   SUPERSET_PGPORT      (defaults to 5432)
#   SUPERSET_PGDATABASE
#   SUPERSET_PGUSER      (a read-only role, e.g. wkcc_backend_ro,
#                         granted SELECT only on ab_user/ab_role/ab_user_role)
#   SUPERSET_PGPASSWORD
#
# None of these are set in this repository — nobody should guess real
# Superset credentials here. Until they're configured, .configured? is
# false and every SupersetDirectory method returns an empty result rather
# than attempting a connection.
class SupersetRecord < ApplicationRecord
  self.abstract_class = true

  REQUIRED_ENV_VARS = %w[SUPERSET_PGHOST SUPERSET_PGDATABASE SUPERSET_PGUSER SUPERSET_PGPASSWORD].freeze

  def self.configured?
    REQUIRED_ENV_VARS.all? { |key| ENV[key].present? }
  end

  if configured?
    establish_connection(
      adapter: "postgresql",
      host: ENV["SUPERSET_PGHOST"],
      port: ENV.fetch("SUPERSET_PGPORT", 5432),
      database: ENV["SUPERSET_PGDATABASE"],
      username: ENV["SUPERSET_PGUSER"],
      password: ENV["SUPERSET_PGPASSWORD"]
    )
  end

  # Defense in depth: even if something bypasses SupersetDirectory and
  # calls .save/.destroy directly on one of these models, it fails loudly
  # rather than writing to Superset's database.
  def readonly?
    true
  end
end
