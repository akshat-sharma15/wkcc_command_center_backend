#!/usr/bin/env rails runner
# Test condition-based alerts by manipulating hub capacity
# Uses AlertRule ID 21: hubs.capacity > 9

puts "=" * 70
puts "CONDITION ALERT TEST - Hub Capacity Threshold"
puts "=" * 70

rule_id = 21
rule = AlertRule.active.find_by(id: rule_id)

unless rule
  puts "✗ Rule ID #{rule_id} not found or is deleted"
  exit 1
end

unless rule.condition_trigger? && rule.group == "hubs" && rule.field == "capacity"
  puts "✗ Rule #{rule_id} is not a hubs.capacity condition rule"
  exit 1
end

puts "\nRule: #{rule.name}"
puts "  Condition: #{rule.group}.#{rule.field} #{rule.operator} #{rule.value}"
puts "  Notify: #{rule.notify?}"
puts "  Recipient: #{rule.recipient_type} ##{rule.recipient_id}"
puts "  Channels: #{rule.notification_channels.join(', ')}"

# Find eligible hubs
eligible_hubs = Hub.where(allow_alerts: true)
  .where("? = ANY (alertable_fields)", "capacity")
  .limit(10)

unless eligible_hubs.any?
  puts "\n✗ No eligible hubs found"
  exit 1
end

puts "\n[SETUP] Found #{eligible_hubs.count} eligible hubs"
eligible_hubs.each_with_index do |hub, i|
  puts "  #{i+1}. #{hub.name} (id=#{hub.id}, capacity=#{hub.capacity})"
end

# Save original capacities
original_capacities = eligible_hubs.map { |h| [h.id, h.capacity] }.to_h
puts "\n[SAVE] Original capacities saved"

# Ensure any existing open alerts for this rule are resolved
puts "\n[CLEAR] Resolving any existing open alerts for this rule..."
Alert.where(alert_rule_id: rule_id, status: "open").each do |alert|
  alert.update!(status: "resolved", resolved_at: Time.current)
  puts "  - Resolved Alert ##{alert.id}"
end

# Set all hubs BELOW threshold
puts "\n[BELOW THRESHOLD] Setting all hubs capacity < #{rule.value}..."
eligible_hubs.each do |hub|
  hub.update!(capacity: rule.value.to_i - 1)
  puts "  - #{hub.name}: capacity = #{hub.capacity}"
end

# Wait for Sidekiq
puts "\n[WAIT] Waiting for evaluation (5 seconds)..."
5.times { sleep 1; print "." }
puts

# Verify no open alerts yet
open_count = Alert.where(alert_rule_id: rule_id, status: "open").count
puts "Open alerts before threshold: #{open_count} ✓" if open_count == 0

# Set all hubs ABOVE threshold
puts "\n[ABOVE THRESHOLD] Setting all hubs capacity > #{rule.value}..."
eligible_hubs.each do |hub|
  new_capacity = rule.value.to_i + 1
  hub.update!(capacity: new_capacity)
  puts "  - #{hub.name}: capacity = #{hub.capacity}"
end

# Wait for processing
puts "\n[WAIT] Waiting for alert creation (10 seconds)..."
10.times { sleep 1; print "." }
puts

# Collect results
puts "\n[RESULTS]"
puts "-" * 70

alerts = Alert.where(alert_rule_id: rule_id, status: "open")
puts "Open Alerts: #{alerts.count}"
alerts.each do |alert|
  hub = Hub.find(alert.record_id)
  puts "  - Alert ##{alert.id}: #{hub.name} (capacity=#{hub.capacity})"

  notifications = alert.notifications
  puts "    Notifications: #{notifications.count}"
  notifications.each do |notif|
    puts "      - ##{notif.id} [#{notif.channel}] status=#{notif.status} read=#{notif.read?}"
  end
end

puts "\n[RESTORE ORIGINAL CAPACITIES]"
original_capacities.each do |hub_id, original_capacity|
  hub = Hub.find(hub_id)
  hub.update!(capacity: original_capacity)
  puts "  - #{hub.name}: #{hub.capacity} → #{original_capacity}"
end

# Wait for resolution
puts "\n[WAIT] Waiting for alert resolution (5 seconds)..."
5.times { sleep 1; print "." }
puts

# Final state
puts "\n[FINAL STATE]"
open = Alert.where(alert_rule_id: rule_id, status: "open").count
resolved = Alert.where(alert_rule_id: rule_id, status: "resolved").count
puts "  - Open alerts: #{open}"
puts "  - Resolved alerts: #{resolved}"

puts "\n" + "=" * 70
puts "TEST COMPLETE"
puts "=" * 70
