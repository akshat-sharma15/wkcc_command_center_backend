# API Reference (Stage 1 + Stage 2 + Stage 3)

Base URL: `http://localhost:3001` (or `$PORT`).

**Authentication is currently disabled on every `/api/v1/*` endpoint** (by
explicit request, to simplify local/Postman testing while this API is
still taking shape). No `Authorization` header is required for any
request below. The bearer-token mechanism (`ApiClient`, `Authorization:
Bearer <token>`) is still fully implemented and can be re-enabled with a
one-line change in `Api::V1::BaseController` — see `ARCHITECTURE.md`.

## Errors

| Status | When |
|---|---|
| 400 | A required top-level param (e.g. `vehicle`) is missing |
| 404 | Record not found |
| 422 | Validation failed — body: `{ "error": ["..."] }` |
| 500 | Unhandled server error — body: `{ "error": "Internal server error" }` |

## Health

```
GET /api/v1/health
```
Unauthenticated. Touches both `operations` and `command_center` database
connections and enqueues a Sidekiq proof-of-life job.

## Resources

All nine follow the same RESTful shape:

```
GET    /api/v1/<resource>          index, paginated (Pagy; X-Page/X-Pages/X-Count headers)
GET    /api/v1/<resource>/:id      show
POST   /api/v1/<resource>          create
PATCH  /api/v1/<resource>/:id      update
DELETE /api/v1/<resource>/:id      destroy -> 204
```

