-- vw_hub_dashboard_summary
-- Grain: one row per hub (hubs.id).
--
-- Data sources actually used: hubs, vehicles, trips, packages, alerts,
-- hub_operations_events. hub_operations_events currently has zero rows in
-- every environment (no event-ingestion pipeline has been built yet - the
-- database-foundation phase only created the table), so every column
-- derived from it (inbound/outbound/processed/dispatch_ready counts,
-- packages_scanned_count, avg_dwell_time_minutes) is structurally correct
-- SQL that reads 0/NULL until something starts writing rows there. That
-- is real data, not a bug - the columns are ready for when hub scanning
-- operations start logging events.
--
-- Deliberately NOT included (insufficient/nonexistent source data):
--   dock utilisation, bay utilisation, labour productivity,
--   sorting accuracy, misroute rate, P95 dwell time.
-- dock_reference/bay_reference exist as free-text columns on
-- hub_operations_events, but there is no dock/bay capacity table to
-- divide an occupied count by, so a "utilisation" percentage cannot be
-- computed - only a raw event count could be, and it isn't requested here.
--
-- avg_vehicle_turnaround_minutes uses TRIP data (already populated today),
-- distinct from avg_dwell_time_minutes which uses HUB EVENT data (not
-- populated yet): turnaround = time between a vehicle's arrival at this
-- hub (trips.actual_arrival_at, destination_hub_id = this hub) and its
-- immediately-following departure from this hub (trips.departure_at,
-- origin_hub_id = this hub) - a real signal today, not proxied from
-- anything else.
--
-- backlog_packages is a named definition, not a native Package#status
-- value: packages physically at this hub with status IN ('pending',
-- 'received') - i.e. intake has not yet moved them into transit or
-- delivered them.

