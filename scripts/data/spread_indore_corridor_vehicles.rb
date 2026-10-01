# Quick visual-distribution fix (task: "map looks too clustered/linear
# around Indore"). Repositions a fixed list of 30 IN_TRANSIT vehicles that
# were bunched close together on the Indore<->Bhopal/Ratlam/Agra/Ahmedabad/
# Jaipur corridors to well-SPREAD points along their OWN EXISTING route -
# no trip, route, waybill, origin or destination changes at all, so hub
# inbound/outbound counts and every relationship stay exactly as they are.
#
#   bin/rails runner scripts/data/spread_indore_corridor_vehicles.rb BATCH=1
#   bin/rails runner scripts/data/spread_indore_corridor_vehicles.rb BATCH=2
#   bin/rails runner scripts/data/spread_indore_corridor_vehicles.rb BATCH=3
#
# For each vehicle: assigns a deterministic progress fraction (spread
# across 0.1-0.9, distinct per vehicle within its batch) along its trip's
# EXISTING current_route (EtaImpactService - origin -> via -> destination,
# or the diverted path), using the same point_along/perpendicular-offset
# math as FleetMonitoring::VehiclePositionPlanner so the result looks like
# the rest of the fleet. departure_at/expected_arrival_at are re-anchored
# to that same progress fraction (same technique as
# scripts/data/regenerate_vehicle_positions.rb) so predicted-vs-planned
# ETA stays consistent - this is the one dependent field a position change
# must also update, per the task's own consistency rules.
#
# Idempotent within a batch: rerunning the same BATCH recomputes the exact
# same target (deterministic per vehicle number + assigned progress), so
# it's safe to rerun.
require "digest"

BATCHES = {
  1 => %w[MP09AH9140 RJ14ZU0987 MP04IO5839 RJ14PS9522 RJ14VI1753 RJ14ZG0702 MP09FI1152 MP09YW8198 MP04FH7455 MP04XL4719],
  2 => %w[MP09DU9316 MP09IN3537 MP09NZ9165 MP09PZ4276 MP09SA9994 MP09TL9267 MP19HL4967 MP19JW5060 MP19VB3843 MP19XL2771],
  3 => %w[MP09MB7026 RJ14CG4274 RJ14KJ3694 RJ14WT0940 MP04GF2900 MP04OD4410 MP04US3126 MP09AK9943 MP09KE6562 MP09PX8893]
}.freeze

# Evenly spread, not bunched - assigned in list order within each batch so
# vehicles sharing a corridor land at visibly different points along it.
PROGRESS_SLOTS = [ 0.12, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82, 0.88, 0.18 ].freeze
SIDE_OFFSET_KM = [ -3.5, 3.0, -2.0, 2.5, -3.0, 1.5, -1.0, 3.5, -2.5, 1.0 ].freeze
PLANNING_SPEED_KMPH = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH

batch_number = (ENV["BATCH"] || ARGV.first).to_i
numbers = BATCHES[batch_number]
abort("Usage: BATCH=1|2|3 bin/rails runner scripts/data/spread_indore_corridor_vehicles.rb") unless numbers

puts "=" * 70
puts "SPREAD INDORE-CORRIDOR VEHICLES - BATCH #{batch_number} (#{numbers.size} vehicles)"
puts "=" * 70

# Same point-along-polyline + perpendicular-offset math as
# FleetMonitoring::VehiclePositionPlanner#point_along/#perpendicular,
# parameterised by an explicit progress/side instead of a vehicle-seeded
# random one, so this batch's spread is deliberate, not incidental.
#
# `coord` reads either key style: current_route returns symbol-keyed
# points when built fresh from EtaImpactService.hub_point/via_point, but
# STRING-keyed points for an actively-diverted trip (current_route then
# prefers RouteDiversion#diverted_path, a JSONB column - Postgres JSON has
# no symbols, so it always round-trips as string keys). Caught this on
# MP09YW8198 (an actively-diverted vehicle) landing at (0.0, 0.0) in the
# first pass, before its bad coordinates were reported as final.
def coord(point, key)
  (point[key] || point[key.to_s]).to_f
