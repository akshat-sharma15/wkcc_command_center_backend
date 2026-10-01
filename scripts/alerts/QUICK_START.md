# Quick Start Guide - Alert System Testing

## 1. Run Health Check (30 seconds)

```bash
cd /Users/mac/wkcc_command_center_backend
rails runner scripts/alerts/01_health_check.rb
```

**Expected Output:**
```
✓ Operations DB connected
✓ Redis connected
✓ Superset: Configured
✓ Slack: Connected
✓ Event Definitions: 11 total, 6 incidents
✓ Alert Rules: 5 active (4 condition, 1 event)
✓ Alerts: 1 open, 4 resolved
✓ Alertable Models: 285+ total records
```

---

## 2. Test Condition Alerts (2-3 minutes)

```bash
rails runner scripts/alerts/02_test_condition_alerts.rb
```

**What It Does:**
1. Finds 5 eligible hubs
2. Saves original capacities
3. Sets them BELOW threshold (capacity < 9)
4. Sets them ABOVE threshold (capacity > 9) → Creates alerts
5. Waits for notification delivery
6. Restores original capacities → Resolves alerts
7. Shows results

**Expected Output:**
```
[RESULTS]
Open Alerts: 5
  - Alert #123: Hub A (capacity=15)
    Notifications: 2
      - #456 [in_app] status=delivered read=false
      - #457 [slack] status=delivered
  ...
```

---

## 3. Setup Event Definitions (15 seconds)

```bash
rails runner scripts/alerts/03_setup_event_definitions.rb
```

**Run Once Per Environment**

**Expected Output:**
```
✓ Vehicle ETA Breach Risk: Created (id=16)
✓ Route Deviation: Created (id=17)
✓ Vehicle GPS Stale: Created (id=18)
✓ Hub Congestion: Created (id=19)
✓ Trip Missed Departure Risk: Created (id=20)
✓ Customer SLA Breach: Created (id=21)
```

---

## 4. Create Event AlertRules (Via UI or Script)

Via Superset UI:
1. Go to **Events** page
2. Click **Create Alert Rule**
3. Select **Event** trigger type
4. Choose an incident (e.g., "Hub Congestion")
5. Set recipient role (e.g., "Admin")
6. Enable notifications: in_app + slack
7. Save

OR via Rails console:
```ruby
AlertRule.create!(
  name: "Hub Congestion Alert",
  trigger_type: "event",
  event_definition_id: 19,  # Hub Congestion
  recipient_type: "role",
  recipient_id: 1,  # Admin role
  severity: "warning",
  notification_channels: ["in_app", "slack"],
  enabled: true,
  notify: true
)
```

---

## 5. Test Event Alerts (1 minute)

```bash
rails runner scripts/alerts/04_test_event_alerts.rb
```

**Expected Output:**
```
[AVAILABLE INCIDENTS]
  - Hub Congestion (id=19): ✓ 1 rule(s)
  - Vehicle ETA Breach Risk (id=16): ⊘ No rules
  ...

[PUBLISHING EVENTS]
1. VEHICLE ETA BREACH RISK
   Entity: Vehicle #1
   ✓ Alert created (id=123)
   Notifications: 2
     - in_app: delivered
     - slack: delivered
```

---

## 6. Verify SSE Tickets (30 seconds)

```bash
rails runner scripts/alerts/05_test_sse_ticket.rb
```

**Expected Output:**
```
✓ Ticket generation works correctly
✓ Valid tickets verify successfully
✓ Invalid tickets are rejected
✓ Each ticket is unique
✓ Fresh tickets are immediately usable
```

---

## 7. Test Slack Delivery (30 seconds)

```bash
rails runner scripts/alerts/06_test_slack_delivery.rb
```

**Expected Output:**
```
✓ Notification delivered to Slack

[CHECK SLACK CHANNEL]
1. Open #alerts in Slack
2. Look for message about 'Hub Name'
3. Message timestamp: 1726421520.001200
```

**Then:**
1. Open Slack channel
2. Verify message appears
3. Check timestamp matches

---

## 8. Manual Browser Tests (5-10 minutes)

### Test SSE Reconnection
1. Open http://localhost:9000 (Superset)
2. Open DevTools (F12)
3. Go to Network tab, filter "stream"
4. Click NotificationBell
5. Verify SSE connection opens
6. Wait 65+ seconds
7. Watch for auto-reconnect with new ticket
8. Should happen automatically (no manual refresh needed)

### Test Slack Disconnect
1. Navigate to Settings → Slack
2. Click **Disconnect**
3. Should show success toast immediately
4. UI should show **Connect Slack** immediately
5. Refresh page
6. Should still show **Not Connected**

### Test Soft Delete
1. Go to **Alerts** page
2. Click **Delete** on a rule
3. Rule disappears from list immediately
4. Refresh page
5. Rule still gone
6. No new alerts created from that rule

---

## Complete Test Time: ~10-15 minutes

```bash
# Automated tests: ~8 minutes
rails runner scripts/alerts/01_health_check.rb          # 30s
rails runner scripts/alerts/02_test_condition_alerts.rb # 3m
rails runner scripts/alerts/03_setup_event_definitions.rb # 15s
rails runner scripts/alerts/04_test_event_alerts.rb     # 1m
rails runner scripts/alerts/05_test_sse_ticket.rb       # 30s
rails runner scripts/alerts/06_test_slack_delivery.rb   # 30s

# Manual browser tests: ~5-10 minutes
```

---

## Success Criteria

✅ Health check passes  
✅ Condition alerts created and resolved  
✅ 6 incident definitions exist  
✅ Event alerts trigger correctly  
✅ SSE tickets generate and verify  
✅ Slack delivery succeeds  
✅ Browser tests pass  

---

## Troubleshooting

### Condition Alert Test Fails
- **Issue:** No eligible hubs found
- **Fix:** Verify Hub.where(allow_alerts: true).count > 0
- **Fix:** Verify capacity is in hub.alertable_fields

### Event Alert Test Fails
- **Issue:** No event AlertRules found
- **Fix:** Create event AlertRules via UI (step 4)
- **Fix:** Verify rule is enabled and notify=true

### Slack Test Fails
- **Issue:** Slack not connected
- **Fix:** Go to Settings → Slack → Connect
- **Fix:** Verify SLACK_NOTIFICATION_CHANNEL env var

### SSE Test Fails
- **Issue:** Ticket generation error
- **Fix:** Check Rails crypto configuration
- **Fix:** Verify Redis is running

---

## Next Steps

1. All tests passing → Feature is ready for QA
2. Create event AlertRules for all 6 incidents via UI
3. Monitor Slack channel for test messages
4. Verify soft-deleted rules don't trigger alerts
5. Deploy to production

---

**All tests are safe to re-run** in development environment without data loss.
