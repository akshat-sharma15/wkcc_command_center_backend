-- vw_hub_dashboard_overview
-- Grain: exactly one row - network-wide hub totals.
--
-- Built directly on top of vw_hub_dashboard_summary so hub-level and
-- network-level numbers can never drift apart from separately-written
-- counting logic - this view only sums/averages what that view already
-- computed correctly per hub.
--
-- average_dwell_time_minutes / throughput_packages_scanned are exposed
-- because the underlying hub_operations_events-derived columns exist and
-- are structurally correct; both currently read NULL/0 network-wide until
-- hub event ingestion exists (see vw_hub_dashboard_summary's header
-- comment). average_dwell_time_minutes is an unweighted average across
-- hubs that have at least one GATE_IN/DEPARTED pair - not weighted by
-- vehicle volume per hub.
--
-- total_open_alerts/total_critical_alerts here are HUB-GROUP alerts only
-- (alerts WHERE group = 'hubs') - the all-group network alert count lives
-- in vw_network_health_summary instead.

CREATE OR REPLACE VIEW vw_hub_dashboard_overview AS
SELECT
  COUNT(*) AS total_hubs,
  COUNT(*) FILTER (WHERE operational_status = 'active') AS active_hubs,
  COALESCE(SUM(total_vehicles), 0) AS total_vehicles,
  COALESCE(SUM(active_vehicles), 0) AS active_vehicles,
  COALESCE(SUM(package_count), 0) AS total_packages,
  COALESCE(SUM(packages_in_transit), 0) AS packages_in_transit,
  COALESCE(SUM(backlog_packages), 0) AS total_backlog,
  COALESCE(SUM(open_alerts), 0) AS total_open_alerts,
  COALESCE(SUM(critical_alerts), 0) AS total_critical_alerts,
  ROUND(AVG(avg_dwell_time_minutes), 2) AS average_dwell_time_minutes,
  COALESCE(SUM(packages_scanned_count), 0) AS throughput_packages_scanned
FROM vw_hub_dashboard_summary;
