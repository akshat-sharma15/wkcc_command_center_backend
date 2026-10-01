# Quick follow-up to spread_indore_corridor_vehicles.rb: that script only
# repositioned vehicles ALONG their existing route, which - correctly
# pointed out - still looks like "a line" since the route itself is a
# line. This actually changes 15 vehicles' ROUTES to real, different
# corridors (Indore->Jabalpur, Jabalpur->Lucknow, Mumbai->Hyderabad),
# passing near Sagar/Rewa/Sambhajinagar as requested, updating every
# dependent field consistently: trip origin/destination/route_info,
# the attached waybill(s)' origin/destination hubs, their packages'
# location (packages "at" the trip's origin hub, per the existing
# convention elsewhere in this codebase), current position (fresh, on the
# new route), and departure/arrival timing (re-anchored so predicted vs
# planned ETA stays consistent).
#
#   bin/rails runner scripts/data/reroute_indore_to_new_corridors.rb
#
# Sagar/Rewa/Sambhajinagar have no Hub record in this dataset (checked
# first - only Jabalpur and Lucknow do), so they're added as WAYPOINT-ONLY
# Locations, the exact same pattern already used for Dewas/Ujjain/Jhabua/
# Nashik elsewhere in this codebase - not new hubs, no new model.
#
# All 15 source vehicles are OUTBOUND from Indore (not inbound) in their
# current route, so this does not touch Indore's inbound count - only
# reduces how many vehicles visually sit on the outbound corridors near it.
#
# Idempotent: skips a vehicle whose trip's route already matches its
# target pair.
require "digest"

puts "=" * 70
puts "REROUTE 15 INDORE VEHICLES TO JABALPUR / LUCKNOW / MUMBAI-HYDERABAD"
puts "=" * 70

WAYPOINTS = {
  "Sagar" => [ "Madhya Pradesh", 23.8388, 78.7378 ],
  "Rewa" => [ "Madhya Pradesh", 24.5362, 81.2961 ],
  "Sambhajinagar" => [ "Maharashtra", 19.8762, 75.3433 ]
}.freeze

WAYPOINTS.each do |city, (state, lat, lng)|
  Location.find_or_create_by!(city: city, state: state) { |l| l.country = "India"; l.latitude = lat; l.longitude = lng }
end
puts "Waypoint locations ensured: #{WAYPOINTS.keys.join(', ')}"

PLANS = [
  { vehicles: %w[MP09AH9140 RJ14ZU0987 MP04IO5839 RJ14PS9522 RJ14VI1753],
    origin: "CC-HUB-016", destination: "CC-HUB-022", via: "Sagar" },
  { vehicles: %w[RJ14ZG0702 MP09FI1152 MP09YW8198 MP09DU9316 MP09IN3537],
    origin: "CC-HUB-022", destination: "CC-HUB-004", via: "Rewa" },
  # Mumbai, not Nagpur - Nagpur->Hyderabad via Sambhajinagar was a ~63%
  # detour off the direct line (846km via vs 500km direct), which
  # produced a real ETA inconsistency for 2 of these 5 vehicles (caught by
  # scripts/data/validate_operational_consistency.rb after the first
  # run). Mumbai->Hyderabad via Sambhajinagar is a ~14% detour (705km vs
  # 621km direct) - the waypoint is actually roughly on that route.
  { vehicles: %w[MP09NZ9165 MP09PZ4276 MP09SA9994 MP09TL9267 MP19JW5060],
    origin: "CC-HUB-011", destination: "CC-HUB-026", via: "Sambhajinagar" }
].freeze

PLANNING_SPEED_KMPH = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH
PROGRESS_SLOTS = [ 0.2, 0.35, 0.5, 0.65, 0.8 ].freeze
SIDE_OFFSETS_KM = [ -2.5, 2.0, -1.5, 2.5, -2.0 ].freeze

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
      dx = (coord(to, :lng) - coord(from, :lng)) * Math.cos(coord(from, :lat) * Math::PI / 180) * 111.0
      dy = (coord(to, :lat) - coord(from, :lat)) * 111.0
      length = Math.hypot(dx, dy)
      next base if length.zero?

      offset_km = side_km * Math.sin(Math::PI * t)
      return { lat: base[:lat] + (-dy / length * offset_km) / 111.0,
               lng: base[:lng] + (dx / length * offset_km) / (111.0 * Math.cos(base[:lat] * Math::PI / 180)) }
    end
    target -= leg
  end
  path.last
