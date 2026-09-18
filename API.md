# API Reference (Stage 1 + Stage 2)

Base URL: `http://localhost:3001` (or `$PORT`).

All `/api/v1/*` endpoints except `GET /api/v1/health` require:

```
Authorization: Bearer <token>
```

See `README.md` for how to issue a token. An invalid or missing token
returns `401 Unauthorized`.

## Errors

| Status | When |
|---|---|
| 400 | A required top-level param (e.g. `vehicle`) is missing |
| 401 | Missing/invalid bearer token |
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

All seven follow the same RESTful shape:

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

Create/update requests wrap params under the singular resource key, e.g.:

```json
POST /api/v1/vehicles
{ "vehicle": { "number": "VH-1023", "vehicle_type": "truck", "hub_id": 1 } }
```

## Not yet implemented (Stage 3+)

- `POST /api/v1/events` (generic event ingestion)
- `/api/v1/event_definitions`
- `GET /api/v1/events/stream` (SSE)
- `/api/v1/alerts`, `/api/v1/integrations`, `/api/v1/notifications`

See `ARCHITECTURE.md` for the intended shape of each.
