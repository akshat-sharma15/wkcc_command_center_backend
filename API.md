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

Create/update requests wrap params under the singular resource key, e.g.:

```json
POST /api/v1/vehicles
{ "vehicle": { "number": "VH-1023", "vehicle_type": "truck", "hub_id": 1 } }
```

Events live in the `command_center` database, independent of the
`operations` database resources above, with no foreign key into them (see
`ARCHITECTURE.md`). `AlertRule`/`Alert` live in the `operations` database
but have no API yet (see "Alerts — no API yet" below).

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

`204 No Content` on success.

## Alerts — no API yet

The `Alert`/`AlertRule` system was reworked (alert-system refactor Phase
1): alerts are no longer tied to `EventDefinition` at all. `AlertRule` and
`Alert` now live in the `operations` database and target five alertable
business models (`Vehicle`, `Hub`, `Package`, `PaymentDue`,
`WorkforceMember`) directly by field/operator/value — see
`ARCHITECTURE.md`. Phase 1 is data-layer only (migrations, models,
validations); there is intentionally no `/api/v1/alerts` or
`/api/v1/alert_rules` route yet. The old `EventDefinition`-based `Alert`
API documented in earlier revisions of this file has been removed along
with its implementation.

## Postman

1. Create an environment with `base_url = http://localhost:3001`. No
   Authorization setup is needed — authentication is currently disabled
   (see top of this document).
2. Example: `POST {{base_url}}/api/v1/events` — body as shown above.

## Not yet implemented (Stage 4+)

- `POST /api/v1/events/occurrences` (generic event ingestion, distinct from
  the `EventDefinition` CRUD above)
- `/api/v1/alert_rules`, `/api/v1/alerts` (AlertRule/Alert exist in the
  operations DB as of Phase 1, but have no API yet — no triggering logic
  exists either)
- `GET /api/v1/events/stream` (SSE)
- `/api/v1/integrations` (Slack/SMS/WhatsApp/Email) and the `integration`
  field on `Alert`
- `/api/v1/notifications`
- `GET /api/v1/superset/roles`, `GET /api/v1/superset/users`

See `ARCHITECTURE.md` for the intended shape of each.
