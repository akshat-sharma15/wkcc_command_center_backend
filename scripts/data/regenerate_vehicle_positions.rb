# Re-places every Fleet Monitoring (map) vehicle at a route-consistent,
# deterministic position (FleetMonitoring::VehiclePositionPlanner) and
# keeps each current trip's timing coherent with that position.
#
#   bin/rails runner scripts/data/regenerate_vehicle_positions.rb
#
# - Only touches the synthetic POC fleet's position columns (vehicle
#   lat/lng/current location) and the timing of their CURRENT trips (plus
#   the demo expected-arrival on those trips' open waybills). Vehicle ids,
#   numbers, statuses, hubs, drivers and trip routes are never changed.
# - Positions are seeded per vehicle number: re-running leaves every
#   vehicle exactly where it is (it is skipped when already in place).
# - A current trip is re-anchored only when its timing no longer matches
#   the position (planned ETA already passed, or predicted vs planned ETA
#   more than COHERENCE_MINUTES apart; revised ETA for a diverted trip): departure = now - distance already
#   covered / pace, arrival = departure + planned route / pace. Active
#   diversions on a re-anchored trip get their impact recalculated.
# - A vehicle's own Location row is updated in place; a row shared with a
#   hub or another vehicle is never moved - the vehicle gets its own row.
COHERENCE_MINUTES = 30
PACE = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH

puts "=" * 70
puts "REGENERATE VEHICLE POSITIONS"
puts "=" * 70

now = Time.current.change(sec: 0)
vehicles = Vehicle.fleet_monitoring_poc.includes(:current_geo_location, hub: :geo_location).order(:number).to_a
trips = FleetMonitoring::HubVehicleFlow.current_trips.includes(origin_hub: :geo_location, destination_hub: :geo_location).index_by(&:vehicle_id)
diversions = RouteDiversion.active.where(trip_id: trips.values.map(&:id)).index_by(&:trip_id)

# Reference cities for the vehicle's city/state label: hub cities and the
# waypoint cities trips run through.
via_cities = trips.values.filter_map { |trip| EtaImpactService.via_point(trip)&.dig(:name) }.uniq
references = (Location.where(id: Hub.where.not(location_id: nil).select(:location_id)).to_a +
              via_cities.filter_map { |city| EtaImpactService.via_point_location(city) }).uniq(&:id)
shared_location_ids = Hub.where.not(location_id: nil).pluck(:location_id).to_set
location_usage = Vehicle.where.not(current_location_id: nil).group(:current_location_id).count

moved = 0
reanchored = 0
recalculated = []

vehicles.each do |vehicle|
  trip = trips[vehicle.id]
  diversion = trip && diversions[trip.id]
  plan = FleetMonitoring::VehiclePositionPlanner.new(vehicle, trip: trip, diversion: diversion).plan
  next puts("  ⊘ #{vehicle.number}: home hub has no coordinates") unless plan

  target = { lat: plan.lat, lng: plan.lng }
  city = references.min_by { |location| GeoDistance.km(target, { lat: location.latitude.to_f, lng: location.longitude.to_f }) }
  current = vehicle.current_geo_location

  Vehicle.transaction do
    in_place = current && GeoDistance.km(target, { lat: current.latitude.to_f, lng: current.longitude.to_f }) < 0.05 &&
               current.city == city.city
    unless in_place
      shared = current.nil? || shared_location_ids.include?(current.id) || location_usage.fetch(current.id, 0) > 1
      attrs = { city: city.city, state: city.state, country: "India", latitude: plan.lat, longitude: plan.lng }
      location = shared ? Location.create!(attrs) : current.tap { |l| l.update!(attrs) }
      vehicle.update_columns( # rubocop:disable Rails/SkipsModelValidations - position telemetry, not an alertable change
        current_location_id: location.id, current_location: "#{city.city}, #{city.state}",
        last_known_latitude: plan.lat, last_known_longitude: plan.lng,
        last_location_at: now - (1 + FleetMonitoring::VehiclePositionPlanner.rng_for(vehicle).rand(20)).minutes
      )
      vehicle.current_geo_location = location
      moved += 1
    end

    next unless trip

    eta = EtaImpactService.new(trip, vehicle: vehicle, diversion: diversion, now: now)
    reference_eta = diversion&.revised_eta || trip.expected_arrival_at
    # A diverted trip's planned ETA may already have passed while its
    # revised ETA is still ahead - coherence is judged on the latter.
    coherent = trip.departure_at && trip.expected_arrival_at && reference_eta && reference_eta > now &&
               eta.predicted_eta && reference_eta && (eta.predicted_eta - reference_eta).abs <= COHERENCE_MINUTES.minutes
    next if coherent

    planned_km = GeoDistance.path_km(eta.planned_route)
    # Time already driven: covered distance at planning pace, slowed by an
    # active diversion's traffic factor - so the predicted arrival equals
    # the diversion's revised ETA once its impact is recalculated.
    traffic = diversion ? diversion.traffic_factor.to_f : 1.0
    departure = now - (plan.progress * plan.path_km * traffic / PACE).hours
    arrival = departure + (planned_km / PACE).hours
    shift = trip.expected_arrival_at ? arrival.change(sec: 0) - trip.expected_arrival_at : nil
    trip.waybills.open.find_each do |waybill|
      next unless shift && waybill.expected_arrival_at

      waybill.update!(expected_arrival_at: waybill.expected_arrival_at + shift, planned_departure_at: departure.change(sec: 0))
    end
    trip.update!(departure_at: departure.change(sec: 0), expected_arrival_at: arrival.change(sec: 0))
    reanchored += 1
    puts "  ↻ re-anchored #{vehicle.number} trip ##{trip.id}" if ENV["VERBOSE"]
    if diversion
      RouteDiversionImpactService.new(diversion.reload).apply!
      recalculated << diversion.id
    end
  end
end

puts "Vehicles: #{vehicles.size} · repositioned: #{moved} · trips re-anchored: #{reanchored} · diversions recalculated: #{recalculated.size}"
states = Vehicle.fleet_monitoring_poc.joins(:current_geo_location).group("locations.state").order("count_all DESC").count
puts "By state (#{states.size} states): #{states.map { |state, count| "#{state} #{count}" }.join(', ')}"
