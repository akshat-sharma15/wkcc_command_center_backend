# Development Setup

Gets a clean clone running locally on macOS or Linux — no Docker.

## Pinned versions

| Component | Version | Source of truth |
|---|---|---|
| Ruby | 3.3.12 | `.ruby-version` |
| Rails | ~> 8.1.3 | `Gemfile` |
| PostgreSQL | 14+ (developed against 16.x) | this document |
| Redis | 6+ (developed against 7.x) | this document |
| Sidekiq | ~> 7.3 (pinned with connection_pool ~> 2.5) | `Gemfile`, see `ARCHITECTURE.md` |

## 1. Ruby

Via [rbenv](https://github.com/rbenv/rbenv) (don't use the OS-packaged
Ruby — version drift breaks native extensions):

```bash
rbenv install 3.3.12
cd wkcc_command_center_backend
rbenv local 3.3.12   # already committed as .ruby-version
gem install bundler
```

**macOS-specific note:** if `rbenv install` fails on the `psych` extension
with `yaml.h file not found`, libyaml isn't on this machine (this happens
when Homebrew isn't available/working, since `brew install libyaml` is the
usual fix). Build it from source and point ruby-build at it:

```bash
curl -sL -o /tmp/libyaml.tar.gz https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
mkdir -p /tmp/libyaml-build && tar xzf /tmp/libyaml.tar.gz -C /tmp/libyaml-build --strip-components=1
cd /tmp/libyaml-build && ./configure --prefix="$HOME/local-tools/libyaml" && make && make install
RUBY_CONFIGURE_OPTS="--with-libyaml-dir=$HOME/local-tools/libyaml" rbenv install 3.3.12
```

## 2. PostgreSQL

This app expects a local PostgreSQL 16 server reachable at the host/port in
your `.env` (see below). If you're also running the sibling
`Wk_command_center` (Superset) project on this machine, **reuse its
Postgres instance** rather than starting a new one — this app just adds
new databases and a new role to it:

```bash
psql -h <PGHOST> -p <PGPORT> -U postgres -d postgres <<SQL
CREATE ROLE wkcc_backend_app LOGIN PASSWORD 'choose-a-local-password';
CREATE DATABASE wkcc_backend_development OWNER wkcc_backend_app;
CREATE DATABASE wkcc_backend_test        OWNER wkcc_backend_app;
CREATE DATABASE wkcc_ops_development     OWNER wkcc_backend_app;
CREATE DATABASE wkcc_ops_test            OWNER wkcc_backend_app;
CREATE DATABASE wkcc_cc_development      OWNER wkcc_backend_app;
CREATE DATABASE wkcc_cc_test             OWNER wkcc_backend_app;
SQL
```

Verify:

```bash
psql -h <PGHOST> -p <PGPORT> -U wkcc_backend_app -d wkcc_backend_development -c '\conninfo'
```

If you don't have a Postgres 16 server at all yet, install one (Homebrew:
`brew install postgresql@16`; or see the sibling Superset project's own
`DEVELOPMENT_SETUP.md` for a Homebrew-free fallback using Postgres.app)
before running the above.

## 3. Redis

This app reuses whatever local Redis instance you've designated in
`.env` (`REDIS_HOST`/`REDIS_PORT`) — by default, the same isolated Redis
instance the sibling Superset project runs on a non-default port, to avoid
colliding with a possibly-shared default Redis at `:6379` on this machine.
Verify:

```bash
redis-cli -h <REDIS_HOST> -p <REDIS_PORT> ping   # expect: PONG
```

No further setup needed — logical DB indices (4/5/6, see `ARCHITECTURE.md`)
don't need to be created ahead of time.

## 4. Environment configuration

```bash
cp .env.example .env
```

Edit `.env`: fill in `PGPASSWORD` (from step 2), confirm `PGHOST`/`PGPORT`
and `REDIS_HOST`/`REDIS_PORT` match your local setup, and set a
`SIDEKIQ_WEB_PASSWORD` for the `/sidekiq` dashboard.

Load it before any `rails`/`bundle`/`sidekiq` command:

```bash
source scripts/dev_env.sh
```

## 5. Backend installation

```bash
bundle install
```

`pg` needs `pg_config` on `PATH` to build its native extension — if you're
using a non-Homebrew Postgres (e.g. Postgres.app), add its `bin/` directory
to `PATH` before running `bundle install` (already handled by
`scripts/dev_env.sh` if you're pointing at the sibling Superset project's
Postgres.app install).

## 6. Database initialization

```bash
./scripts/init_db.sh
```

Runs `db:create db:migrate db:seed` across all three databases (primary,
operations, command_center). Safe to re-run.

## 7. Starting the app

```bash
./scripts/run_server.sh     # terminal 1: API on :3001 (or $PORT)
./scripts/run_sidekiq.sh    # terminal 2: Sidekiq worker
```

Verify:

```bash
curl http://localhost:3001/api/v1/health
```

Sidekiq dashboard (Basic Auth, `SIDEKIQ_WEB_USERNAME`/`SIDEKIQ_WEB_PASSWORD`
from `.env`): `http://localhost:3001/sidekiq`.

## 8. Running tests

```bash
bundle exec rspec
```

## 9. Troubleshooting

- **`pg_config` not found / `pg` gem fails to build**: see step 5.
- **`PG::ConnectionBad`**: confirm `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD`
  in `.env` match a running Postgres and that you ran `source
  scripts/dev_env.sh`.
- **Sidekiq jobs enqueue but scheduled jobs never fire**: check the
  `connection_pool` gem version pin in `Gemfile` — see `ARCHITECTURE.md`.
- **Port 3001 already in use**: another local project may be on it;
  override `PORT` in `.env`.

## 10. Resetting local development

```bash
psql -h <PGHOST> -p <PGPORT> -U postgres -c "DROP DATABASE wkcc_ops_development;"
psql -h <PGHOST> -p <PGPORT> -U postgres -c "CREATE DATABASE wkcc_ops_development OWNER wkcc_backend_app;"
# repeat for wkcc_backend_development / wkcc_cc_development as needed
./scripts/init_db.sh
```

This never touches the sibling Superset project's `wkcc_superset` database
or any other project's data on a shared machine.
