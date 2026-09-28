# Seed predefined incident event definitions
# Run via: rails db:seed:incident_event_definitions

incidents = [
  {
    name: "Vehicle ETA Breach Risk",
    group: "Fleet / Transport",
    event_type: "Vehicle ETA Breach Risk",
    description: "Vehicle is at risk of missing its estimated arrival time"
  },
  {
    name: "Route Deviation",
    group: "Fleet / Transport",
    event_type: "Route Diversion",
    description: "Vehicle has deviated from its planned route"
  },
  {
    name: "Vehicle GPS Stale",
    group: "Fleet / Transport",
    event_type: "Vehicle GPS Stale",
    description: "Vehicle GPS signal is stale or not updating"
  },
  {
    name: "Hub Congestion",
    group: "Hubs",
    event_type: "Hub Congestion",
    description: "Hub is experiencing unusual congestion"
  },
  {
    name: "Trip Missed Departure Risk",
    group: "Fleet / Transport",
    event_type: "Trip Missed Departure Risk",
    description: "Trip is at risk of missing its scheduled departure time"
  },
  {
    name: "Customer SLA Breach",
    group: "Sales",
    event_type: "Customer SLA Breach",
    description: "A customer service level agreement is at risk of breach"
  }
]

puts "Creating predefined incident event definitions..."
incidents.each do |incident_data|
  existing = EventDefinition.find_by(name: incident_data[:name])
  if existing
    puts "  ⊘ #{incident_data[:name]}: Already exists (id=#{existing.id})"
  else
    event_def = EventDefinition.create!(
      name: incident_data[:name],
      group: incident_data[:group],
      event_type: incident_data[:event_type]
    )
    puts "  ✓ #{incident_data[:name]}: Created (id=#{event_def.id})"
  end
end

puts "Done!"
