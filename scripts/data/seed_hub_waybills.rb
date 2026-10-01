# Adds ~50 waybills that are sitting AT A HUB rather than moving, which
# this dataset had none of - every one of the 360 existing waybills is on
# an in_transit trip, so the "AT HUB" branch of the waybill search
# (FleetMonitoring::SearchSuggestions#waybill_suggestion, which shows the
# holding hub instead of a route) could never actually appear.
#
#   bin/rails runner scripts/data/seed_hub_waybills.rb
#
# Each one is issued against a POC vehicle that is parked at its home hub
# (active, no in-transit trip), with:
#   - status "issued" - an OPEN waybill (Waybill::OPEN_STATUSES) that has
#     not departed, which is exactly what "at the hub" means here
#   - trip: nil - Waybill#trip is genuinely optional; these are documents
#     raised against a vehicle awaiting dispatch, so inventing a Trip for
#     them would be fabricating a journey that hasn't been planned
#   - origin_hub = the hub the vehicle is actually standing at, so the
#     search's `waybill.trip&.origin_hub || waybill.vehicle.hub` fallback
#     resolves to the right place
#   - destination_hub = a nearby real hub (nearest few by great-circle,
#     picked deterministically), so the corridor is regionally plausible
#     instead of a random cross-country pairing
#   - 40-60 packages and a weight budgeted PER VEHICLE (70% of capacity
#     split across that vehicle's waybills), the same capacity rule
#     scripts/data/realistic_waybill_packages.rb follows - a vehicle with
#     two waybills can't be loaded past its own rating
#   - real Package rows located at that hub, status "received"
#
# Nothing existing is modified: no trip, no vehicle, no existing waybill,
# and no hub inbound/outbound count (these carry no trip, so they never
# enter HubVehicleFlow).
#
# Idempotent: does nothing once TARGET_COUNT hub waybills already exist.
require "digest"

TARGET_COUNT = 50
PACKAGES_MIN = 40
PACKAGES_MAX = 60
CAPACITY_BUDGET_FRACTION = 0.7
NEAREST_HUB_CHOICES = 4

puts "=" * 70
puts "SEED HUB-RESIDENT WAYBILLS"
puts "=" * 70

existing = Waybill.status_issued.where(trip_id: nil).count
if existing >= TARGET_COUNT
  puts "#{existing} hub waybills already present - nothing to do (idempotent)."
  exit
end

vehicles = Vehicle.fleet_monitoring_poc.status_active
                  .where.not(id: Trip.status_in_transit.select(:vehicle_id))
                  .includes(hub: :geo_location).to_a
                  .select { |v| v.hub&.geo_location }
                  .sort_by(&:number)
abort("No parked POC vehicles with a located hub available") if vehicles.empty?

hubs = Hub.includes(:geo_location).select { |h| h.geo_location }
hub_points = hubs.to_h { |h| [ h.id, { lat: h.geo_location.latitude.to_f, lng: h.geo_location.longitude.to_f } ] }

# Nearest few hubs to each origin, so a waybill's destination is a
# plausible regional run rather than an arbitrary pairing.
def nearby_hubs(origin_hub, hubs, hub_points)
  origin = hub_points[origin_hub.id]
  hubs.reject { |h| h.id == origin_hub.id }
      .sort_by { |h| GeoDistance.km(origin, hub_points[h.id]) }
      .first(NEAREST_HUB_CHOICES)
end

def unique_waybill_number(seed_key)
  rng = Random.new(Digest::MD5.hexdigest(seed_key).to_i(16))
  loop do
    candidate = format("%012d", rng.rand(100_000_000_000..999_999_999_999))
    return candidate unless Waybill.exists?(waybill_number: candidate)
  end
end

def unique_package_identifiers(count, seed_key)
  rng = Random.new(Digest::MD5.hexdigest(seed_key).to_i(16))
  identifiers = []
  loop do
    candidate = format("CC-PKG-%06d", rng.rand(100_000..999_999))
    next if identifiers.include?(candidate) || Package.exists?(identifier: candidate)

    identifiers << candidate
    break if identifiers.size == count
  end
  identifiers
end

# Spread the target across the available vehicles (some carry two).
assignments = Array.new(TARGET_COUNT) { |i| vehicles[i % vehicles.size] }
per_vehicle_total = assignments.tally

created = []

assignments.each_with_index do |vehicle, index|
  origin_hub = vehicle.hub
  rng = Random.new(Digest::MD5.hexdigest("hub-waybill-#{vehicle.id}-#{index}").to_i(16))
  destination_hub = nearby_hubs(origin_hub, hubs, hub_points)[rng.rand(NEAREST_HUB_CHOICES)] ||
                    hubs.find { |h| h.id != origin_hub.id }
  next unless destination_hub

  package_count = rng.rand(PACKAGES_MIN..PACKAGES_MAX)
  capacity = vehicle.capacity.to_f
  share = capacity.positive? ? (capacity * CAPACITY_BUDGET_FRACTION) / per_vehicle_total[vehicle] : 500.0
  weight = [ share * (0.85 + rng.rand * 0.3), 50.0 ].max
  weight = [ weight, capacity ].min if capacity.positive?

  distance_km = GeoDistance.km(hub_points[origin_hub.id], hub_points[destination_hub.id])
  departure = Time.current + rng.rand(2..20).hours # awaiting dispatch
  arrival = departure + (distance_km / FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH).hours

  waybill = nil
  Waybill.transaction do
    waybill = Waybill.create!(
      waybill_number: unique_waybill_number("hub-waybill-#{vehicle.id}-#{index}"),
      vehicle: vehicle,
      trip: nil,
      origin_hub: origin_hub,
      destination_hub: destination_hub,
      status: "issued",
      planned_departure_at: departure,
      expected_arrival_at: arrival,
      total_packages: package_count,
      total_weight: weight.round(2)
    )
    unique_package_identifiers(package_count, "hub-waybill-pkgs-#{vehicle.id}-#{index}").each do |identifier|
      Package.create!(
        identifier: identifier,
        location_type: "Hub",
        location_id: origin_hub.id,
        status: "received",
        waybill_id: waybill.id
      )
    end
  end

  created << { number: waybill.waybill_number, hub: origin_hub.code, hub_name: origin_hub.name,
               destination: destination_hub.code, vehicle: vehicle.number,
               packages: package_count, weight: weight.round(1), capacity: capacity.to_i }
end

puts "\nCreated #{created.size} hub-resident waybills:\n\n"
created.first(10).each do |c|
  puts "  #{c[:number]}  AT #{c[:hub]} #{c[:hub_name]}  -> #{c[:destination]}  vehicle=#{c[:vehicle]}  #{c[:packages]} pkgs / #{c[:weight]}kg (cap #{c[:capacity]}kg)"
end
puts "  ... and #{created.size - 10} more" if created.size > 10

puts "\nHubs now holding waybills:"
Waybill.status_issued.where(trip_id: nil).group(:origin_hub_id).count.sort_by { |_, c| -c }.each do |hub_id, count|
  puts "  #{Hub.find(hub_id).name}: #{count}"
end

over = created.group_by { |c| c[:vehicle] }.select { |_, rows| rows.sum { |r| r[:weight] } > rows.first[:capacity] }
puts "\nVehicles loaded past capacity across their waybills: #{over.empty? ? '0 (none)' : over.keys.join(', ')}"
