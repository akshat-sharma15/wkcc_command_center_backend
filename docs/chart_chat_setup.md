# Chart-scoped AI chat setup

The Command Centre assistant can be opened against a single Superset chart
("Ask AI about this chart" in the Charts listing). That conversation is
confined to the chart and the dataset behind it: it cannot read any other
approved source, and follow-up questions stay inside the same scope.

This document covers the configuration the feature needs. The global
assistant (`POST /api/v1/ai/chat`) needs none of it and is unaffected.

## Why Superset calls this endpoint, not the browser

Superset owns the chart/dataset permission model, so it is the only party
that can decide whether a user may ask about a given chart:

```
Browser (chart id only)
  -> Superset  POST /api/v1/chart_chat/        (superset/chart_chat/api.py)
       resolves chart id -> chart -> dataset
       enforces the signed-in user's access to BOTH
       builds the AI context (no credentials, no SQL)
  -> Rails     POST /api/v1/ai/chart_chat      (Api::V1::AiController#chart_chat)
       CommandCenter::ChartScope confines the turn to one source
  -> Gemini -> query_command_center -> read-only Postgres role
```

The browser never sends a dataset id, table name, or SQL - only a chart id.
That is what stops a user from pointing the assistant at data they cannot
otherwise see.

## Required configuration

Both sides need the **same** shared secret. It is what proves to Rails that
a chart-chat request came from Superset after an access check, rather than
from a browser that made up its own context.

Generate one value:

```bash
openssl rand -hex 32
```

Set it in **both** places (never commit either file):

| Where | Variable |
| --- | --- |
| Command Centre (this repo), `.env` | `COMMAND_CENTER_SERVICE_TOKEN` |
| Superset, environment / `superset_config.py` | `COMMAND_CENTER_SERVICE_TOKEN` |

Superset also needs to know where this API lives; it defaults to
`http://localhost:3001` and is overridden with `COMMAND_CENTER_API_ORIGIN`.

### Fails closed

If `COMMAND_CENTER_SERVICE_TOKEN` is blank or unset on the Rails side,
`POST /api/v1/ai/chart_chat` returns **403 for every request**. A missing
deployment step therefore cannot leave the endpoint open to unauthenticated
callers - it leaves the feature switched off instead. The symptom in the UI
is an error in the chat panel when opening a chart chat.

## What the assistant may read

`CommandCenter::ChartScope` maps the chart's dataset name onto
`CommandCenter::SourceCatalog`:

- **Dataset is an approved source** (e.g. `vw_fleet_dashboard_summary`) -
  the conversation may query that one source and nothing else. A tool call
  naming any other source is rejected before it reaches the database, and
  the rejected name is not returned to the caller.
- **Dataset is not an approved source** - no query runs at all. The
  assistant explains the chart from its configuration and states that it
  cannot report figures for it, rather than inventing any.

Conversations are bound to their chart via `ai_conversations.scope_key`
(`"chart:<id>"`, or NULL for the global assistant), so a `conversation_id`
issued for one chart cannot be replayed against another chart or against
the global assistant.

## Dependencies shared with the global assistant

Chart chat reuses the existing AI stack, so it also needs:

- `GEMINI_API_KEY` (and optionally `GEMINI_MODEL`)
- the read-only Postgres role from [`ai_readonly_role.sql`](ai_readonly_role.sql),
  including the grants repeated against each environment's operations
  database (`wkcc_ops_development`, `wkcc_ops_test`, production)

The `wkcc_ops_test` grants have to be re-applied whenever the test database
is rebuilt (`db:test:prepare` drops them), and the analytical views must
exist there too:

```bash
RAILS_ENV=test bin/rails db:operations_views:apply
```

Without those, the AI specs fail with `PG::UndefinedTable` or
`PG::InsufficientPrivilege` rather than anything to do with this feature.
