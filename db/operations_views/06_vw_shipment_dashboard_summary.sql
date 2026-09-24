-- vw_shipment_dashboard_summary
-- Grain: exactly one row - network-wide shipment/delivery totals.
--
-- packages_damaged/packages_short count Package#status enum values
-- ('damaged'/'short'), NOT packages with a nonzero damaged_quantity/
-- short_quantity while in another status - those partial-damage figures
-- are summed instead in vw_hub_dashboard_summary (per hub) and are
-- available per-package in vw_shipment_dashboard.
-- promised_deliveries = count of packages that HAVE a promised_delivery_at
-- set (SLA coverage), not a count of on-time deliveries.
-- overdue_packages = promised, not yet delivered, and past the promised
-- date. delivered_late_packages = delivered, but after the promised date.
-- Both are only calculated where the underlying dates actually exist.

CREATE OR REPLACE VIEW vw_shipment_dashboard_summary AS
WITH order_agg AS (
  SELECT COUNT(*) AS total_orders FROM orders
),
package_agg AS (
  SELECT
    COUNT(*) AS total_packages,
    COUNT(*) FILTER (WHERE status = 'in_transit') AS packages_in_transit,
    COUNT(*) FILTER (WHERE status = 'delivered') AS packages_delivered,
    COUNT(*) FILTER (WHERE status = 'pending') AS packages_pending,
    COUNT(*) FILTER (WHERE status = 'damaged') AS packages_damaged,
    COUNT(*) FILTER (WHERE status = 'short') AS packages_short,
    COUNT(*) FILTER (WHERE promised_delivery_at IS NOT NULL) AS promised_deliveries,
    COUNT(*) FILTER (
      WHERE promised_delivery_at IS NOT NULL
        AND status <> 'delivered'
        AND promised_delivery_at < NOW()
    ) AS overdue_packages,
    COUNT(*) FILTER (
      WHERE delivered_at IS NOT NULL
        AND promised_delivery_at IS NOT NULL
        AND delivered_at > promised_delivery_at
    ) AS delivered_late_packages
  FROM packages
),
alert_agg AS (
  SELECT
    COUNT(*) FILTER (WHERE status = 'open') AS open_package_alerts,
    COUNT(*) FILTER (WHERE status = 'open' AND severity = 'critical') AS critical_package_alerts
  FROM alerts
  WHERE "group" = 'packages'
)
SELECT
  oa.total_orders,
  pa.total_packages,
  pa.packages_in_transit,
  pa.packages_delivered,
  pa.packages_pending,
  pa.packages_damaged,
  pa.packages_short,
  pa.promised_deliveries,
  pa.overdue_packages,
  pa.delivered_late_packages,
  aa.open_package_alerts,
  aa.critical_package_alerts
FROM order_agg oa
CROSS JOIN package_agg pa
CROSS JOIN alert_agg aa;
