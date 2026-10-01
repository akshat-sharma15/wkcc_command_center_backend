#!/usr/bin/env rails runner
# Create predefined event definitions for incident-based alerts

puts "=" * 70
puts "SETUP EVENT DEFINITIONS"
puts "=" * 70

# Define events
events = [
  { name: "Vehicle ETA Breach Risk", group: "Fleet / Transport", event_type: "Vehicle ETA Breach Risk" },
  { name: "Route Deviation", group: "Fleet / Transport", event_type: "Route Diversion" },
  { name: "Vehicle GPS Stale", group: "Fleet / Transport", event_type: "Vehicle GPS Stale" },
  { name: "Hub Congestion", group: "Hubs", event_type: "Hub Congestion" },
  { name: "Trip Missed Departure Risk", group: "Fleet / Transport", event_type: "Trip Missed Departure Risk" },
  { name: "Customer SLA Breach", group: "Sales", event_type: "Customer SLA Breach" }
]

puts "\n[CREATING] Event definitions..."
created = []
skipped = []

events.each do |event_data|
  existing = EventDefinition.find_by(name: event_data[:name])

  if existing
    skipped << event_data[:name]
    puts "  ⊘ #{event_data[:name]}: Already exists (id=#{existing.id})"
  else
    event_def = EventDefinition.create!(event_data)
    created << event_data[:name]
    puts "  ✓ #{event_data[:name]}: Created (id=#{event_def.id})"
  end
end

# Advanced operational incidents, keyed (vehicle.failure,
# hub.extra_vehicle_request, route.diversion) - see IncidentCatalog.
puts "\n[ADVANCED INCIDENTS]"
IncidentCatalog.ensure_event_definitions!.each do |event_def|
  puts "  ✓ #{event_def.key}: #{event_def.name} (id=#{event_def.id})"
end

puts "\n[SUMMARY]"
puts "  - Created: #{created.count}"
puts "  - Skipped (already exist): #{skipped.count}"

puts "\n[AVAILABLE EVENT DEFINITIONS]"
EventDefinition.order(:name).each do |event_def|
  puts "  - #{event_def.name} (id=#{event_def.id})"
  rule_count = AlertRule.where(event_definition_id: event_def.id).count
  if rule_count > 0
    puts "    → #{rule_count} alert rule(s)"
  end
end

puts "\n" + "=" * 70
puts "SETUP COMPLETE"
puts "=" * 70
