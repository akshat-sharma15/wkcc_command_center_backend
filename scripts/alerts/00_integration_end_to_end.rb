#!/usr/bin/env rails runner
# DEMO-READY END-TO-END ALERT & NOTIFICATION INTEGRATION TEST
#
# Safe to run repeatedly, including back-to-back during a live client demo:
#   - Owns a fixed set of clearly-named "Demo: ..." AlertRules (created here,
#     idempotently, on every run) covering real business conditions across
#     Hubs, Vehicles, Packages, Payments, Workforce, and 3 of the seeded
#     incident EventDefinitions.
#   - Rotates to the NEXT scenario in that list each run (based on the most
#     recently triggered demo Alert), so consecutive runs never repeat the
#     same alert and always read as a distinct, meaningful business event.
#   - Picks a random real record for the scenario's entity each run, so the
#     notification text always names a real hub/vehicle/package/etc., not a
#     hardcoded id.
#   - Restores the record to its original value once the cycle completes, so
#     the demo dataset never accumulates junk state between runs.
#
# This script:
# 1. Verifies all integrations (DB, Redis, Superset, Slack)
# 2. Ensures the demo AlertRules exist (creates/repairs them if missing)
# 3. Picks the next scenario in rotation
# 4. Triggers that scenario's real-world condition/event
# 5. Waits for the Alert, then Notifications, then delivery
# 6. Prints the EXACT title/message that lands in NotificationBell + Slack
# 7. Restores the record to its pre-demo state

puts "\n" + "=" * 80
puts "🚀 END-TO-END ALERT & NOTIFICATION INTEGRATION TEST (Demo Mode)"
puts "=" * 80

# ============================================================================
# STEP 1: VERIFY ALL INTEGRATIONS
# ============================================================================
puts "\n[STEP 1] VERIFYING INTEGRATIONS"
puts "-" * 80

all_good = true

begin
  Alert.count
  puts "  ✅ Operations Database: Connected"
rescue => e
  puts "  ❌ Operations Database: #{e.message}"
  all_good = false
end

begin
  redis = Redis.new(url: RealtimeNotificationPublisher.redis_url)
  redis.ping
  redis.close
  puts "  ✅ Redis: Connected (for SSE pub/sub)"
rescue => e
  puts "  ❌ Redis: #{e.message}"
  all_good = false
end

if SupersetDirectory.configured?
  puts "  ✅ Superset: Configured"
  roles = SupersetDirectory.roles
  users = SupersetDirectory.users
  puts "     → #{roles.count} roles, #{users.count} users"
else
  puts "  ❌ Superset: NOT CONFIGURED — cannot resolve a real recipient role"
  all_good = false
end

slack_integration = Integration.find_by(provider: "slack")
channel = ENV["SLACK_NOTIFICATION_CHANNEL"]

if slack_integration&.connected? && slack_integration.bot_token.present?
  puts "  ✅ Slack: Connected"
  puts "     → Workspace: #{slack_integration.workspace_name}"
  puts "     → Channel: #{channel || 'NOT SET'}"
  slack_ready = channel.present?
else
  puts "  ⚠️  Slack: NOT CONNECTED"
  puts "     → Slack notifications will be created but will FAIL to deliver"
  puts "     → To fix: go to Settings → Slack Integration → Connect"
  slack_ready = false
end

unless all_good
  puts "\n❌ INTEGRATION TEST FAILED - Fix issues above and retry"
  exit 1
end

puts "\n✅ ALL INTEGRATIONS READY"

# ============================================================================
# STEP 2: ENSURE THE DEMO ALERT RULES EXIST
# ============================================================================
puts "\n[STEP 2] ENSURING DEMO ALERT RULES EXIST"
puts "-" * 80

demo_role = SupersetDirectory.roles.find { |r| r[:name] == "Admin" } || SupersetDirectory.roles.first
unless demo_role
  puts "❌ No real Superset role exists to use as a recipient — cannot create demo rules."
  puts "   Create at least one role in Superset and re-run."
  exit 1
