-- vw_network_health_summary
-- Grain: exactly one row - a trusted network snapshot. NOT a weighted
-- health-score engine - scoring is explicitly deferred out of this phase.
--
-- open_alerts/critical_alerts here are ACROSS ALL alert groups (vehicles,
-- hubs, packages, payments, workforce, and any event-mode alerts) -
-- broader than the hub-only figures in vw_hub_dashboard_overview and the
-- package-only figures in vw_shipment_dashboard_summary.
-- Built on top of vw_hub_dashboard_overview, vw_fleet_dashboard_summary,
-- and vw_shipment_dashboard_summary so these numbers can never drift from
-- the per-domain views - only the all-group alert totals are computed
-- fresh here.

CREATE OR REPLACE VIEW vw_network_health_summary AS
WITH alert_agg AS (
  SELECT
    COUNT(*) FILTER (WHERE status = 'open') AS open_alerts,
    COUNT(*) FILTER (WHERE status = 'open' AND severity = 'critical') AS critical_alerts
  FROM alerts
)
SELECT
  ho.total_hubs,
  ho.active_hubs,
  fs.total_vehicles,
  fs.active_vehicles,
  fs.vehicles_on_trip,
  fs.active_trips,
  fs.delayed_trips,
  ss.total_orders,
  ss.total_packages,
  ss.packages_in_transit,
  ss.packages_delivered AS delivered_packages,
  aa.open_alerts,
  aa.critical_alerts,
  fs.average_fuel_efficiency_kmpl,
  fs.average_mileage_km
FROM vw_hub_dashboard_overview ho
CROSS JOIN vw_fleet_dashboard_summary fs
CROSS JOIN vw_shipment_dashboard_summary ss
CROSS JOIN alert_agg aa;
