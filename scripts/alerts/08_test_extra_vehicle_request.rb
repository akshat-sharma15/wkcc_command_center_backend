# Scenario 2 - Extra Vehicle Request (hub.extra_vehicle_request).
#   bin/rails runner scripts/alerts/08_test_extra_vehicle_request.rb [HUB_CODE]
# Defaults to the Indore Command Centre Hub. A still-open request for the
# same hub from a previous run is resolved first so the scenario repeats.
require_relative "support/scenario_helpers"
include ScenarioHelpers

puts "=" * 70
puts "SCENARIO 2 - EXTRA VEHICLE REQUEST"
puts "=" * 70

rule = AlertRule.active.find_by(name: "Incident: Extra Vehicle Request")
abort("Run scripts/data/seed_advanced_incidents.rb first") unless rule
hub = Hub.find_by!(code: ARGV[0].presence || "CC-HUB-016")

Alert.where(alert_rule: rule, group: "events:hubs", record_id: hub.id, status: "open").find_each do |previous|
  previous.resolve!(by: USER_ID, note: "Closed by scenario re-run")
  puts "  (resolved previous open request ##{previous.id})"
end

section "Trigger"
puts "  Hub #{hub.name} (#{hub.code})"
status, body = api(:post, "/api/v1/incidents/hub.extra_vehicle_request",
                   { entity_id: hub.id, payload: { requested_vehicle_count: 2, priority: "high",
                                                   reason: "Outbound demand exceeds available capacity" } })
check("POST /api/v1/incidents/hub.extra_vehicle_request", status == 201, "HTTP #{status}")
alert = body&.dig("alerts", 0)
abort("  ✗ no alert created: #{body.inspect}") unless alert
incident = alert["incident"]

section "Alert ##{alert['id']} enrichment"
show :hub, incident.dig("hub", "name")
show :inbound_vehicles, incident["inbound_vehicle_count"]
show :outbound_vehicles, incident["outbound_vehicle_count"]
show :projected_load, incident["projected_load_kg"] && "#{(incident['projected_load_kg'] / 1000.0).round(2)} t"
show :capacity, incident["capacity_kg"] && "#{(incident['capacity_kg'] / 1000.0).round(2)} t"
show :utilization, incident["projected_utilization_pct"] && "#{incident['projected_utilization_pct']}%"
show :available_vehicles, incident["available_vehicle_count"]
show :requested, incident["requested_vehicle_count"]
show :suggested, incident["suggested_additional_vehicles"]
show :reason, incident["reason"]
check("hub load computed", !incident["projected_load_kg"].nil? && !incident["inbound_vehicle_count"].nil?)
check("utilization computed", !incident["projected_utilization_pct"].nil?, incident.dig("hub_load", "unavailable"))
check("View Hub deep link", incident.dig("links", "hub").to_s.include?("hub=#{hub.code}"), incident.dig("links", "hub"))

section "Delivery"
report_delivery(alert["id"])
finish!
