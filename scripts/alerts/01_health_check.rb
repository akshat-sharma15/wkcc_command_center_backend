#!/usr/bin/env rails runner
# Complete system health check for alert/notification infrastructure

puts "=" * 70
puts "ALERT & NOTIFICATION SYSTEM HEALTH CHECK"
puts "=" * 70

puts "\n[1] DATABASE"
begin
  Alert.count
  puts "  ✓ Operations DB connected"
rescue => e
  puts "  ✗ Operations DB: #{e.message}"
end

puts "\n[2] REDIS"
begin
  redis = Redis.new(url: RealtimeNotificationPublisher.redis_url)
  redis.ping
  puts "  ✓ Redis connected"
  redis.close
rescue => e
  puts "  ✗ Redis: #{e.message}"
end

puts "\n[3] SUPERSET"
if SupersetDirectory.configured?
  puts "  ✓ Configured"
  roles = SupersetDirectory.roles
  users = SupersetDirectory.users
  puts "    - #{roles.count} roles"
  puts "    - #{users.count} users"
else
  puts "  ✗ Not configured"
end

puts "\n[4] SLACK"
integration = Integration.find_by(provider: "slack")
if integration&.connected?
  puts "  ✓ Connected"
  puts "    - Channel: #{ENV["SLACK_NOTIFICATION_CHANNEL"]}"
else
  puts "  ✗ Not connected"
end

puts "\n[5] EVENT DEFINITIONS"
puts "  Total: #{EventDefinition.count}"
puts "  Incidents: #{EventDefinition.where(name: ["Vehicle ETA Breach Risk", "Route Deviation", "Vehicle GPS Stale", "Hub Congestion", "Trip Missed Departure Risk", "Customer SLA Breach"]).count}/6"

puts "\n[6] ALERT RULES"
puts "  Total: #{AlertRule.count}"
puts "  Active: #{AlertRule.active.count}"
puts "  Condition: #{AlertRule.where(trigger_type: "condition").count}"
puts "  Event: #{AlertRule.where(trigger_type: "event").count}"
puts "  Soft-deleted: #{AlertRule.deleted.count}"

puts "\n[7] ALERTS"
puts "  Open: #{Alert.where(status: "open").count}"
puts "  Acknowledged: #{Alert.where(status: "acknowledged").count}"
puts "  Resolved: #{Alert.where(status: "resolved").count}"

puts "\n[8] NOTIFICATIONS"
puts "  Pending: #{Notification.where(status: "pending").count}"
puts "  Delivered: #{Notification.where(status: "delivered").count}"
puts "  Failed: #{Notification.where(status: "failed").count}"
puts "  Unread: #{Notification.unread.count}"

puts "\n[9] ALERTABLE MODELS"
AlertRule::ALERTABLE_MODELS.each do |group, model|
  count = model.where(allow_alerts: true).count
  puts "  - #{model.name}: #{count}"
end

puts "\n" + "=" * 70
puts "END HEALTH CHECK"
puts "=" * 70