end

def point_along(path, fraction, side_km)
  target = GeoDistance.path_km(path) * fraction
  path.each_cons(2) do |from, to|
    leg = GeoDistance.km(from, to)
    if target <= leg || to.equal?(path.last)
      t = leg.zero? ? 0 : [ target / leg, 1.0 ].min
      base = { lat: coord(from, :lat) + (coord(to, :lat) - coord(from, :lat)) * t,
               lng: coord(from, :lng) + (coord(to, :lng) - coord(from, :lng)) * t }
      return perpendicular(base, from, to, side_km * Math.sin(Math::PI * t))
    end
    target -= leg
  end
  path.last
end

def perpendicular(base, from, to, km)
  dx = (coord(to, :lng) - coord(from, :lng)) * Math.cos(coord(from, :lat) * Math::PI / 180) * 111.0
  dy = (coord(to, :lat) - coord(from, :lat)) * 111.0
  length = Math.hypot(dx, dy)
  return base if length.zero?

  { lat: base[:lat] + (-dy / length * km) / 111.0,
    lng: base[:lng] + (dx / length * km) / (111.0 * Math.cos(base[:lat] * Math::PI / 180)) }
end

changed = []
skipped = []

numbers.each_with_index do |number, index|
  vehicle = Vehicle.find_by(number: number)
  if vehicle.nil?
    skipped << [ number, "vehicle not found" ]
    next
  end

  trip = vehicle.trips.status_in_transit.order(departure_at: :desc).first
  if trip.nil?
    skipped << [ number, "no in-transit trip" ]
    next
  end

  eta = EtaImpactService.new(trip, vehicle: vehicle)
  path = eta.current_route
  if path.size < 2
    skipped << [ number, "route has no geometry" ]
    next
  end

  old_location = vehicle.current_geo_location
  old_lat, old_lng = old_location&.latitude, old_location&.longitude

  progress = PROGRESS_SLOTS[index % PROGRESS_SLOTS.size]
  side_km = SIDE_OFFSET_KM[index % SIDE_OFFSET_KM.size]
  point = point_along(path, progress, side_km)

  total_hours = [ GeoDistance.path_km(path) / PLANNING_SPEED_KMPH, 0.5 ].max
  elapsed_hours = total_hours * progress

  Vehicle.transaction do
    new_location = Location.create!(
      city: old_location&.city || trip.origin_hub.geo_location&.city,
      state: old_location&.state || trip.origin_hub.geo_location&.state,
      country: "India", latitude: point[:lat].round(6), longitude: point[:lng].round(6)
    )
    vehicle.update!(current_location_id: new_location.id, last_known_latitude: point[:lat].round(6),
                    last_known_longitude: point[:lng].round(6), last_location_at: Time.current - rand(1..12).minutes)
    trip.update!(departure_at: Time.current - elapsed_hours.hours, expected_arrival_at: Time.current + (total_hours - elapsed_hours).hours)
  end

  changed << {
    number: number, old: old_lat && old_lng ? "#{old_lat.round(4)},#{old_lng.round(4)}" : "n/a",
    new: "#{point[:lat].round(4)},#{point[:lng].round(4)}", trip_id: trip.id,
    route: "#{trip.origin_hub.code}->#{trip.destination_hub.code}",
    waybill: trip.waybills.pluck(:waybill_number).join(",").presence || "none",
    progress: progress
  }
end

puts "\nChanged (#{changed.size}):"
changed.each { |c| puts "  #{c[:number]}  #{c[:old]} -> #{c[:new]}  progress=#{c[:progress]}  trip=#{c[:trip_id]} #{c[:route]}  waybill=#{c[:waybill]}" }
puts "\nSkipped (#{skipped.size}):" if skipped.any?
skipped.each { |n, reason| puts "  #{n}: #{reason}" }
