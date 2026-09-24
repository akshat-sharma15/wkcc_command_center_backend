-- vw_shipment_dashboard
-- Grain: one row per package (packages.id).
--
-- promised_delivery_at = the package's own promise if set, else falls
-- back to its order's promise (COALESCE) - a documented fallback, not a
-- fabricated value.
-- location_name resolves from whichever of hubs/warehouses actually
-- matches packages.location_type/location_id (Package's existing
-- polymorphic location - untouched).
-- latest_status_transition_at is populated only once at least one status
-- change has been recorded in package_status_transitions (written by
-- Package#record_status_transition going forward - not backfilled for
-- history predating this phase).

CREATE OR REPLACE VIEW vw_shipment_dashboard AS
WITH package_alert_agg AS (
  SELECT
    record_id AS package_id,
    COUNT(*) FILTER (WHERE status = 'open') AS open_alert_count,
    COUNT(*) FILTER (WHERE status = 'open' AND severity = 'critical') AS critical_alert_count
  FROM alerts
  WHERE "group" = 'packages'
  GROUP BY record_id
),
package_transition_agg AS (
  SELECT
    package_id,
    MAX(occurred_at) AS latest_status_transition_at
  FROM package_status_transitions
  GROUP BY package_id
)
SELECT
  p.id AS package_id,
  p.identifier AS package_identifier,
  p.status AS package_status,
  p.expected_quantity,
  p.received_quantity,
  p.damaged_quantity,
  p.short_quantity,
  COALESCE(p.promised_delivery_at, o.promised_delivery_at) AS promised_delivery_at,
  p.delivered_at,
  p.location_id,
  p.location_type,
  COALESCE(lh.name, lw.name) AS location_name,
  o.id AS order_id,
  o.order_number,
  o.customer_reference,
  o.status AS order_status,
  t.id AS trip_id,
  t.vehicle_id,
  v.number AS vehicle_number,
  oh.name AS origin_hub,
  dh.name AS destination_hub,
  t.status AS trip_status,
  COALESCE(paa.open_alert_count, 0) AS open_alert_count,
  COALESCE(paa.critical_alert_count, 0) AS critical_alert_count,
  pta.latest_status_transition_at
FROM packages p
LEFT JOIN orders o ON o.id = p.order_id
LEFT JOIN hubs lh ON p.location_type = 'Hub' AND lh.id = p.location_id
LEFT JOIN warehouses lw ON p.location_type = 'Warehouse' AND lw.id = p.location_id
LEFT JOIN trips t ON t.id = p.trip_id
LEFT JOIN vehicles v ON v.id = t.vehicle_id
LEFT JOIN hubs oh ON oh.id = t.origin_hub_id
LEFT JOIN hubs dh ON dh.id = t.destination_hub_id
LEFT JOIN package_alert_agg paa ON paa.package_id = p.id
LEFT JOIN package_transition_agg pta ON pta.package_id = p.id;