end
puts "  Recipient role for all demo rules: '#{demo_role[:name]}' (id=#{demo_role[:id]})"

# Each scenario is a real, named business condition — not a synthetic
# "test" rule — so the notification text is meaningful in a client demo.
# :trigger_value is what makes the rule fire; :safe_value is a valid,
# non-triggering value used only if a record happens to already be at
# :trigger_value when picked (keeps the run idempotent); the record is
# always restored to its true original value at the end (STEP 7).
CONDITION_SCENARIOS = [
  {
    name: "Demo: Hub Parking Capacity Critical", severity: "critical",
    group: "hubs", field: "available_parking", operator: "<", value: 5,
    trigger_value: 2, safe_value: 999
  },
  {
    name: "Demo: Vehicle Out of Service", severity: "warning",
    group: "vehicles", field: "status", operator: "=", value: "out_of_service",
    trigger_value: "out_of_service", safe_value: "active"
  },
  {
    name: "Demo: Package Damage Threshold Exceeded", severity: "warning",
    group: "packages", field: "damaged_quantity", operator: ">=", value: 5,
    trigger_value: 6, safe_value: 0
  },
  {
    name: "Demo: Payment Overdue", severity: "warning",
    group: "payments", field: "payment_status", operator: "=", value: "overdue",
    trigger_value: "overdue", safe_value: "pending"
  },
  {
    name: "Demo: Workforce Unplanned Absence", severity: "info",
    group: "workforce", field: "attendance_status", operator: "=", value: "absent",
    trigger_value: "absent", safe_value: "present"
  }
].freeze

# entity_group matches an AlertRule::ALERTABLE_MODELS key so
# AlertNotificationMessageBuilder can resolve a real, human-readable name
# (e.g. "Indore Regional Hub") instead of a bare "Hub #1".
EVENT_SCENARIOS = [
  {
    name: "Demo: Hub Congestion Incident", severity: "critical",
    event_type: "Hub Congestion", entity_group: "hubs", entity_type: "hubs"
  },
  {
    name: "Demo: Vehicle ETA Breach Risk Incident", severity: "warning",
    event_type: "Vehicle ETA Breach Risk", entity_group: "vehicles", entity_type: "vehicles"
  },
  {
    name: "Demo: Customer SLA Breach Incident", severity: "critical",
    event_type: "Customer SLA Breach", entity_group: "payments", entity_type: "Customer"
  }
].freeze

ensured_rules = []

CONDITION_SCENARIOS.each do |scenario|
  rule = AlertRule.active.find_or_initialize_by(name: scenario[:name])
  rule.assign_attributes(
    trigger_type: "condition",
    event_definition_id: nil,
    group: scenario[:group],
    field: scenario[:field],
    operator: scenario[:operator],
    value: scenario[:value].to_s,
    severity: scenario[:severity],
    recipient_type: "role",
    recipient_id: demo_role[:id],
    notification_channels: %w[in_app slack],
    enabled: true,
    notify: true
  )
  if rule.save
    puts "  ✅ #{scenario[:name]} (rule ##{rule.id})"
    ensured_rules << scenario.merge(kind: :condition, rule: rule)
  else
    puts "  ❌ #{scenario[:name]}: #{rule.errors.full_messages.join(', ')}"
  end
end

