# Architecture

## Why this exists

The [Webkorps Command Center](../Wk_command_center) Superset fork's own
`ARCHITECTURE.md` anticipates a companion service for operational data and
alerting: "External Alert/Notification Application... a separate
service/repo... not a module built inside Superset's codebase." This repo
is that companion service.

## Current state (Stage 1 + Stage 2 of 10)

```
                    OPERATIONS DATA
                          |
                          v
                   Rails Application
                          |
             +------------+-------------+
             |            |             |
             v            v             v
           CRUD       Event Engine   Alert Engine      <- Stage 3+, not built
             |            |             |
             |            v             v
             |       Event Stream     Alert Rules      <- Stage 3+/7+, not built
             |            |             |
             |            +------> SSE Stream          <- Stage 6, not built
             |                         |
             v                         v
       PostgreSQL                 Superset
      (operations db)            Command Center
```

Only the CRUD path (Vehicles, Trips, Hubs, Warehouses, Packages, Finance,
Workforce) exists today. No event system, simulator, alert engine,
integrations, or SSE stream has been built yet.

## Three databases, one Postgres server

This app owns three logical PostgreSQL databases via Rails' native
multi-database support (`config/database.yml`, `connects_to`), all on the
same local Postgres 16 server already used by the Superset project
(`localhost:55432`), under a new dedicated role (`wkcc_backend_app`) that
does not touch Superset's own database:

- **`primary`** (`ApplicationRecord`) — cross-cutting app tables.
  `ApiClient` today; nothing else until later stages.
- **`operations`** (`OperationsRecord`) — Vehicle, Trip, Hub, Warehouse,
  Package, PaymentDue, WorkforceMember (Stage 2).
- **`command_center`** (`CommandCenterRecord`) — events, alert rules,
  integrations, notifications (Stage 3+). Migrated to an empty schema now
  so the third connection is proven wired (see `GET /api/v1/health`)
  rather than rediscovered later.

**Hard rule:** no foreign key or ActiveRecord association may cross the
`operations` ↔ `command_center` boundary. The Stage 3+ event domain only
ever references operational entities loosely via `entity_type`/`entity_id`
(never a real FK) — cross-domain lookups always resolve those in a service
object, never a database join. This is what makes splitting the databases
now (rather than after Stage 3+ tables exist) free of future rework.

## Redis

Reuses the Superset project's isolated local Redis instance
(`localhost:6380`, chosen there specifically to avoid the shared default
Redis at `:6379` used by other projects on this machine) rather than
standing up a fourth Redis process. That project reserves logical DB
indices 1 (Celery broker), 2 (Celery results), 3 (cache); this app reserves:

- `REDIS_SIDEKIQ_DB=4`
- `REDIS_CACHE_DB=5` (Rails cache store)
- `REDIS_EVENTS_DB=6` (reserved for the Stage 3+ event pub/sub channel;
  unused until then)

## API authentication (V1)

Bearer-token, service-to-service. `ApiClient` (in the `primary` database)
stores a name, a SHA-256 digest of the token (never the token itself — see
`app/models/api_client.rb` for why this isn't bcrypt), a `scopes` string
array, and `active`/`last_used_at`. Every `Api::V1::BaseController`
subclass requires a valid `Authorization: Bearer <token>` header via the
`ApiAuthenticatable` concern. No admin UI yet — tokens are issued from the
Rails console (see `README.md`). Scopes are checked in-memory
(`current_api_client.has_scope?(...)`); no separate scopes table until an
admin UI actually needs scope metadata.

## Deferred: read-only Superset identity lookup

Not built in Stage 1/2. When a later stage needs to resolve Superset users/
roles (e.g. for alert recipient resolution), the intended design is:

- A dedicated, **read-only** Postgres role (e.g. `wkcc_backend_ro`) granted
  `SELECT` only on Superset's `ab_user`, `ab_role`, `ab_user_role` tables
  (Flask-AppBuilder's identity schema — confirmed against the installed
  flask-appbuilder 5.0.2 source: `ab_user(id, first_name, last_name,
  username, password, active, email, ...)`, `ab_role(id, name)`,
  `ab_user_role(id, user_id, role_id)`).
- A plain `establish_connection` in Rails (e.g. `SupersetUser < ApplicationRecord`
  with `self.table_name = "ab_user"`), **outside** the migration-managed
  multi-database setup above — this connection is read-only and this app
  never runs migrations against Superset's database.
- This app **never** modifies Superset's tables, migrations, or metadata.

## Event system, simulator, alert engine, SSE (Stage 3–10)

Not built. See the root task's full roadmap for the intended shape:
generic event ingestion (`POST /api/v1/events`) validated against
admin-definable `EventDefinition`s, publishing to Redis Pub/Sub, async
alert-rule evaluation and notification delivery via Sidekiq, and an
`ActionController::Live`-based SSE endpoint (`GET /api/v1/events/stream`)
that subscribes to Redis Pub/Sub per-connection — explicitly not
WebSockets at this stage, but designed so WebSockets could supplement or
replace SSE later without redesigning the event domain (the event
occurrence, publisher, and subscriber layers are already separated by
directory: `app/publishers/`, `app/subscribers/`, currently empty).

The event simulator (Stage 4) will be a self-rescheduling Sidekiq job that
picks real existing records (never fabricated IDs) and pushes them through
the exact same `Events::IngestEvent` pipeline a real external API call
would use — no shortcut path.

## Project layout

```
app/
  controllers/api/v1/    RESTful resource controllers, one per domain
  controllers/concerns/  ApiAuthenticatable
  models/                ApplicationRecord / OperationsRecord / CommandCenterRecord
                          + one model per resource
  serializers/api/v1/    Plain PORO serializers (no gem dependency yet)
  jobs/                  Sidekiq::Job subclasses (ApplicationJob base)
  services/              Empty — Stage 3+ (plain CRUD doesn't need service objects)
  publishers/ subscribers/  Empty — Stage 3+ (event pub/sub)
db/
  migrate/                 primary database
  operations_migrate/      operations database
  command_center_migrate/  command_center database (empty for now)
  seeds/                   one file per entity, realistic non-uniform data
scripts/
  dev_env.sh    source this first; loads .env + PATH for local toolchains
  init_db.sh    db:create db:migrate db:seed across all 3 databases
  run_server.sh run_sidekiq.sh
```

## Version pinning

- Rails 8.1.3.1, Ruby 3.3.12 (via rbenv) — see `.ruby-version` and `Gemfile`.
- `sidekiq ~> 7.3` is pinned together with `connection_pool ~> 2.5`:
  Sidekiq 7.3.x's scheduler thread breaks silently against
  `connection_pool` 3.0+ (keyword-only `pop` vs Sidekiq's positional call).
  This matters because Stage 4 (simulator) and Stage 7 (notifications) both
  depend on scheduled/delayed jobs.
