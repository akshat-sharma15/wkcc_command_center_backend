-- vw_vehicle_dashboard
-- Grain: one row per vehicle (vehicles.id).
--
-- "Current trip" = the vehicle's in_transit trip, if one exists (picking
-- the most recently departed if more than one, which should not normally
-- happen). A vehicle with no in_transit trip shows NULL trip columns
-- rather than falling back to a stale completed trip, to avoid implying a
-- trip is "current" when it is not.
-- package_count/order_count follow vehicle -> current trip -> packages
-- (the Fleet MVP relationship chain) - not every package this vehicle has
-- ever carried, only the ones on its current trip. No new VehiclePackage
-- table was created.
-- Driver fields are limited to WorkforceMember's own existing columns
-- (identifier, name) - nothing else is stored about drivers.

CREATE OR REPLACE VIEW vw_vehicle_dashboard AS
WITH current_trip AS (
  SELECT DISTINCT ON (t.vehicle_id)
    t.vehicle_id,
    t.id AS trip_id,
    t.origin_hub_id,
    t.destination_hub_id,
    t.departure_at,
    t.expected_arrival_at,
    t.actual_arrival_at,
    t.status AS trip_status
  FROM trips t
  WHERE t.status = 'in_transit'
  ORDER BY t.vehicle_id, t.departure_at DESC
),
current_trip_packages AS (
  SELECT
    ct.vehicle_id,
    COUNT(p.id) AS package_count,
    COUNT(DISTINCT p.order_id) AS order_count
  FROM current_trip ct
  LEFT JOIN packages p ON p.trip_id = ct.trip_id
  GROUP BY ct.vehicle_id
),
vehicle_event_agg AS (
  SELECT
    vehicle_id,
    COUNT(*) FILTER (WHERE event_type = 'BREAKDOWN') AS breakdown_count,
    COUNT(*) FILTER (WHERE event_type = 'ROUTE_DEVIATION') AS route_deviation_count
  FROM vehicle_operation_events
  GROUP BY vehicle_id
),
vehicle_alert_agg AS (
  SELECT
    record_id AS vehicle_id,
    COUNT(*) FILTER (WHERE status = 'open') AS open_alert_count,
    COUNT(*) FILTER (WHERE status = 'open' AND severity = 'critical') AS critical_alert_count
  FROM alerts
  WHERE "group" = 'vehicles'
  GROUP BY record_id
)
SELECT
  v.id AS vehicle_id,
  v.number AS vehicle_number,
  v.vehicle_type,
  v.vendor,
  v.status,
  v.current_location,
  v.last_known_latitude,
  v.last_known_longitude,
  v.last_location_at,
  v.capacity,
  v.mileage_km,
  v.fuel_efficiency_kmpl,
  h.id AS hub_id,
  h.code AS hub_code,
  h.name AS hub_name,
  wm.id AS driver_id,
  wm.identifier AS driver_identifier,
  wm.name AS driver_name,
  ct.trip_id,
  ct.origin_hub_id,
  oh.name AS origin_hub,
  ct.destination_hub_id,
  dh.name AS destination_hub,
  ct.departure_at,
  ct.expected_arrival_at,
  ct.actual_arrival_at,
  ct.trip_status,
  COALESCE(ctp.package_count, 0) AS package_count,
  COALESCE(ctp.order_count, 0) AS order_count,
  COALESCE(vea.breakdown_count, 0) AS breakdown_count,
  COALESCE(vea.route_deviation_count, 0) AS route_deviation_count,
  COALESCE(vaa.open_alert_count, 0) AS open_alert_count,
  COALESCE(vaa.critical_alert_count, 0) AS critical_alert_count
FROM vehicles v
LEFT JOIN hubs h ON h.id = v.hub_id
LEFT JOIN workforce_members wm ON wm.id = v.driver_id
LEFT JOIN current_trip ct ON ct.vehicle_id = v.id
LEFT JOIN hubs oh ON oh.id = ct.origin_hub_id
LEFT JOIN hubs dh ON dh.id = ct.destination_hub_id
LEFT JOIN current_trip_packages ctp ON ctp.vehicle_id = v.id
LEFT JOIN vehicle_event_agg vea ON vea.vehicle_id = v.id
LEFT JOIN vehicle_alert_agg vaa ON vaa.vehicle_id = v.id;