| Resource | Path | Model | Key fields |
|---|---|---|---|
| Vehicles | `/api/v1/vehicles` | `Vehicle` | `number` (unique), `vehicle_type`, `status` (active/maintenance/out_of_service), `capacity`, `vendor`, `current_location`, `hub_id`, `driver_id` (optional, → WorkforceMember) |
| Trips | `/api/v1/trips` | `Trip` | `vehicle_id`, `origin_hub_id`, `destination_hub_id` (must differ), `departure_at`, `expected_arrival_at`, `actual_arrival_at`, `status` (scheduled/in_transit/completed/cancelled/delayed), `route_info` |
| Hubs | `/api/v1/hubs` | `Hub` | `name`, `code` (unique), `location`, `capacity`, `parking_capacity`, `available_parking`, `operational_status` (active/degraded/closed) |
| Warehouses | `/api/v1/warehouses` | `Warehouse` | `name`, `code` (unique), `location`, `capacity`, `status` (active/inactive/closed) |
| Packages | `/api/v1/packages` | `Package` | `identifier` (unique), `trip_id` (optional), `location_type`+`location_id` (polymorphic: `Warehouse` or `Hub`), `expected_quantity`, `received_quantity`, `damaged_quantity`, `short_quantity`, `status` (pending/in_transit/received/damaged/short/delivered) |
| Finance | `/api/v1/finance` | `PaymentDue` | `vendor`, `amount`, `due_date`, `payment_status` (pending/paid/overdue); response includes derived `aging_days` (not stored) |
| Workforce | `/api/v1/workforce_members` | `WorkforceMember` | `identifier` (unique), `name`, `role_type` (guard/warehouse_worker/loader/supervisor/driver/other_staff), `hub_id`, `shift`, `attendance_status` (present/absent/on_leave) |
| Events | `/api/v1/events` | `EventDefinition` | `name` (unique), `group`, `type` — see [Event groups/types](#event-groups-and-types) for the fixed vocabulary |
| Alerts | `/api/v1/alerts` | `Alert` | `name`, `event_id` (→ `EventDefinition`), `role`, `description` |

Create/update requests wrap params under the singular resource key, e.g.:

```json
POST /api/v1/vehicles
{ "vehicle": { "number": "VH-1023", "vehicle_type": "truck", "hub_id": 1 } }
```

Events and Alerts live in the `command_center` database, are independent of
the `operations` database resources above, and carry no foreign key into
them (see `ARCHITECTURE.md`).

## Events API

`EventDefinition` records are configurable event *types* the Command Center
can raise alerts against (e.g. "Accident" under the "Fleet / Transport"
group) — not operational models. `group` and `type` must be one of a fixed,
server-validated vocabulary.

### Event groups and types

| Group | Types |
|---|---|
| `Hubs` | `Inbound Truck`, `Outbound Truck`, `Parking Space`, `Capacity` |
| `Fleet / Transport` | `Failure of Truck with Goods Damaged`, `Need Vehicle Replacement`, `Route Diversion`, `Cancel Departure`, `Accident` |
| `Workforce` | `Shift Change`, `Low Attendance` |
| `Sales` | `Low Inbound Calls`, `Low Outbound Calls` |
| `Finance` | `Payment Dues` |

A `type` that isn't listed under the given `group` is rejected with `422`
(e.g. `group: "Hubs", type: "Accident"` fails — `Accident` only belongs to
`Fleet / Transport`).

### `GET /api/v1/events`

Paginated list, newest first.

```bash
curl -s http://localhost:3001/api/v1/events
```

```json
[
  {
    "id": 1,
    "name": "Truck Accident",
    "group": "Fleet / Transport",
    "type": "Accident",
    "created_at": "2026-09-18T14:00:00.000Z",
    "updated_at": "2026-09-18T14:00:00.000Z"
  }
]
```

### `GET /api/v1/events/:id`

```bash
curl -s http://localhost:3001/api/v1/events/1
```

Response: same shape as one list item. `404` with
`{ "error": "Couldn't find EventDefinition with 'id'=999" }` if not found.

### `POST /api/v1/events`

```bash
curl -s -X POST http://localhost:3001/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
        "event": {
          "name": "Truck Accident",
          "group": "Fleet / Transport",
          "type": "Accident"
        }
      }'
```

`201 Created` with the created record. Validation errors return `422`:

```json
// group/type mismatch
{ "error": ["Event type 'Accident' is not valid for group 'Hubs'"] }

// duplicate name
{ "error": ["Name has already been taken"] }

// unknown group
{ "error": ["Group is not included in the list"] }
```

### `PATCH /api/v1/events/:id`

Same body shape as create; any subset of `name`/`group`/`type`.

```bash
curl -s -X PATCH http://localhost:3001/api/v1/events/1 \
  -H "Content-Type: application/json" \
  -d '{ "event": { "name": "Critical Truck Accident" } }'
```

### `DELETE /api/v1/events/:id`

```bash
curl -s -X DELETE http://localhost:3001/api/v1/events/1
```

`204 No Content` on success. `422` if any `Alert` still references this
event definition:

```json
{ "error": ["Cannot delete record because dependent alerts exist"] }
```

## Alerts API

An `Alert` binds an `EventDefinition` to a role that should be notified,
with no integration/delivery channel yet (added in a later stage).

### `GET /api/v1/alerts`

```bash
curl -s http://localhost:3001/api/v1/alerts
```

```json
[
  {
    "id": 1,
    "name": "Critical Truck Accident",
    "role": "Logistics Manager",
    "description": "Notify logistics users when a truck failure results in damaged goods.",
    "event": {
      "id": 1,
      "name": "Truck Accident",
      "group": "Fleet / Transport",
      "type": "Accident"
    },
    "created_at": "2026-09-18T14:05:00.000Z",
    "updated_at": "2026-09-18T14:05:00.000Z"
  }
]
```

### `GET /api/v1/alerts/:id`

```bash
curl -s http://localhost:3001/api/v1/alerts/1
```

Response: same shape as one list item. `404` if not found.

### `POST /api/v1/alerts`

`event_id` must reference an existing `EventDefinition` (created via the
Events API above). `role` is currently a free-text string — see
[Deferred: Superset role lookup](ARCHITECTURE.md#deferred-read-only-superset-identity-lookup)
for how it will later be validated against live Superset roles.

```bash
curl -s -X POST http://localhost:3001/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '{
        "alert": {
          "name": "Critical Truck Accident",
          "event_id": 1,
          "role": "Logistics Manager",
          "description": "Notify logistics users when a truck failure results in damaged goods."
        }
      }'
```

`201 Created` with the created record (nested `event` object as shown
above). Validation errors return `422`:

```json
// missing/invalid event_id
{ "error": ["Event definition must exist"] }

// missing required field
{ "error": ["Role can't be blank", "Description can't be blank"] }
```

### `PATCH /api/v1/alerts/:id`

Same body shape as create; any subset of `name`/`event_id`/`role`/`description`.

```bash
curl -s -X PATCH http://localhost:3001/api/v1/alerts/1 \
  -H "Content-Type: application/json" \
  -d '{ "alert": { "role": "Fleet Supervisor" } }'
```

### `DELETE /api/v1/alerts/:id`

```bash
curl -s -X DELETE http://localhost:3001/api/v1/alerts/1
```

`204 No Content` on success. Deleting an alert never blocks — only
deleting an `EventDefinition` still referenced by an alert does.

## Postman

1. Create an environment with `base_url = http://localhost:3001`. No
   Authorization setup is needed — authentication is currently disabled
   (see top of this document).
2. Example request chain to exercise the full Event → Alert flow:
   - `POST {{base_url}}/api/v1/events` — body as shown above; save the
     response `id` to a collection variable `event_id`
     (Tests tab: `pm.collectionVariables.set("event_id", pm.response.json().id);`).
   - `POST {{base_url}}/api/v1/alerts` — body `{ "alert": { "name": "...",
     "event_id": {{event_id}}, "role": "...", "description": "..." } }`.
   - `GET {{base_url}}/api/v1/alerts` — confirm the created alert is listed.
   - `DELETE {{base_url}}/api/v1/events/{{event_id}}` — confirm this
     returns `422` while the alert still exists, then delete the alert
     first and retry.

## Not yet implemented (Stage 4+)

- `POST /api/v1/events/occurrences` (generic event ingestion, distinct from
  the `EventDefinition` CRUD above)
- `GET /api/v1/events/stream` (SSE)
- `/api/v1/integrations` (Slack/SMS/WhatsApp/Email) and the `integration`
  field on `Alert`
- `/api/v1/notifications`
- `GET /api/v1/superset/roles`, `GET /api/v1/superset/users`

See `ARCHITECTURE.md` for the intended shape of each.
