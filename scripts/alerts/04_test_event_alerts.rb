#!/usr/bin/env rails runner
# Test event-based alerts using predefined EventDefinitions

puts "=" * 70
puts "EVENT ALERT TEST"
puts "=" * 70

# List available incident events
incident_names = [
  "Vehicle ETA Breach Risk",
  "Route Deviation",
  "Vehicle GPS Stale",
  "Hub Congestion",
  "Trip Missed Departure Risk",
  "Customer SLA Breach"
]

event_defs = EventDefinition.where(name: incident_names).order(:name)
puts "\n[AVAILABLE INCIDENTS]"
event_defs.each do |event_def|
  rule_count = AlertRule.active.where(event_definition_id: event_def.id, trigger_type: "event", enabled: true).count
  status = rule_count > 0 ? "✓ #{rule_count} rule(s)" : "⊘ No rules"
  puts "  - #{event_def.name} (id=#{event_def.id}): #{status}"
end

# Find enabled event alert rules
event_rules = AlertRule.active.where(trigger_type: "event", enabled: true)
unless event_rules.any?
  puts "\n⊘ No enabled event alert rules found"
  puts "   Create event alert rules first via UI or script"
  exit 0
end

puts "\n[EVENT ALERT RULES]"
event_rules.each do |rule|
  event_def = rule.event_definition
  puts "  - Rule ##{rule.id}: #{rule.name}"
  puts "    Event: #{event_def&.name || 'MISSING'}"
  puts "    Notify: #{rule.notify?} → #{rule.recipient_type} ##{rule.recipient_id}"
  puts "    Channels: #{rule.notification_channels.join(', ')}"
end

# Test entities
puts "\n[TEST ENTITIES]"
vehicles = Vehicle.where(allow_alerts: true).limit(2)
hubs = Hub.where(allow_alerts: true).limit(2)

puts "  Vehicles: #{vehicles.count}"
vehicles.each { |v| puts "    - #{v.name} (id=#{v.id})" }
puts "  Hubs: #{hubs.count}"
hubs.each { |h| puts "    - #{h.name} (id=#{h.id})" }

puts "\n[PUBLISHING EVENTS]"
puts "-" * 70

created_alerts = []

# Test Vehicle ETA Breach Risk
if (event_def = EventDefinition.find_by(name: "Vehicle ETA Breach Risk"))
  vehicle = vehicles.first
  if vehicle
    puts "\n1. VEHICLE ETA BREACH RISK"
    puts "   Entity: Vehicle ##{vehicle.id} (#{vehicle.name})"

    begin
      EventPublisher.publish(
        event_definition: event_def,
        entity_type: "vehicles",
        entity_id: vehicle.id,
        payload: { eta_minutes_at_risk: 15, scheduled_eta: "14:30" }
      )

      alert = Alert.where(
        group: "events:vehicles",
        record_id: vehicle.id,
        status: "open"
      ).order(created_at: :desc).first

      if alert
        puts "   ✓ Alert created (id=#{alert.id})"
        created_alerts << alert.id
        puts "   Notifications: #{alert.notifications.count}"
        alert.notifications.each do |n|
          puts "     - #{n.channel}: #{n.status}"
        end
      end
    rescue => e
      puts "   ✗ Error: #{e.message}"
    end
  end
end

# Test Hub Congestion
if (event_def = EventDefinition.find_by(name: "Hub Congestion"))
  hub = hubs.first
  if hub
    puts "\n2. HUB CONGESTION"
    puts "   Entity: Hub ##{hub.id} (#{hub.name})"

    begin
      EventPublisher.publish(
        event_definition: event_def,
        entity_type: "hubs",
        entity_id: hub.id,
        payload: { congestion_level: "high", packages_pending: 245 }
      )

      alert = Alert.where(
        group: "events:hubs",
        record_id: hub.id,
        status: "open"
      ).order(created_at: :desc).first

      if alert
        puts "   ✓ Alert created (id=#{alert.id})"
        created_alerts << alert.id
        puts "   Notifications: #{alert.notifications.count}"
        alert.notifications.each do |n|
          puts "     - #{n.channel}: #{n.status}"
        end
      end
    rescue => e
      puts "   ✗ Error: #{e.message}"
    end
  end
end

# Test Customer SLA Breach
if (event_def = EventDefinition.find_by(name: "Customer SLA Breach"))
  puts "\n3. CUSTOMER SLA BREACH"
  puts "   Entity: Shipment (using sample data)"

  begin
    EventPublisher.publish(
      event_definition: event_def,
      entity_type: "shipments",
      entity_id: 1,
      payload: { customer_id: "C123", sla_hours: 24, hours_remaining: 2 }
    )

    alert = Alert.where(
      group: "events:shipments",
      record_id: 1,
      status: "open"
    ).order(created_at: :desc).first

    if alert
      puts "   ✓ Alert created (id=#{alert.id})"
      created_alerts << alert.id
      puts "   Notifications: #{alert.notifications.count}"
      alert.notifications.each do |n|
        puts "     - #{n.channel}: #{n.status}"
      end
    end
  rescue => e
    puts "   ✗ Error: #{e.message}"
  end
end

# Wait for delivery jobs
if created_alerts.any?
  puts "\n[WAIT] Waiting for notification delivery (5 seconds)..."
  5.times { sleep 1; print "." }
  puts
end

# Summary
puts "\n[SUMMARY]"
puts "  - Alerts created: #{created_alerts.count}"

all_event_alerts = Alert.where("group LIKE ?", "events:%", status: "open")
puts "  - Total event alerts: #{all_event_alerts.count}"

puts "\n" + "=" * 70
puts "EVENT TEST COMPLETE"
puts "=" * 70
