-- vw_fleet_dashboard_summary
-- Grain: exactly one row - network-wide fleet totals.
--
-- vehicles_on_trip = vehicles with at least one trip currently
-- status = 'in_transit'. vehicles_available = active-status vehicles with
-- no in_transit trip right now.
-- breakdown_count/route_deviation_count are all-time counts from
-- vehicle_operation_events (currently 0 in every environment - no
-- ingestion pipeline writes to that table yet; see the database-foundation
-- phase).
-- Deliberately NOT included: GPS freshness, GPS signal loss, idle %,
-- fuel consumption, odometer analytics - explicitly out of scope for the
-- Command Centre MVP.

CREATE OR REPLACE VIEW vw_fleet_dashboard_summary AS
WITH vehicle_flags AS (
  SELECT
    v.id,
    v.status,
    v.mileage_km,
    v.fuel_efficiency_kmpl,
    EXISTS (
      SELECT 1 FROM trips t WHERE t.vehicle_id = v.id AND t.status = 'in_transit'
    ) AS on_trip
  FROM vehicles v
),
vehicle_agg AS (
  SELECT
    COUNT(*) AS total_vehicles,
    COUNT(*) FILTER (WHERE status = 'active') AS active_vehicles,
    COUNT(*) FILTER (WHERE status <> 'active') AS inactive_vehicles,
    COUNT(*) FILTER (WHERE on_trip) AS vehicles_on_trip,
    COUNT(*) FILTER (WHERE status = 'active' AND NOT on_trip) AS vehicles_available,
    ROUND(AVG(mileage_km), 2) AS average_mileage_km,
    ROUND(AVG(fuel_efficiency_kmpl), 2) AS average_fuel_efficiency_kmpl
  FROM vehicle_flags
),
trip_agg AS (
  SELECT
    COUNT(*) FILTER (WHERE status = 'in_transit') AS active_trips,
    COUNT(*) FILTER (WHERE status = 'delayed') AS delayed_trips,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_trips
  FROM trips
),
event_agg AS (
  SELECT
    COUNT(*) FILTER (WHERE event_type = 'BREAKDOWN') AS breakdown_count,
    COUNT(*) FILTER (WHERE event_type = 'ROUTE_DEVIATION') AS route_deviation_count
  FROM vehicle_operation_events
)
SELECT
  va.total_vehicles,
  va.active_vehicles,
  va.inactive_vehicles,
  va.vehicles_on_trip,
  va.vehicles_available,
  va.average_mileage_km,
  va.average_fuel_efficiency_kmpl,
  ta.active_trips,
  ta.delayed_trips,
  ta.completed_trips,
  ea.breakdown_count,
  ea.route_deviation_count
FROM vehicle_agg va
CROSS JOIN trip_agg ta
CROSS JOIN event_agg ea;
