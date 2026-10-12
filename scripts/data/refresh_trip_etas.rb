# Brings the map's in-transit trips' schedule up to date with the current
# time, so ETAs are realistic (not "315 hours late" on a trip planned weeks
# ago) and a diverted truck's card ETA equals its diversion's revised ETA.
#
#   bin/rails runner scripts/data/refresh_trip_etas.rb           # dry run: prints what would change
#   APPLY=1 bin/rails runner scripts/data/refresh_trip_etas.rb   # writes
#
# Re-run it before a demo; trips that are already up to date are skipped.
#
# Touches ONLY, for the current in-transit trips of map trucks whose schedule
# is stale:
#   - trips.departure_at / expected_arrival_at
#   - expected_arrival_at / planned_departure_at of those trips' OPEN waybills
#     (shifted by the same amount as the trip)
#   - those trips' ACTIVE route diversions, recalculated with the existing
#     RouteDiversionImpactService (revised ETA, delay, affected counts)
# Never touches vehicle positions, statuses, routes, hubs, packages, orders,
# alerts or anything else, and sends no notifications (none of these models
# trigger alerting).
#
# New schedule: departure = now - (distance already covered / pace),
# arrival = departure + planned route / pace - the same rule as
# scripts/data/regenerate_vehicle_positions.rb, but with the truck's actual
# position, which is left where it is. With it, the live predicted ETA
# equals the planned ETA (or, when diverted, the revised ETA).
COHERENCE_MINUTES = 30
PACE = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH
apply = ENV["APPLY"] == "1"
now = Time.current.change(sec: 0)

trips = FleetMonitoring::HubVehicleFlow.current_trips
          .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location).to_a
diversions = RouteDiversion.active.where(trip_id: trips.map(&:id)).order(diverted_at: :desc).group_by(&:trip_id)

puts "#{apply ? 'APPLYING' : 'DRY RUN (set APPLY=1 to write)'} - now #{now.in_time_zone('Asia/Kolkata')}"
refreshed = skipped = unavailable = 0

trips.each do |trip|
  vehicle = trip.vehicle
  diversion = diversions[trip.id]&.first
  eta = EtaImpactService.new(trip, vehicle: vehicle, diversion: diversion, now: now)
  reference = diversion&.revised_eta || trip.expected_arrival_at
  if eta.predicted_eta && reference && reference > now && (eta.predicted_eta - reference).abs <= COHERENCE_MINUTES.minutes
    skipped += 1
    next
  end

  remaining = eta.remaining_km
  route_km = GeoDistance.path_km(eta.current_route)
  planned_km = GeoDistance.path_km(eta.planned_route)
  unless remaining && route_km.positive? && planned_km.positive?
    unavailable += 1
    puts "  ⊘ #{vehicle.number} trip ##{trip.id}: no position or route coordinates - left as is"
    next
  end

  traffic = diversion ? diversion.traffic_factor.to_f : 1.0
  covered = [ route_km - remaining, 0 ].max
  departure = (now - (covered * traffic / PACE).hours).change(sec: 0)
  arrival = (departure + (planned_km / PACE).hours).change(sec: 0)
  shift = trip.expected_arrival_at ? arrival - trip.expected_arrival_at : nil
  waybills = trip.waybills.open.to_a

  puts "  ↻ #{vehicle.number} trip ##{trip.id}: arrival #{trip.expected_arrival_at&.in_time_zone('Asia/Kolkata')&.strftime('%d %b %H:%M')} -> " \
       "#{arrival.in_time_zone('Asia/Kolkata').strftime('%d %b %H:%M')}, #{waybills.size} open waybill(s)#{diversion ? ', diversion recalculated' : ''}"
  refreshed += 1
  next unless apply

  OperationsRecord.transaction do
    waybills.each do |waybill|
      attrs = { planned_departure_at: departure }
      attrs[:expected_arrival_at] = waybill.expected_arrival_at + shift if shift && waybill.expected_arrival_at
      waybill.update!(attrs)
    end
    trip.update!(departure_at: departure, expected_arrival_at: arrival)
    RouteDiversionImpactService.new(diversion.reload, now: now).apply! if diversion
  end
end

puts "#{trips.size} in-transit trips: #{refreshed} #{apply ? 'refreshed' : 'would be refreshed'}, #{skipped} already up to date, #{unavailable} left as is."
