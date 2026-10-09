-- vw_route_dashboard
-- Grain: one row per trip (trips.id). Trip remains the route/trip source
-- - no separate routes table exists or was created.
--
-- trip_duration_minutes is only populated once both departure_at and
-- actual_arrival_at exist (i.e. the trip has actually completed its
-- movement). eta_variance_minutes is only populated once actual_arrival_at
-- exists, per the "only calculate ETA variance if the timestamps support
-- it" rule - positive means later than expected, negative means earlier.
-- breakdown_count/route_deviation_count are scoped to THIS trip
-- (vehicle_operation_events.trip_id), not the vehicle's lifetime.

CREATE OR REPLACE VIEW vw_route_dashboard AS
WITH trip_package_agg AS (
  SELECT
    trip_id,
    COUNT(*) AS package_count,
    COUNT(DISTINCT order_id) AS order_count
  FROM packages
  WHERE trip_id IS NOT NULL
  GROUP BY trip_id
),
trip_event_agg AS (
  SELECT
    trip_id,
    COUNT(*) FILTER (WHERE event_type = 'BREAKDOWN') AS breakdown_count,
    COUNT(*) FILTER (WHERE event_type = 'ROUTE_DEVIATION') AS route_deviation_count
  FROM vehicle_operation_events
  WHERE trip_id IS NOT NULL
  GROUP BY trip_id
)
SELECT
  t.id AS trip_id,
  t.vehicle_id,
  v.number AS vehicle_number,
  t.origin_hub_id,
  oh.name AS origin_hub,
  t.destination_hub_id,
  dh.name AS destination_hub,
  t.status,
  t.departure_at,
  t.expected_arrival_at,
  t.actual_arrival_at,
  CASE
    WHEN t.departure_at IS NOT NULL AND t.actual_arrival_at IS NOT NULL
      THEN ROUND((EXTRACT(EPOCH FROM (t.actual_arrival_at - t.departure_at)) / 60.0)::numeric, 2)
  END AS trip_duration_minutes,
  CASE
    WHEN t.actual_arrival_at IS NOT NULL AND t.expected_arrival_at IS NOT NULL
      THEN ROUND((EXTRACT(EPOCH FROM (t.actual_arrival_at - t.expected_arrival_at)) / 60.0)::numeric, 2)
  END AS eta_variance_minutes,
  COALESCE(tpa.package_count, 0) AS package_count,
  COALESCE(tpa.order_count, 0) AS order_count,
  COALESCE(tea.breakdown_count, 0) AS breakdown_count,
  COALESCE(tea.route_deviation_count, 0) AS route_deviation_count,
  oh.code AS origin_hub_code,
  dh.code AS destination_hub_code,
  ol.city AS origin_city,
  ol.state AS origin_state,
  dl.city AS destination_city,
  dl.state AS destination_state,
  v.status AS vehicle_status
FROM trips t
LEFT JOIN vehicles v ON v.id = t.vehicle_id
LEFT JOIN hubs oh ON oh.id = t.origin_hub_id
LEFT JOIN hubs dh ON dh.id = t.destination_hub_id
LEFT JOIN locations ol ON ol.id = oh.location_id
LEFT JOIN locations dl ON dl.id = dh.location_id
LEFT JOIN trip_package_agg tpa ON tpa.trip_id = t.id
LEFT JOIN trip_event_agg tea ON tea.trip_id = t.id
-- Only the map's trucks (vehicles.fleet_monitoring_poc = true), so the AI reports on
-- exactly the fleet the map shows. Nothing is deleted; rows are just not exposed here.
WHERE v.fleet_monitoring_poc = true;
