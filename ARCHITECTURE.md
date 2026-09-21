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
  Package, PaymentDue, WorkforceMember (Stage 2); `AlertRule`, `Alert`,
  and the alert-configuration columns on five of those models (alert-system
  refactor Phase 1); `EventDefinition` (Phase 3 — moved here from
  `command_center` specifically so `AlertRule.belongs_to :event_definition,
  optional: true` could be a real FK instead of a cross-database
  reference). All alert-related schema and persistence lives here.
- **`command_center`** (`CommandCenterRecord`) — owns no application
  tables anymore. An unused `alerts` table (the old `Alert`, previously
  `belongs_to :event_definition`) still exists here — its Ruby model/
  controller/API were removed as obsolete back in Phase 1, and the table
  itself was deliberately left in place (cleanup is a separate decision);
  its FK to `event_definitions` was dropped in the same migration that
  moved `EventDefinition` out, since Postgres won't drop a table something
  still references. Integrations, notifications, and event occurrences are
  not built yet (Stage 4+).

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

## Event definitions (Stage 3)

One model in the `command_center` database:

- **`EventDefinition`** — `name` (unique), `group`, `event_type`. `group`
  and `event_type` are validated against a fixed, code-defined vocabulary
  (`EventDefinition::GROUPS_AND_TYPES`) rather than a separate lookup
  table, since the taxonomy is fixed for this stage (Hubs, Fleet /
  Transport, Workforce, Sales, Finance — see `API.md`). These are event
  *type* definitions, not operational models — `"Capacity"` is a string
  value of `event_type`, not a `Capacity` model, and the same applies to
  every other group/type name that happens to echo an operational concept
  (Hub, Truck, Accident, ...).

## Alert-system refactor Phase 1 (operations DB)

The original `Alert` (`command_center`, `belongs_to :event_definition`,
`role` + `description`) was replaced — alerts are no longer tied to
`EventDefinition` at all. The new design targets business-model fields
directly, entirely within the `operations` database:

- **Five alertable models** — `Vehicle`, `Hub`, `Package`, `PaymentDue`,
  `WorkforceMember` — each gained two columns: `allow_alerts` (boolean,
  default `false`) and `alertable_fields` (Postgres `string[]`, default
  `[]`). A record opts into alerting and declares which of its own
  columns may be targeted. **Trip is deliberately excluded** (explicit
  product decision). A "routes" group and a new `Route` model were
  considered (since `Trip` was off the table) and then deliberately
  dropped — there was no independent business-domain need for a `Route`
  entity beyond serving the alert system, and a model shouldn't be
  invented solely for that. If a genuine `Route`/lane entity is needed
  later, add it on its own merits and then extend `ALERTABLE_MODELS`.
- **`AlertRule::ALERTABLE_MODELS`** — a plain frozen hash (`"vehicles" =>
  Vehicle`, etc.), the server-side allowlist/security boundary for which
  models a rule's `group` may reference. Deliberately *not* an
  `AlertResource`/`AlertResourceField` table — this is application code,
  not database data — and frontend input is never `constantize`d;
  `AlertRule#target_model` always resolves through this hash.
- **`AlertRule`** — `name`, `group`, `field`, `operator`, `value` (jsonb),
  `severity`, `notify`, `recipient_type`, `recipient_id`, `enabled`,
  `created_by_user_id`. Validates `group` is an allowlisted key, `field`
  is an actual column on that group's model, and `field` is listed in
  `alertable_fields` on at least one `allow_alerts: true` record of that
  model — i.e. `field_must_be_alertable_on_target_model` queries
  `Model.where(allow_alerts: true).where("? = ANY (alertable_fields)",
  field)`. `recipient_type`/`recipient_id` are only required when
  `notify` is true; `recipient_id` is a plain bigint (e.g. a Superset role
  ID) with no FK, since it may point outside this database entirely.
- **`Alert`** — `belongs_to :alert_rule`, plus `group`/`record_id` (the
  triggering record, resolved the same way as `AlertRule.group` — never a
  real FK, since the target table varies per group), `field`,
  `expected_value`/`actual_value`, `severity`, `status` (`open` /
  `acknowledged` / `resolved`), `triggered_at`, `resolved_at`, `metadata`
  (jsonb). `AlertRule has_many :alerts, dependent: :restrict_with_error`.

**Not built yet** (later phases): no `/api/v1/alerts` or
`/api/v1/alert_rules` route, no `AlertEvaluationJob`, no automatic
triggering, no Slack/notification delivery, no SSE. Phase 1 is the data
layer only.

## Deferred: read-only Superset identity lookup

Not built yet. `AlertRule.recipient_id` is a plain bigint for this stage —
not validated against Superset, so nothing is blocked on it. When a later
stage needs to resolve Superset users/roles (e.g. for alert recipient
resolution), the intended design is:

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
directory: `app/publishers/`, `app/subscribers/`, currently empty).

The event simulator (Stage 4) will be a self-rescheduling Sidekiq job that
picks real existing records (never fabricated IDs) and pushes them through
the exact same `Events::IngestEvent` pipeline a real external API call
would use — no shortcut path.

## Slack integration (connect/disconnect only — no delivery)

`Integration` (`command_center` — reviving that database's originally
intended purpose now that `EventDefinition` has moved out; see above) and
`SlackOauthState` back a standard OAuth v2 flow:
`GET /api/v1/integrations/slack{,/connect,/callback}` and
`DELETE /api/v1/integrations/slack/:id` — see
`app/controllers/api/v1/slack_integrations_controller.rb` and
`app/services/slack_oauth_client.rb` (stdlib `Net::HTTP`, no HTTP client
gem). `Integration#bot_token` is encrypted at rest via Rails 8's built-in
`ActiveRecord::Encryption` (`encrypts :bot_token`), whose keys live in
`config/credentials.yml.enc` (committed — it's encrypted; `config/master.key`
decrypts it and is gitignored, never committed). The token is never
included in any API response (see `IntegrationSerializer`) or logged.

OAuth `state` is DB-backed (`SlackOauthState`, one-time-use, 10-minute
TTL) rather than session/cookie-based: the frontend (`:9000`) and this API
(`:3001`) are different origins with no shared cookie domain, and the
callback is a real cross-site browser redirect from `slack.com` — a
`SameSite=None` cookie would need HTTPS to survive that round-trip, which
local dev doesn't have. Reconnecting the workspace updates the single
`provider: "slack"` row rather than creating a duplicate (`provider` is
unique) — there is one Integration per provider, matching the product
surface of "is Slack connected", not a history of connection attempts.
Disconnecting revokes the token with Slack (`auth.revoke`, best-effort)
and clears `bot_token`/`bot_user_id`/`scope` locally, but keeps the row
(status `disconnected`) rather than deleting it outright.

**Not built**: `chat.postMessage`, any Slack notification/delivery
job, alert-to-Slack routing, Slack Block Kit templates, interactive
actions, or the Slack Events API. This is connect/disconnect only.

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
  command_center_migrate/  command_center database (EventDefinition — Stage 3)
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
