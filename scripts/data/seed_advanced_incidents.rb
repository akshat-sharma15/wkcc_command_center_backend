# Sets up the three advanced incidents (Truck Failure, Extra Vehicle
# Request, Route Diversion) end to end. Idempotent - safe to re-run.
#
#   bin/rails runner scripts/data/seed_advanced_incidents.rb
#
# 1. EventDefinitions with stable keys (IncidentCatalog) - adopted by name
#    if they already exist, never duplicated.
# 2. One enabled event AlertRule per incident: notifies the Admin role on
#    in_app + Slack; primary assignee = the Admin user, secondary = the
#    Alpha role (both resolved by name from Superset, never copied).
# 3. Demo load capacities (hubs.load_capacity_kg) for the corridor hubs,
#    only where none is set - the schema had no hub capacity with a unit,
#    so these figures are demo configuration, not measured data.
DEMO_HUB_CAPACITY_KG = {
  "CC-HUB-016" => 7_500,  # Indore
  "HUB-IND" => 4_000,     # Indore Regional
  "HUB-RTM" => 2_000,     # Ratlam Transit Point
  "CC-HUB-019" => 6_000,  # Bhopal
  "CC-HUB-013" => 6_000,  # Ahmedabad
  "CC-HUB-015" => 4_500,  # Vadodara
  "CC-HUB-014" => 5_000,  # Surat
  "CC-HUB-011" => 5_000,  # Mumbai
  "CC-HUB-012" => 14_000, # Pune
  "CC-HUB-018" => 13_000, # Nashik
  "CC-HUB-002" => 3_000,  # Jaipur
  "CC-HUB-001" => 5_000   # Delhi
}.freeze

RULES = {
  IncidentCatalog::VEHICLE_FAILURE => { name: "Incident: Truck Failure", severity: "critical", escalation_after_minutes: 15 },
  IncidentCatalog::HUB_EXTRA_VEHICLE_REQUEST => { name: "Incident: Extra Vehicle Request", severity: "warning", escalation_after_minutes: 30 },
  IncidentCatalog::ROUTE_DIVERSION => { name: "Incident: Route Diversion", severity: "critical", escalation_after_minutes: 20 }
}.freeze

puts "=" * 70
puts "SEED ADVANCED INCIDENTS"
puts "=" * 70

puts "\n[1] Event definitions"
IncidentCatalog.ensure_event_definitions!.each do |definition|
  puts "  ✓ #{definition.key.ljust(26)} ##{definition.id} #{definition.name} (#{definition.group} / #{definition.event_type})"
end

puts "\n[2] Alert rules"
admin_role = SupersetDirectory.roles.find { |role| role[:name] == "Admin" }
secondary_role = SupersetDirectory.roles.find { |role| role[:name] == "Alpha" }
admin_user = SupersetDirectory.users.find { |user| user[:username] == "admin" } || SupersetDirectory.users.first
abort("  ✗ Superset is not configured or has no Admin role/user - cannot set recipients/assignees") unless admin_role && admin_user

RULES.each do |key, attrs|
  rule = AlertRule.active.find_or_initialize_by(name: attrs[:name])
  rule.assign_attributes(
    trigger_type: "event", event_definition: IncidentCatalog.event_definition(key),
    group: nil, field: nil, operator: nil, value: nil,
    severity: attrs[:severity], enabled: true, notify: true,
    recipient_type: "role", recipient_id: admin_role[:id], notification_channels: %w[in_app slack],
    primary_assignee_type: "user", primary_assignee_id: admin_user[:id],
    secondary_assignee_type: secondary_role && "role", secondary_assignee_id: secondary_role&.dig(:id),
    escalation_after_minutes: attrs[:escalation_after_minutes]
  )
  status = rule.new_record? ? "created" : (rule.changed? ? "updated" : "unchanged")
  rule.save!
  puts "  ✓ ##{rule.id} #{rule.name} [#{status}] primary=user:#{admin_user[:name]} secondary=#{secondary_role ? "role:#{secondary_role[:name]}" : 'none'}"
end

puts "\n[3] Demo hub load capacities"
DEMO_HUB_CAPACITY_KG.each do |code, kg|
  hub = Hub.find_by(code: code)
  next puts("  ⊘ #{code} not found") unless hub
  next puts("  ⊘ #{hub.name}: already #{hub.load_capacity_kg.to_i} kg") if hub.load_capacity_kg

  hub.update_column(:load_capacity_kg, kg) # rubocop:disable Rails/SkipsModelValidations - demo config, not an alertable change
  puts "  ✓ #{hub.name}: #{kg} kg"
end

puts "\nDone. Trigger the scenarios with scripts/alerts/07-09_*.rb"
