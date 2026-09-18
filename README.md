# Webkorps Business Operations Command Center — Backend

A Ruby on Rails API backend for the Webkorps Business Operations Command
Center: operational master data (vehicles, trips, hubs, warehouses,
packages, finance, workforce), a real-time operational event stream, and an
alert/notification engine — designed as a separate service alongside the
[Webkorps Command Center](../Wk_command_center) Superset deployment (see
that repo's `ARCHITECTURE.md`).

Runs directly on the host, no Docker, no Kamal.

- **Base:** Rails 8.1 (`--api` mode), Ruby 3.3.12
- **Databases:** three logical PostgreSQL databases (`primary`,
  `operations`, `command_center`) via Rails' native multi-database support
- **Background jobs:** Sidekiq + Redis
- **Real-time:** Server-Sent Events over Redis Pub/Sub (Stage 3+, not yet
  built)

This is **Stage 1 + Stage 2** of a 10-stage roadmap: project setup
(PostgreSQL/Redis/Sidekiq wiring, API skeleton, bearer-token auth) and CRUD
for the seven operational entities. See `ARCHITECTURE.md` for the full
roadmap and what's deliberately deferred.

## Quick start

```bash
cp .env.example .env   # then edit .env with your local DB/Redis credentials
source scripts/dev_env.sh

./scripts/init_db.sh                # db:create db:migrate db:seed, all 3 databases

./scripts/run_server.sh             # terminal 1: API on :3001
./scripts/run_sidekiq.sh            # terminal 2: Sidekiq worker
```

Full setup instructions, including PostgreSQL/Redis provisioning, are in
[DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md). API endpoints are documented
in [API.md](API.md). System design and the staged roadmap are in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Testing

```bash
bundle exec rspec
```

## Issuing an API token

There is no admin UI yet (Stage 1/2 scope). Issue a token from the Rails
console:

```ruby
client, raw_token = ApiClient.create_with_token!(name: "some-service", scopes: [])
puts raw_token   # shown once; only a digest is persisted
```