end

changed = []
skipped = []

PLANS.each do |plan|
  origin_hub = Hub.find_by!(code: plan[:origin])
  destination_hub = Hub.find_by!(code: plan[:destination])
  via_point = { lat: WAYPOINTS[plan[:via]][1], lng: WAYPOINTS[plan[:via]][2] }
  origin_point = EtaImpactService.hub_point(origin_hub)
  destination_point = EtaImpactService.hub_point(destination_hub)
  path = [ origin_point, via_point.merge(name: plan[:via]), destination_point ]
  total_km = GeoDistance.path_km(path)
  total_hours = [ total_km / PLANNING_SPEED_KMPH, 0.5 ].max

  plan[:vehicles].each_with_index do |number, index|
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

    if trip.origin_hub_id == origin_hub.id && trip.destination_hub_id == destination_hub.id
      skipped << [ number, "already on this route (idempotent)" ]
      next
    end

    old_route = "#{trip.origin_hub.code}->#{trip.destination_hub.code}"
    old_origin_hub_id = trip.origin_hub_id
    progress = PROGRESS_SLOTS[index % PROGRESS_SLOTS.size]
    side_km = SIDE_OFFSETS_KM[index % SIDE_OFFSETS_KM.size]
    point = point_along(path, progress, side_km)
    elapsed_hours = total_hours * progress

    Vehicle.transaction do
      trip.update!(
        origin_hub_id: origin_hub.id, destination_hub_id: destination_hub.id,
        route_info: "#{origin_hub.name} to #{destination_hub.name} via #{plan[:via]}",
        departure_at: Time.current - elapsed_hours.hours,
        expected_arrival_at: Time.current + (total_hours - elapsed_hours).hours
      )
      trip.waybills.each do |waybill|
        waybill.update!(
          origin_hub_id: origin_hub.id, destination_hub_id: destination_hub.id,
          planned_departure_at: trip.departure_at, expected_arrival_at: trip.expected_arrival_at
        )
        # Packages sit "at" the trip's origin hub while awaiting dispatch,
        # per the same convention used everywhere else in this codebase
        # (see db/seeds/fleet_monitoring_poc.rb) - move them to match.
        Package.where(waybill_id: waybill.id, location_type: "Hub", location_id: old_origin_hub_id)
               .update_all(location_id: origin_hub.id) # rubocop:disable Rails/SkipsModelValidations
      end
      new_location = Location.create!(city: plan[:via], state: WAYPOINTS[plan[:via]][0],
                                       country: "India", latitude: point[:lat].round(6), longitude: point[:lng].round(6))
      vehicle.update!(current_location_id: new_location.id, last_known_latitude: point[:lat].round(6),
                      last_known_longitude: point[:lng].round(6), last_location_at: Time.current - rand(1..12).minutes)
    end

    changed << { number: number, old_route: old_route, new_route: "#{plan[:origin]}->#{plan[:destination]} via #{plan[:via]}",
                 trip_id: trip.id, waybills: trip.waybills.pluck(:waybill_number).join(",") }
  end
end

puts "\nChanged (#{changed.size}):"
changed.each { |c| puts "  #{c[:number]}  #{c[:old_route]} -> #{c[:new_route]}  trip=#{c[:trip_id]}  waybills=#{c[:waybills]}" }
puts "\nSkipped (#{skipped.size}):" if skipped.any?
skipped.each { |n, reason| puts "  #{n}: #{reason}" }

puts "\nInbound counts after reroute:"
counts = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).group(:destination_hub_id).count
%w[CC-HUB-016 CC-HUB-022 CC-HUB-004 CC-HUB-020 CC-HUB-026 HUB-RTM CC-HUB-019 CC-HUB-013 CC-HUB-011].each do |code|
  h = Hub.find_by(code: code)
  puts "  #{h.name}: #{counts[h.id] || 0} inbound"
end
