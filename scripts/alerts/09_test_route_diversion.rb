# Scenario 3 - Route Diversion (route.diversion) on TRK-102:
#   planned  Indore -> Ujjain -> Ratlam
#   diverted Indore -> Dhar   -> Ratlam
#   bin/rails runner scripts/alerts/09_test_route_diversion.rb
# Creates the RouteDiversion through POST /api/v1/route-diversions (which
# calculates impact and publishes the incident), then checks the persisted
# impact, the alert enrichment, delivery, and the map endpoints/deep links.
# An active diversion from a previous run is resolved first.
require_relative "support/scenario_helpers"
include ScenarioHelpers

puts "=" * 70
puts "SCENARIO 3 - ROUTE DIVERSION"
puts "=" * 70

vehicle = Vehicle.find_by(number: ARGV[0].presence || "TRK-102")
abort("TRK-102 missing - run scripts/data/add_100_vehicles.rb") unless vehicle
trip = vehicle.trips.status_in_transit.order(departure_at: :desc).first
abort("#{vehicle.number} has no in-transit trip") unless trip
ujjain = Location.where(city: "Ujjain").order(:id).first
dhar = Location.where(city: "Dhar").order(:id).first
abort("Ujjain/Dhar locations missing - run scripts/data/add_100_vehicles.rb") unless ujjain && dhar

vehicle.route_diversions.active.find_each do |previous|
  previous.resolve!
  previous.alert&.resolve!(by: USER_ID, note: "Closed by scenario re-run") unless previous.alert.nil? || previous.alert.status_resolved?
  puts "  (resolved previous diversion ##{previous.id})"
end

section "Trigger"
puts "  #{vehicle.number} trip ##{trip.id}: #{trip.origin_hub.name} -> #{trip.destination_hub.name}"
status, body = api(:post, "/api/v1/route-diversions", {
  route_diversion: {
    vehicle_id: vehicle.id, trip_id: trip.id, traffic_factor: 1.2,
    reason: "Bridge closure on the Ujjain bypass - diverted via Dhar",
    original_path: [ { hub_id: trip.origin_hub_id }, { location_id: ujjain.id }, { hub_id: trip.destination_hub_id } ],
    diverted_path: [ { hub_id: trip.origin_hub_id }, { location_id: dhar.id }, { hub_id: trip.destination_hub_id } ]
  }
})
check("POST /api/v1/route-diversions", status == 201, "HTTP #{status} #{body['error'] if status != 201}")
abort unless status == 201
diversion = body
impact = diversion["impact"]

section "RouteDiversion ##{diversion['id']} impact"
show :original, impact["original_route"].map { |p| p["name"] }.join(" → ")
show :diverted, impact["diverted_route"].map { |p| p["name"] }.join(" → ")
show :original_km, diversion["original_distance_km"]
show :diverted_km, diversion["diverted_distance_km"]
show :extra_km, diversion["additional_distance_km"]
show :distance_basis, impact["distance_basis"]
show :delay_minutes, diversion["delay_minutes"]
show :original_eta, diversion["original_eta"]
show :revised_eta, diversion["revised_eta"]
show :fuel_litres, diversion["fuel_impact_litres"]
show :waybills, diversion["affected_waybills"]
show :packages, diversion["affected_packages"]
show :orders, diversion["affected_orders"]
show :revenue_risk, inr(diversion["revenue_risk"])
show :sla_risk, impact["sla_risk"]
show :dest_hub_util, impact.dig("destination_hub_impact", "projected_utilization_pct")
show :hub_congestion, impact["hub_congestion_risk"]
show :missed_departure, impact.dig("missed_departure_risk", "at_risk")
show :affected_vehicles, impact.dig("affected_vehicles", "vehicle_numbers")&.join(", ")
show :unavailable, impact["unavailable"].presence&.join("; ")
check("extra distance positive", diversion["additional_distance_km"].to_f.positive?)
check("delay and revised ETA calculated", diversion["delay_minutes"].to_i.positive? && diversion["revised_eta"].present?)
check("waybill/order impact", diversion["affected_waybills"].to_i.positive? && diversion["affected_orders"].to_i.positive?)
check("revenue risk persisted", !diversion["revenue_risk"].nil?)
check("incident alert linked", diversion["alert_id"].present?)

alert = Alert.find(diversion["alert_id"])
incident = alert.metadata["incident"]
section "Alert ##{alert.id}"
show :summary, incident["summary"]
check("alert enriched from diversion", incident["diversion_id"] == diversion["id"] && incident["delay_minutes"] == diversion["delay_minutes"])
%w[vehicle route hub].each { |k| check("#{k} deep link", incident.dig("links", k).present?, incident.dig("links", k)) }

section "Delivery"
notifications = report_delivery(alert.id)
slack = notifications.find { |n| n.channel == "slack" }
blocks = slack && SlackIncidentMessageBuilder.new(slack).blocks
check("Slack rich layout with View Incident/Truck/Route/Hub + lifecycle buttons",
      blocks && ([ "View Incident", "View Truck", "View Route", "View Hub", "Acknowledge", "Resolve" ] - blocks.last[:elements].map { |e| e[:text][:text] }).empty?)

section "Map endpoints"
status, overlay = api(:get, "/api/v1/fleet-monitoring/route-diversions/#{diversion['id']}")
check("GET fleet-monitoring/route-diversions/:id", status == 200 && overlay["diverted_path"].size == 3)
status, list = api(:get, "/api/v1/fleet-monitoring/vehicles")
row = list&.find { |v| v["pnr"] == vehicle.number }
check("vehicle list flags diversion", row && row["diverted"] && row["diversion_id"] == diversion["id"],
      row && "diverted=#{row['diverted']} incident=#{row.dig('active_incident', 'title')} waybills=#{row['waybill_count']}")
finish!
