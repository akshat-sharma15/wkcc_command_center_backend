-- Provisioning SQL for the Command Centre AI chatbot's dedicated
-- read-only Postgres role (Phase 5). Run once per environment (local
-- dev, staging, production) as a Postgres superuser, against the
-- `operations` database (wkcc_ops_development / wkcc_ops_test /
-- production equivalent).
--
-- This was applied directly via psql in this local environment (not a
-- Rails migration - roles/grants are cluster/database-level objects, not
-- schema Rails should manage or that the AI's own read-only role should
-- ever be able to alter). See config/database.yml's `ai_readonly`
-- connection and app/models/ai_read_only_record.rb.
--
-- Replace :'ai_readonly_password' with a real generated secret before
-- running (psql: `\set ai_readonly_password 'the-real-secret'` first, or
-- substitute it directly) - never commit a real password into this file.

CREATE ROLE wkcc_ai_readonly WITH LOGIN PASSWORD :'ai_readonly_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;

-- Defense in depth: even if a bug in CommandCenter::QueryService ever let
-- a write-shaped statement through, Postgres itself refuses it for every
-- transaction this role opens.
ALTER ROLE wkcc_ai_readonly SET default_transaction_read_only = on;

-- This role only ever needs the operations database. It is NOT denied
-- CONNECT to the command_center/primary databases at the Postgres level
-- (PUBLIC's default CONNECT grant on every database applies to every
-- role, and revoking it FROM PUBLIC would break other roles that rely on
-- that default - e.g. Superset's own wkcc_app role). Instead, it is
-- granted ZERO table privileges in those databases (see below is only
-- ever run against `operations`), which is the boundary that actually
-- matters: bare CONNECT with no GRANTed tables yields no readable data at
-- all. A production deployment on a dedicated Postgres cluster (rather
-- than this shared local dev server) can additionally lock this down at
-- the network/pg_hba.conf level if desired.
\c wkcc_ops_development

GRANT USAGE ON SCHEMA public TO wkcc_ai_readonly;

-- Approved analytical views (8) - the PRIMARY data source for the chatbot.
GRANT SELECT ON
  vw_hub_dashboard_summary,
  vw_hub_dashboard_overview,
  vw_fleet_dashboard_summary,
  vw_vehicle_dashboard,
  vw_route_dashboard,
  vw_shipment_dashboard_summary,
  vw_shipment_dashboard,
  vw_network_health_summary
TO wkcc_ai_readonly;

-- Approved raw tables (10) - operational event history / drill-down only.
-- Deliberately excludes warehouses, payment_dues, alert_rules,
-- event_definitions, notifications - never grant SELECT on those to this
-- role.
GRANT SELECT ON
  hubs,
  vehicles,
  trips,
  packages,
  orders,
  hub_operations_events,
  vehicle_operation_events,
  package_status_transitions,
  workforce_members,
  alerts
TO wkcc_ai_readonly;

-- Rails' own bookkeeping tables - harmless migration-version metadata,
-- needed so ActiveRecord::Migration.maintain_test_schema! (and Rails
-- generally) can read schema version without erroring for this
-- connection. See config/database.yml's `database_tasks: false` on the
-- `ai_readonly` entry, which stops Rails from trying to MIGRATE this
-- connection - this grant is only for the read Rails still does.
GRANT SELECT ON schema_migrations, ar_internal_metadata TO wkcc_ai_readonly;

-- Repeat the `\c` + two SELECT GRANT blocks above (view list + table
-- list) against wkcc_ops_test and the production operations database as
-- each environment is provisioned. schema_migrations/ar_internal_metadata
-- only need the grant in environments Rails itself manages (dev/test).
