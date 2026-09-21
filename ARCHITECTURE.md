# Architecture

## Why this exists

The [Webkorps Command Center](../Wk_command_center) Superset fork's own
`ARCHITECTURE.md` anticipates a companion service for operational data and
alerting: "External Alert/Notification Application... a separate
service/repo... not a module built inside Superset's codebase." This repo
is that companion service.

## Current state (Stage 1 + Stage 2 + Stage 3 of 10)

```
                    OPERATIONS DATA
                          |
                          v
                   Rails Application
                          |
             +------------+-------------+
             |            |             |
             v            v             v
           CRUD    Event Definitions  Alert Definitions   <- Stage 3 (this stage)
             |     (EventDefinition)      (Alert)
             |            |             |
             |            v             v
             |       Event Ingestion   Integrations       <- Stage 4+/7+, not built
             |       (occurrences)     Alert Execution     <- Stage 4+/7+, not built
             |            |             |
             |            +------> SSE Stream             <- Stage 6, not built
             |                         |
             v                         v
       PostgreSQL                 Superset
      (operations db)            Command Center
```

The CRUD path (Vehicles, Trips, Hubs, Warehouses, Packages, Finance,
Workforce) exists from Stage 2. Stage 3 adds **Event Definition** and
**Alert Definition** management only — `EventDefinition` (name/group/type,
validated against a fixed vocabulary) and `Alert` (name/event/role/
description). No event ingestion, occurrence tracking, simulator, alert
execution, integrations (Slack/SMS/WhatsApp/Email), or SSE stream has been
built yet — see `API.md`'s "Not yet implemented" section.

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
- **`command_center`** (`CommandCenterRecord`) — `EventDefinition` and
  `Alert` (Stage 3). Integrations, notifications, and event occurrences
  are not built yet (Stage 4+).

**Hard rule:** no foreign key or ActiveRecord association may cross the
`operations` ↔ `command_center` boundary. The Stage 4+ event-occurrence
domain will only ever reference operational entities loosely via
`entity_type`/`entity_id` (never a real FK) — cross-domain lookups always
resolve those in a service object, never a database join. This is what
made splitting the databases from Stage 1 (rather than after
`command_center` tables existed) free of rework in Stage 3.

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

## API authentication (V1) — currently disabled

Bearer-token, service-to-service, built and functional but **not currently
enforced** (disabled by explicit request, to simplify local/Postman
testing while the API is still taking shape). `ApiClient` (in the
`primary` database) stores a name, a SHA-256 digest of the token (never
the token itself — see `app/models/api_client.rb` for why this isn't
bcrypt), a `scopes` string array, and `active`/`last_used_at`.
`Api::V1::BaseController` includes the `ApiAuthenticatable` concern (so
`current_api_client`/`authenticate_api_client!`/`require_scope!` are
available), but the `before_action :authenticate_api_client!` line that
would enforce it on every request is commented out — see
`app/controllers/api/v1/base_controller.rb`. Re-enabling authentication is
a one-line change (uncomment that line); everything else (`ApiClient`
model, token issuance, the concern) is unaffected by it being off. No
admin UI for token issuance — tokens are issued from the Rails console
(see `README.md`). Scopes are checked in-memory
(`current_api_client.has_scope?(...)`); no separate scopes table until an
admin UI actually needs scope metadata.

## Event and Alert definitions (Stage 3)

Two models in the `command_center` database, deliberately with **no**
association back into `operations`:

- **`EventDefinition`** — `name` (unique), `group`, `event_type`. `group`
  and `event_type` are validated against a fixed, code-defined vocabulary
  (`EventDefinition::GROUPS_AND_TYPES`) rather than a separate lookup
  table, since the taxonomy is fixed for this stage (Hubs, Fleet /
  Transport, Workforce, Sales, Finance — see `API.md`). These are event
  *type* definitions, not operational models — `"Capacity"` is a string
  value of `event_type`, not a `Capacity` model, and the same applies to
  every other group/type name that happens to echo an operational concept
  (Hub, Truck, Accident, ...).
- **`Alert`** — `name`, `belongs_to :event_definition`, `role` (plain
  string for now — see below), `description`. No `integration` field yet;
  that is added when Stage 3+/7+ builds Slack/SMS/WhatsApp/Email delivery.

Deleting an `EventDefinition` still referenced by an `Alert` is rejected
(`dependent: :restrict_with_error`) — `422` from the API, not a silent
cascade.

Extensibility for later stages: when real operational entities are wired
up (Stage 4+ event ingestion), an `EventOccurrence` will reference both an
`EventDefinition` and the originating operational record via a loose
`entity_type`/`entity_id` pair — never a foreign key — for exactly the
same cross-database reason `operations` and `command_center` are already
split.

## Deferred: read-only Superset identity lookup

Not built yet. `Alert.role` is a plain string for this stage — not
validated against Superset, so Event/Alert APIs are not blocked on it (per
explicit Stage 3 scope). When a later stage needs to resolve Superset
users/roles (e.g. for alert recipient resolution), the intended design is:

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

## Event ingestion, simulator, alert engine, SSE, integrations (Stage 4–10)

Not built. `EventDefinition` and `Alert` (Stage 3, above) only cover
*definition* management. See the root task's full roadmap for the intended
shape of what's next: generic event *occurrence* ingestion
(`POST /api/v1/events/occurrences`, named to avoid colliding with the
Stage 3 `EventDefinition` CRUD at `/api/v1/events`) validated against the
`EventDefinition`s created here, publishing to Redis Pub/Sub, async
alert-rule evaluation and notification delivery via Sidekiq, an
`ActionController::Live`-based SSE endpoint (`GET /api/v1/events/stream`)
that subscribes to Redis Pub/Sub per-connection — explicitly not
WebSockets at this stage, but designed so WebSockets could supplement or
replace SSE later without redesigning the event domain (the event
occurrence, publisher, and subscriber layers are already separated by
directory: `app/publishers/`, `app/subscribers/`, currently empty) — and
the `Integration` model (Slack/SMS/WhatsApp/Email, only Slack functional
initially) plus the `integration` field on `Alert`, deliberately deferred
out of Stage 3.

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
  services/              Empty — Stage 4+ (plain CRUD doesn't need service objects)
  publishers/ subscribers/  Empty — Stage 4+ (event pub/sub)
db/
  migrate/                 primary database
  operations_migrate/      operations database
  command_center_migrate/  command_center database (EventDefinition, Alert — Stage 3)
  seeds/                   one file per entity, realistic non-uniform data
scripts/
  dev_env.sh    optional; only for bundle install's pg_config PATH or raw
                psql/redis-cli — .env itself loads automatically via
                dotenv-rails for every rails/sidekiq/rspec command
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
