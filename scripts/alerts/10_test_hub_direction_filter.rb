# Hub inbound/outbound map filter (GET /api/v1/fleet-monitoring/hubs/:code/vehicles).
#   bin/rails runner scripts/alerts/10_test_hub_direction_filter.rb [HUB_CODE]
# Verifies the server returns ONLY the requested direction's POC vehicles
# and that the result matches the underlying trips exactly.
require_relative "support/scenario_helpers"
include ScenarioHelpers

puts "=" * 70
puts "HUB INBOUND / OUTBOUND FILTER"
puts "=" * 70

hub = Hub.find_by!(code: ARGV[0].presence || "CC-HUB-016")
poc_trips = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
expected = {
  "inbound" => poc_trips.where(destination_hub_id: hub.id).distinct.pluck("vehicles.number").sort,
  "outbound" => poc_trips.where(origin_hub_id: hub.id).distinct.pluck("vehicles.number").sort
}
expected["all"] = (expected["inbound"] + expected["outbound"]).uniq.sort
puts "  Hub #{hub.name} (#{hub.code}); POC fleet #{Vehicle.fleet_monitoring_poc.count}"

%w[inbound outbound all].each do |direction|
  status, body = api(:get, "/api/v1/fleet-monitoring/hubs/#{hub.code}/vehicles?direction=#{direction}")
  rows = body&.fetch("vehicles", []) || []
  pnrs = rows.map { |row| row["pnr"] }.sort
  check("#{direction}: HTTP 200", status == 200)
  check("#{direction}: exactly the expected vehicles", pnrs == expected[direction], "#{pnrs.size} vehicles")
  unless direction == "all"
    check("#{direction}: every row tagged #{direction}", rows.all? { |row| row["direction"] == direction })
  end
  check("#{direction}: rows carry map fields", rows.all? { |row| %w[pnr lat lng status trip_id destination eta].all? { |k| row.key?(k) } })
end
status, = api(:get, "/api/v1/fleet-monitoring/hubs/#{hub.code}/vehicles?direction=sideways")
check("invalid direction rejected", status == 400)
finish!