EVENT_SCENARIOS.each do |scenario|
  event_def = EventDefinition.find_by(event_type: scenario[:event_type])
  unless event_def
    puts "  ⚠️  #{scenario[:name]}: skipped — EventDefinition '#{scenario[:event_type]}' not found."
    puts "     → Run scripts/alerts/03_setup_event_definitions.rb first."
    next
  end

  rule = AlertRule.active.find_or_initialize_by(name: scenario[:name])
  rule.assign_attributes(
    trigger_type: "event",
    event_definition_id: event_def.id,
    group: nil,
    field: nil,
    operator: nil,
    value: nil,
    severity: scenario[:severity],
    recipient_type: "role",
    recipient_id: demo_role[:id],
    notification_channels: %w[in_app slack],
    enabled: true,
    notify: true
  )
  if rule.save
    puts "  ✅ #{scenario[:name]} (rule ##{rule.id})"
    ensured_rules << scenario.merge(kind: :event, rule: rule, event_definition: event_def)
  else
    puts "  ❌ #{scenario[:name]}: #{rule.errors.full_messages.join(', ')}"
  end
end

if ensured_rules.empty?
  puts "\n❌ NO DEMO RULES COULD BE ESTABLISHED — see errors above."
  exit 1
end

# ============================================================================
# STEP 3: PICK THE NEXT SCENARIO IN ROTATION
# ============================================================================
puts "\n[STEP 3] SELECTING NEXT DEMO SCENARIO"
puts "-" * 80

demo_names_in_order = ensured_rules.map { |s| s[:name] }
last_rule_name = Alert.joins(:alert_rule)
  .where(alert_rules: { name: demo_names_in_order })
  .order(created_at: :desc)
  .limit(1)
  .pick("alert_rules.name")

start_index = last_rule_name ? (demo_names_in_order.index(last_rule_name).to_i + 1) % ensured_rules.length : 0
scenario = ensured_rules[start_index]
rule = scenario[:rule]

puts "  Last demo alert used: #{last_rule_name || '(none yet)'}"
puts "  ✅ This run's scenario: '#{scenario[:name]}'"
puts "     → Rule ##{rule.id}, severity=#{scenario[:severity]}, channels=#{rule.notification_channels.join(', ')}"

# ============================================================================
# STEP 4: CLEAR ANY EXISTING OPEN ALERT FOR THIS SCENARIO'S RULE ONLY
# ============================================================================
puts "\n[STEP 4] CLEARING PRIOR OPEN ALERT FOR THIS SCENARIO"
puts "-" * 80

existing_open = Alert.where(alert_rule_id: rule.id, status: "open")
if existing_open.any?
  existing_open.update_all(status: "resolved", resolved_at: Time.current)
  puts "  ✅ Resolved #{existing_open.count} prior open alert(s) for this rule"
else
  puts "  ✅ No prior open alert for this rule"
end

# ============================================================================
# STEP 5: TRIGGER THE REAL-WORLD CONDITION / EVENT
# ============================================================================
puts "\n[STEP 5] TRIGGERING: #{scenario[:name]}"
puts "-" * 80

trigger_description = nil
record_to_restore = nil
original_value = nil

if scenario[:kind] == :condition
  model = AlertRule::ALERTABLE_MODELS[scenario[:group]]
  record = model.where(allow_alerts: true)
    .where("? = ANY (alertable_fields)", scenario[:field])
    .order(Arel.sql("RANDOM()"))
    .first

  unless record
    puts "❌ No eligible #{model.name} records found (allow_alerts=true, '#{scenario[:field]}' alertable)"
    exit 1
  end

  identifying = %w[name identifier number code].find { |a| record.respond_to?(a) && record.public_send(a).present? }
  record_label = identifying ? "#{model.name} #{record.public_send(identifying)}" : "#{model.name} ##{record.id}"

  original_value = record.public_send(scenario[:field])
  trigger_value = scenario[:trigger_value]

  puts "  Target record: #{record_label} (id=#{record.id})"
  puts "  Current #{scenario[:field]}: #{original_value.inspect}"

  if original_value.to_s == trigger_value.to_s
    puts "  → Already at trigger value; nudging to a safe value first so the change is real"
    record.update!(scenario[:field] => scenario[:safe_value])
    sleep 2
  end

  puts "  → Setting #{scenario[:field]} to #{trigger_value.inspect} (rule: #{scenario[:group]}.#{scenario[:field]} #{scenario[:operator]} #{scenario[:value]})"
  record.update!(scenario[:field] => trigger_value)
  puts "  ✅ Record updated — AlertEvaluationJob should trigger"

  record_to_restore = record
  trigger_description = "#{record_label}: #{scenario[:field]} → #{trigger_value}"

