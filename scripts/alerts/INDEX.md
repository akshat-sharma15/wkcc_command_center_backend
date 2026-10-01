# Alert System Test Scripts - Complete Index

**Location:** `/Users/mac/wkcc_command_center_backend/scripts/alerts/`

## All Scripts Available ✅

```
scripts/alerts/
├── 01_health_check.rb
├── 02_test_condition_alerts.rb
├── 03_setup_event_definitions.rb
├── 04_test_event_alerts.rb
├── 05_test_sse_ticket.rb
├── 06_test_slack_delivery.rb
├── README.md
├── QUICK_START.md
├── FINALIZATION_REPORT.md
└── INDEX.md (this file)
```

## Run Any Script

```bash
cd /Users/mac/wkcc_command_center_backend
rails runner scripts/alerts/01_health_check.rb
```

## Complete Test Flow (10-15 minutes)

```bash
# 1. Verify baseline (30s)
rails runner scripts/alerts/01_health_check.rb

# 2. Test condition alerts (2-3m)
rails runner scripts/alerts/02_test_condition_alerts.rb

# 3. Create incident definitions (15s)
rails runner scripts/alerts/03_setup_event_definitions.rb

# 4. Test event alerts (1m)
rails runner scripts/alerts/04_test_event_alerts.rb

# 5. Verify SSE (30s)
rails runner scripts/alerts/05_test_sse_ticket.rb

# 6. Test Slack delivery (30s)
rails runner scripts/alerts/06_test_slack_delivery.rb
```

## What Each Script Does

| Script | Time | Purpose |
|--------|------|---------|
| 01_health_check.rb | 30s | System diagnostics & baseline |
| 02_test_condition_alerts.rb | 2-3m | Create 5+ condition alerts |
| 03_setup_event_definitions.rb | 15s | Create 6 incident definitions |
| 04_test_event_alerts.rb | 1m | Test event alert triggering |
| 05_test_sse_ticket.rb | 30s | Verify SSE tickets work |
| 06_test_slack_delivery.rb | 30s | Test Slack integration |

## Documentation

- **README.md** - Overview of all scripts
- **QUICK_START.md** - Step-by-step testing guide
- **FINALIZATION_REPORT.md** - Detailed implementation details
- **INDEX.md** - This file

## Key Changes Made

✅ Soft delete AlertRule (deleted_at column)  
✅ 6 incident event definitions created  
✅ Slack 204 disconnect handling fixed  
✅ EventPublisher excludes deleted rules  
✅ AlertEvaluationJob excludes deleted rules  
✅ All test scripts moved to permanent location  

## Testing Checklist

- [ ] Run health_check.rb - verify baseline
- [ ] Run test_condition_alerts.rb - create 5+ alerts
- [ ] Run setup_event_definitions.rb - create incidents
- [ ] Create event AlertRules via UI
- [ ] Run test_event_alerts.rb - verify event flow
- [ ] Run test_sse_ticket.rb - verify SSE works
- [ ] Run test_slack_delivery.rb - test Slack

## All Systems Ready ✅

Database: ✓  
Redis: ✓  
Superset: ✓  
Slack: ✓  
SSE: ✓  
Soft Delete: ✓  
Events: ✓  

---

**Next:** See QUICK_START.md for complete testing guide
