# Alert & Notification System - Test Scripts

All test scripts for the Command Center alert and notification system.

## Quick Start — One-Shot End-to-End Test (Demo Mode)

```bash
cd /Users/mac/wkcc_command_center_backend

# Single script: checks integrations, owns a fixed set of clearly-named
# "Demo: ..." AlertRules covering real business conditions (Hub parking,
# vehicle status, package damage, overdue payments, workforce absence,
# and 3 incident events), rotates to a fresh scenario each run against a
# random real record, and verifies the notification lands in both in_app
# and Slack.
rails runner scripts/alerts/00_integration_end_to_end.rb
```

This is the fastest way to prove the whole pipeline (integrations →
AlertRule → Alert → Notification → in_app/Slack delivery) works in one
command — and it is built for repeated use in front of a client: every run
produces a **different, realistically-named alert** (never the same
generic test twice in a row) naming a **real hub/vehicle/package/etc.**,
and it restores the record afterward so the demo data stays clean.

For the individual, more granular scripts, see below.

## Test Scripts

### 0. Full Integration Test — One Script Does It All (Demo Mode, ~30s)
```bash
rails runner scripts/alerts/00_integration_end_to_end.rb
```
- Verifies DB, Redis, Superset, and Slack integrations
- Idempotently creates/repairs 8 demo AlertRules with real, presentable
  names (e.g. "Demo: Hub Parking Capacity Critical", "Demo: Vehicle Out of
  Service", "Demo: Customer SLA Breach Incident") — never a "test 455"-style
  placeholder name, so the notification title/body are always meaningful
- **Rotates** to the next scenario in the list each run (based on the most
  recently triggered demo alert), so back-to-back demo runs never repeat
- Picks a random real record each run (a real hub, vehicle, package,
  payment, or workforce member) so the message text always names something
  real, e.g. "Hub Bhopal North Hub has available parking 2."
- Waits for the Alert, then the Notifications, then delivery
- Prints the exact title/message text that lands in NotificationBell + Slack
- Restores the record's original value afterward (auto-resolves the alert)
- Reports in_app + Slack delivery status with clear pass/fail reasoning,
  including a specific fix (`/invite @bot` or reconnect Slack) if Slack
  fails with `not_in_channel`
- Safe to re-run back-to-back (fully idempotent)

### 1. Health Check (30 seconds)
```bash
rails runner scripts/alerts/01_health_check.rb
```
- Verifies all systems operational
- Reports incident counts
- Shows soft-deleted rule count
- Tests database, Redis, Superset, Slack

### 2. Condition Alerts Test (2-3 minutes)
```bash
rails runner scripts/alerts/02_test_condition_alerts.rb
```
- Uses existing AlertRule #21
- Creates 5+ condition-based alerts
- Generates 10+ notifications
- Tests alert lifecycle: create → resolve

### 3. Setup Event Definitions (15 seconds)
```bash
rails runner scripts/alerts/03_setup_event_definitions.rb
```
- Creates 6 predefined incident definitions
- Safe to re-run (idempotent)
- Run once per environment

### 4. Event Alerts Test (1 minute)
```bash
rails runner scripts/alerts/04_test_event_alerts.rb
```
- Publishes sample events
- Creates event-triggered alerts
- Tests full notification pipeline
- Requires existing event AlertRules

### 5. SSE Ticket Test (30 seconds)
```bash
rails runner scripts/alerts/05_test_sse_ticket.rb
```
- Generates SSE tickets
- Verifies tickets work
- Confirms invalid tickets rejected
- Stress tests with 10 rapid generations

### 6. Slack Delivery Test (30 seconds)
```bash
rails runner scripts/alerts/06_test_slack_delivery.rb
```
- Creates test alert and notification
- Delivers to configured Slack channel
- Shows Slack message timestamp
- Cleans up test data

## Documentation

- **QUICK_START.md** - Step-by-step testing guide
- **FINALIZATION_REPORT.md** - Detailed implementation report
- **README.md** - This file

## Complete Test Flow (10-15 minutes)

```bash
# 1. Health check
rails runner scripts/alerts/01_health_check.rb

# 2. Test condition alerts
rails runner scripts/alerts/02_test_condition_alerts.rb

# 3. Setup events
rails runner scripts/alerts/03_setup_event_definitions.rb

# 4. Test events
rails runner scripts/alerts/04_test_event_alerts.rb

# 5. Verify SSE
rails runner scripts/alerts/05_test_sse_ticket.rb

# 6. Test Slack
rails runner scripts/alerts/06_test_slack_delivery.rb
```

## Key Features Tested

✅ Condition-based alerts  
✅ Event-based alerts  
✅ Role-based recipient resolution  
✅ in_app + Slack notifications  
✅ SSE ticket generation  
✅ Soft delete for AlertRules  
✅ Alert/Notification history preserved  
✅ Slack delivery  

## Requirements

- Rails environment configured
- Operations database migrated
- Superset configured (optional)
- Redis running
- Slack integration connected (for Slack test)

## Expected Results

### Condition Alert Test
- Creates 5+ open alerts
- Generates 10+ notifications (2 per alert)
- Resolves alerts when condition no longer met

### Event Alert Test
- Publishes 3 sample events
- Creates corresponding alerts
- Generates notifications for each
- Delivers to Slack

### Health Check
- All systems show ✓
- 6/6 incident definitions present
- 0 soft-deleted rules (until you test soft delete)

## Troubleshooting

If a test fails:

1. **Health check fails** - Check database/Redis/Superset connectivity
2. **Condition test fails** - Verify hub has allow_alerts=true and capacity alertable
3. **Event test fails** - Create event AlertRules via UI first
4. **SSE test fails** - Check Rails crypto configuration
5. **Slack test fails** - Verify bot token and channel configuration

## Next Steps

1. Run health check to establish baseline
2. Run condition alert test to verify flow
3. Setup event definitions
4. Create event AlertRules via UI
5. Run event alert test
6. Monitor Slack channel for messages

---

All scripts preserve data integrity and are safe to re-run in development.

## Advanced incidents (Truck Failure · Extra Vehicle Request · Route Diversion)

Data setup (idempotent, run in this order on a fresh environment):

```bash
bin/rails runner scripts/data/add_100_vehicles.rb            # TRK-101..200 -> 200 map vehicles
bin/rails runner scripts/data/seed_waybills.rb               # waybills for in-transit trips
bin/rails runner scripts/data/seed_advanced_incidents.rb     # keyed EventDefinitions, rules, assignees
bin/rails runner scripts/data/seed_route_diversions.rb       # active diversions across India (+ re-plans positions)
bin/rails runner scripts/data/regenerate_vehicle_positions.rb  # route-consistent positions + coherent ETAs
bin/rails runner scripts/data/validate_operational_consistency.rb  # vehicles / hubs / diversions / notifications
```

Scenario tests (each exits non-zero on failure):

| Script | Covers |
|---|---|
| `07_test_truck_failure.rb` | Truck Failure enrichment, in-app + Slack delivery, acknowledge → assign → escalate → resolve |
| `08_test_extra_vehicle_request.rb` | Extra Vehicle Request with hub load / capacity |
| `09_test_route_diversion.rb` | RouteDiversion impact, alert, Slack layout, map endpoints |
| `10_test_hub_direction_filter.rb` | Hub inbound/outbound list == hub counts |
| `11_test_notification_parity.rb` | In-app vs Slack card parity, lifecycle via API, SSE `incident_update`, Slack `chat.update`, drill-through links |