elsif scenario[:kind] == :event
  event_def = scenario[:event_definition]
  entity_model = AlertRule::ALERTABLE_MODELS[scenario[:entity_group]]
  entity_record = entity_model&.order(Arel.sql("RANDOM()"))&.first

  unless entity_record
    puts "❌ No real #{scenario[:entity_group]} record found to attach this event to"
    exit 1
  end

  identifying = %w[name identifier number code].find { |a| entity_record.respond_to?(a) && entity_record.public_send(a).present? }
  entity_label = identifying ? entity_record.public_send(identifying) : "##{entity_record.id}"

  puts "  Event: #{event_def.name}"
  puts "  Entity: #{scenario[:entity_type]} #{entity_label} (id=#{entity_record.id})"

  EventPublisher.publish(
    event_definition: event_def,
    entity_type: scenario[:entity_type],
    entity_id: entity_record.id,
    payload: { demo: true, entity_label: entity_label.to_s, triggered_at: Time.current.iso8601 }
  )
  puts "  ✅ Event published"

  trigger_description = "#{scenario[:entity_type].to_s.singularize.capitalize} #{entity_label} triggered '#{event_def.name}'"
end

# ============================================================================
# STEP 6: WAIT FOR ALERT CREATION
# ============================================================================
puts "\n[STEP 6] WAITING FOR ALERT CREATION"
puts "-" * 80

print "  ⏳ Waiting for AlertEvaluationJob/EventPublisher"
alert = nil
10.times do
  sleep 1
  print "."
  alert = Alert.where(alert_rule_id: rule.id, status: "open").order(created_at: :desc).first
  break if alert
end
puts

unless alert
  puts "❌ ALERT NOT CREATED - Check Sidekiq jobs and logs"
  record_to_restore&.update!(scenario[:field] => original_value)
  exit 1
end

puts "  ✅ Alert created!"
puts "     → ID: #{alert.id}"
puts "     → Status: #{alert.status}"
puts "     → Triggered at: #{alert.triggered_at}"

# ============================================================================
# STEP 7: WAIT FOR NOTIFICATIONS + DELIVERY
# ============================================================================
puts "\n[STEP 7] WAITING FOR NOTIFICATIONS"
puts "-" * 80

notifications = alert.notifications
expected_count = rule.notification_channels.count

print "  ⏳ Waiting for #{expected_count} notification(s)"
expected_count.times.each { |i| break if notifications.reload.count >= expected_count; sleep 1; print "." }
10.times { break if notifications.reload.count >= expected_count; sleep 1; print "." }
puts

if notifications.empty?
  puts "❌ NO NOTIFICATIONS CREATED — check AlertRecipientResolver / AlertNotifier logs"
  record_to_restore&.update!(scenario[:field] => original_value)
  exit 1
end

puts "  ✅ #{notifications.count} notification(s) created:"
notifications.each { |n| puts "     → [#{n.channel}] ID: #{n.id}, Status: #{n.status}" }

puts "\n[STEP 8] WAITING FOR DELIVERY"
puts "-" * 80
print "  ⏳ Waiting for NotificationDeliveryJob"
10.times do
  sleep 1
  print "."
  notifications.each(&:reload)
  break if notifications.all? { |n| n.status != "pending" }
end
puts

puts "  ✅ Delivery status:"
notifications.each do |n|
  icon = { "delivered" => "✅", "pending" => "⏳", "failed" => "❌" }[n.status] || "⚠️"
  puts "     → [#{n.channel.upcase}] #{icon} #{n.status.upcase}"
  puts "        Slack TS: #{n.external_reference}" if n.channel == "slack" && n.external_reference.present?
  puts "        Error: #{n.error_message}" if n.error_message.present?