CREATE OR REPLACE VIEW vw_hub_dashboard_summary AS
WITH vehicle_agg AS (
  SELECT
    hub_id,
    COUNT(*) AS total_vehicles,
    COUNT(*) FILTER (WHERE status = 'active') AS active_vehicles
  FROM vehicles
  GROUP BY hub_id
),
trip_touches AS (
  SELECT origin_hub_id AS hub_id, status FROM trips
  UNION ALL
  SELECT destination_hub_id AS hub_id, status FROM trips
),
trip_agg AS (
  SELECT
    hub_id,
    COUNT(*) FILTER (WHERE status = 'in_transit') AS active_trips,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_trips,
    COUNT(*) FILTER (WHERE status = 'delayed') AS delayed_trips
  FROM trip_touches
  GROUP BY hub_id
),
package_agg AS (
  SELECT
    location_id AS hub_id,
    COUNT(*) AS package_count,
    COUNT(*) FILTER (WHERE status = 'in_transit') AS packages_in_transit,
    COUNT(*) FILTER (WHERE status = 'delivered') AS delivered_packages,
    COUNT(*) FILTER (WHERE status IN ('pending', 'received')) AS backlog_packages,
    COALESCE(SUM(damaged_quantity), 0) AS damaged_quantity,
    COALESCE(SUM(short_quantity), 0) AS short_quantity
  FROM packages
  WHERE location_type = 'Hub'
  GROUP BY location_id
),
hub_event_agg AS (
  SELECT
    hub_id,
    COUNT(*) FILTER (WHERE event_type = 'GATE_IN') AS inbound_vehicle_count,
    COUNT(*) FILTER (WHERE event_type = 'DEPARTED') AS outbound_vehicle_count,
    COUNT(*) FILTER (WHERE event_type IN ('SCANNED', 'SORTED')) AS processed_event_count,
    COUNT(*) FILTER (WHERE event_type = 'DISPATCH_READY') AS dispatch_ready_count,
    COUNT(DISTINCT package_id) FILTER (WHERE event_type = 'SCANNED') AS packages_scanned_count
  FROM hub_operations_events
  GROUP BY hub_id
),
dwell_pairs AS (
  SELECT
    hub_id,
    vehicle_id,
    event_type,
    occurred_at,
    LEAD(event_type) OVER (PARTITION BY hub_id, vehicle_id ORDER BY occurred_at) AS next_event_type,
    LEAD(occurred_at) OVER (PARTITION BY hub_id, vehicle_id ORDER BY occurred_at) AS next_occurred_at
  FROM hub_operations_events
  WHERE vehicle_id IS NOT NULL AND event_type IN ('GATE_IN', 'DEPARTED')
),
dwell_agg AS (
  SELECT
    hub_id,
    ROUND(AVG(EXTRACT(EPOCH FROM (next_occurred_at - occurred_at)) / 60.0)::numeric, 2) AS avg_dwell_time_minutes
  FROM dwell_pairs
  WHERE event_type = 'GATE_IN' AND next_event_type = 'DEPARTED'
  GROUP BY hub_id
),
trip_touch_events AS (
  SELECT vehicle_id, destination_hub_id AS hub_id, actual_arrival_at AS touched_at, 'arrival' AS touch_type
  FROM trips
  WHERE actual_arrival_at IS NOT NULL
  UNION ALL
  SELECT vehicle_id, origin_hub_id AS hub_id, departure_at AS touched_at, 'departure' AS touch_type
  FROM trips
  WHERE departure_at IS NOT NULL
),
turnaround_pairs AS (
  SELECT
    hub_id,
    vehicle_id,
    touch_type,
    touched_at,
    LEAD(touch_type) OVER (PARTITION BY hub_id, vehicle_id ORDER BY touched_at) AS next_touch_type,
    LEAD(touched_at) OVER (PARTITION BY hub_id, vehicle_id ORDER BY touched_at) AS next_touched_at
  FROM trip_touch_events
),
turnaround_agg AS (
  SELECT
    hub_id,
    ROUND(AVG(EXTRACT(EPOCH FROM (next_touched_at - touched_at)) / 60.0)::numeric, 2) AS avg_vehicle_turnaround_minutes
  FROM turnaround_pairs
  WHERE touch_type = 'arrival' AND next_touch_type = 'departure'
  GROUP BY hub_id
),
alert_agg AS (
  SELECT
    record_id AS hub_id,
    COUNT(*) FILTER (WHERE status = 'open') AS open_alerts,
    COUNT(*) FILTER (WHERE status = 'open' AND severity = 'critical') AS critical_alerts
  FROM alerts
  WHERE "group" = 'hubs'
  GROUP BY record_id
)
SELECT
  h.id AS hub_id,
  h.code AS hub_code,
  h.name AS hub_name,
  h.location,
  h.operational_status,
  h.capacity,
  h.parking_capacity,
  h.available_parking,
  ROUND(
    ((h.parking_capacity - h.available_parking)::numeric / NULLIF(h.parking_capacity, 0)) * 100,
    2
  ) AS parking_utilisation_pct,
  COALESCE(va.total_vehicles, 0) AS total_vehicles,
  COALESCE(va.active_vehicles, 0) AS active_vehicles,
  COALESCE(he.inbound_vehicle_count, 0) AS inbound_vehicle_count,
  COALESCE(he.outbound_vehicle_count, 0) AS outbound_vehicle_count,
  COALESCE(ta.active_trips, 0) AS active_trips,
  COALESCE(ta.completed_trips, 0) AS completed_trips,
  COALESCE(ta.delayed_trips, 0) AS delayed_trips,
  COALESCE(pa.package_count, 0) AS package_count,
  COALESCE(pa.packages_in_transit, 0) AS packages_in_transit,
  COALESCE(pa.delivered_packages, 0) AS delivered_packages,
  COALESCE(pa.backlog_packages, 0) AS backlog_packages,
  COALESCE(pa.damaged_quantity, 0) AS damaged_quantity,
  COALESCE(pa.short_quantity, 0) AS short_quantity,
  COALESCE(he.processed_event_count, 0) AS processed_event_count,
  COALESCE(he.dispatch_ready_count, 0) AS dispatch_ready_count,
  COALESCE(he.packages_scanned_count, 0) AS packages_scanned_count,
  da.avg_dwell_time_minutes,
  tr.avg_vehicle_turnaround_minutes,
  COALESCE(aa.open_alerts, 0) AS open_alerts,
  COALESCE(aa.critical_alerts, 0) AS critical_alerts
FROM hubs h
LEFT JOIN vehicle_agg va ON va.hub_id = h.id
LEFT JOIN trip_agg ta ON ta.hub_id = h.id
LEFT JOIN package_agg pa ON pa.hub_id = h.id
LEFT JOIN hub_event_agg he ON he.hub_id = h.id
LEFT JOIN dwell_agg da ON da.hub_id = h.id
LEFT JOIN turnaround_agg tr ON tr.hub_id = h.id
LEFT JOIN alert_agg aa ON aa.hub_id = h.id;
