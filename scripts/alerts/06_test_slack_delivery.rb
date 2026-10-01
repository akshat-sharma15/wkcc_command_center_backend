#!/usr/bin/env rails runner
# Test Slack delivery for notifications

puts "=" * 70
puts "SLACK DELIVERY TEST"
puts "=" * 70

# Verify Slack is configured
integration = Integration.find_by(provider: "slack")
unless integration&.connected? && integration.bot_token.present?
  puts "\n✗ Slack is not properly connected"
  puts "   Status: #{integration&.status}"
  puts "   Has token: #{integration&.bot_token.present?}"
  exit 1
end

channel = ENV["SLACK_NOTIFICATION_CHANNEL"]
unless channel.present?
  puts "\n✗ SLACK_NOTIFICATION_CHANNEL is not configured"
  exit 1
end

puts "\n[SETUP]"
puts "  Integration: #{integration.workspace_name} (#{integration.workspace_id})"
puts "  Channel: #{channel}"
puts "  Bot Token: present" if integration.bot_token.present?
puts "  Status: #{integration.status}"

# Find an alertable hub
puts "\n[CREATE TEST ALERT]"
hub = Hub.where(allow_alerts: true).first
unless hub
  puts "✗ No alertable hubs found"
  exit 1
end

puts "  Hub: #{hub.name} (id=#{hub.id})"

# Create a test alert
alert = Alert.create!(
  alert_rule_id: AlertRule.active.first&.id || 1,
  group: "hubs",
  record_id: hub.id,
  field: "capacity",
  expected_value: "10",
  actual_value: "15",
  severity: "warning",
  status: "open",
  triggered_at: Time.current
)

puts "  Alert created: id=#{alert.id}"

# Get a user ID
user_id = SupersetDirectory.users.first[:id] if SupersetDirectory.configured?
user_id ||= 1

puts "  Recipient user: id=#{user_id}"

# Create Slack notification
puts "\n[CREATE TEST NOTIFICATION]"

notification = Notification.create!(
  alert: alert,
  recipient_user_id: user_id,
  channel: "slack",
  status: "pending",
  title: "Test Alert: #{hub.name} Capacity High",
  message: "Hub capacity is above threshold (15 > 10)",
  metadata: { test: true }
)

puts "  Notification created: id=#{notification.id}"
puts "  Status: #{notification.status}"

# Deliver the notification
puts "\n[DELIVER NOTIFICATION]"

begin
  NotificationDeliveryJob.new.perform(notification.id)
  notification.reload
  puts "  ✓ Delivery job completed"
rescue => e
  puts "  ✗ Error during delivery: #{e.message}"
end

puts "  Final status: #{notification.status}"
if notification.external_reference.present?
  puts "  Slack message timestamp: #{notification.external_reference}"
end
if notification.error_message.present?
  puts "  Error message: #{notification.error_message}"
end

# Verify
puts "\n[VERIFICATION]"

if notification.status == "delivered"
  puts "  ✓ Notification delivered to Slack"
  puts "\n[CHECK SLACK CHANNEL]"
  puts "  1. Open #{channel} in Slack"
  puts "  2. Look for message about '#{hub.name}'"
  puts "  3. Message timestamp: #{notification.external_reference}"
elsif notification.status == "failed"
  puts "  ✗ Notification delivery failed"
  puts "    Error: #{notification.error_message}"
else
  puts "  ⊘ Notification status: #{notification.status}"
end

# Cleanup
puts "\n[CLEANUP]"
puts "  Deleting test data..."
alert.destroy
puts "  ✓ Test data cleaned up"

puts "\n" + "=" * 70
puts "SLACK DELIVERY TEST COMPLETE"
puts "=" * 70