end

# ============================================================================
# STEP 9: SHOW THE EXACT NOTIFICATION TEXT (what the client will see)
# ============================================================================
puts "\n[STEP 9] NOTIFICATION PREVIEW (exact text delivered to end users)"
puts "-" * 80
sample = notifications.first
puts "  Title:   #{sample.title}"
puts "  Message: #{sample.message}"

# ============================================================================
# STEP 10: RESTORE THE RECORD TO ITS ORIGINAL STATE
# ============================================================================
if record_to_restore
  puts "\n[STEP 10] RESTORING DEMO RECORD"
  puts "-" * 80
  record_to_restore.update!(scenario[:field] => original_value)
  puts "  ✅ #{scenario[:field]} restored to #{original_value.inspect} (this will auto-resolve the alert)"
end

# ============================================================================
# SUMMARY
# ============================================================================
puts "\n" + "=" * 80
puts "📊 TEST SUMMARY"
puts "=" * 80

puts "\n✅ COMPLETED:"
puts "  1. Scenario: '#{scenario[:name]}'"
puts "  2. Trigger Applied: #{trigger_description}"
puts "  3. Alert Triggered: ##{alert.id} (Status: #{alert.status})"
puts "  4. Notifications Created: #{notifications.count}"

in_app_notif = notifications.find { |n| n.channel == "in_app" }
slack_notif = notifications.find { |n| n.channel == "slack" }
in_app_status = in_app_notif&.status || "not_created"
slack_status = slack_notif&.status || "not_created"

puts "\n📨 DELIVERY STATUS:"
puts "  #{in_app_status == 'delivered' ? '✅' : '⚠️'} In-App:  #{in_app_status.upcase}"
puts "  #{slack_status == 'delivered' ? '✅' : (slack_status == 'pending' ? '⏳' : '❌')} Slack:   #{slack_status.upcase}"

puts "\n" + "=" * 80

slack_env_issue = slack_notif && slack_notif.status == "failed" && !slack_ready
slack_not_in_channel = slack_notif && slack_notif.error_message == "not_in_channel"

if in_app_status == "delivered" && slack_status == "delivered"
  puts "✅ END-TO-END TEST PASSED!"
  puts "\n🎉 NOTIFICATION CYCLE COMPLETE:"
  puts "   1. Alert triggered from rule: #{rule.name}"
  puts "   2. Notifications created (in_app + slack)"
  puts "   3. Delivered to end-user platform (NotificationBell + Slack)"
  puts "\n   The complete alert → notification → delivery flow works! 🚀"
elsif in_app_status == "delivered" && slack_env_issue
  puts "✅ PIPELINE PASSED (Slack delivery skipped — Slack not connected)"
  puts "   → Connect Slack (Settings → Slack Integration → Connect) and re-run."
elsif in_app_status == "delivered" && slack_not_in_channel
  puts "✅ PIPELINE PASSED (Slack delivery blocked — bot not in channel #{channel})"
  puts "\n   Slack rejected the message with 'not_in_channel'. Fix with ONE of:"
  puts "     a) In Slack, open ##{channel} and run: /invite @<your-bot-name>"
  puts "        (fastest — works immediately, no reconnect needed)"
  puts "     b) Disconnect and reconnect Slack in Settings — the bot now"
  puts "        requests chat:write.public + channels:join, which let it"
  puts "        post to public channels without a manual invite."
  puts "   Then re-run this script."
else
  puts "⚠️  TEST INCOMPLETE"
  puts "\n   In-App notification status: #{in_app_status}"
  puts "   Slack notification status: #{slack_status}"
  puts "\n   Check logs (NotificationDeliveryJob, Sidekiq) and retry."
end

puts "=" * 80 + "\n"
