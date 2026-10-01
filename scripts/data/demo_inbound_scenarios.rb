# Demo-ready dataset for the 5 "trucks in transit into/out of Indore"
# scenarios (task section 13) and their package/weight realism (sections
# 4-5). Reuses existing hubs/vehicles/trips wherever they already fit the
# brief instead of inventing new ones - see the per-section comments below
# for exactly which existing record each scenario reuses.
#
#   bin/rails runner scripts/data/demo_inbound_scenarios.rb
#
# Idempotent: the one new Trip this creates is skipped if that vehicle
# already has an in-transit trip, and package top-up is skipped for any
# waybill that already has >= 40 packages.
require "digest"

puts "=" * 70
puts "DEMO SCENARIOS: 5 Indore-centric trucks + realistic packages/weight"
puts "=" * 70

INDORE = Hub.find_by!(code: "CC-HUB-016")
MUMBAI = Hub.find_by!(code: "CC-HUB-011")

# --- 1. Indore -> Mumbai (the one requested journey with no existing
# in-transit POC trip - Bhopal/Ratlam(via Ujjain)/Ahmedabad already have
# real in-transit POC trips, reused as-is below). Reuses Nashik, an
# existing hub location roughly on that corridor, as the waypoint - the
# same pattern db/seeds/fleet_monitoring_poc.rb uses for its own curated
# routes (a real city's Location as the vehicle's current position, no
# road geometry implied - see GeoDistance/EtaImpactService's great-circle
# model). Vehicle: an existing Indore-hub POC vehicle with no current trip.
existing_mumbai_trip = Trip.status_in_transit.where(origin_hub_id: INDORE.id, destination_hub_id: MUMBAI.id)
                           .joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).order(:id).first

mumbai_vehicle = existing_mumbai_trip&.vehicle

if existing_mumbai_trip
  puts "  ⊘ #{mumbai_vehicle.number} already has an in-transit Indore -> Mumbai trip (##{existing_mumbai_trip.id}) - skipping (idempotent)."
else
  mumbai_vehicle = Vehicle.fleet_monitoring_poc.where(hub_id: INDORE.id).status_active
                          .where.not(id: Trip.status_in_transit.select(:vehicle_id))
                          .order(:capacity).last # pick the largest-capacity idle one

  if mumbai_vehicle.nil?
    puts "  ⊘ No idle Indore POC vehicle available for a new Mumbai trip - skipping."
    mumbai_vehicle = nil
  end
end

if mumbai_vehicle && existing_mumbai_trip.nil?
  # A placeholder schedule - it gets replaced immediately below by
  # FleetMonitoring::VehiclePositionPlanner's own progress fraction, the
  # exact logic scripts/data/regenerate_vehicle_positions.rb uses to keep
  # every other vehicle's position and trip timing coherent (position on
  # the route, predicted ETA close to planned). Using anything else here
  # (e.g. a hand-picked waypoint) risks the same route/ETA mismatch that
  # script exists to prevent.
  trip = Trip.create!(
    vehicle: mumbai_vehicle,
    origin_hub: INDORE,
    destination_hub: MUMBAI,
    status: "in_transit",
    departure_at: Time.current - 3.hours,
    expected_arrival_at: Time.current + 5.hours,
    route_info: "#{INDORE.name} to #{MUMBAI.name} via Nashik"
  )

  plan = FleetMonitoring::VehiclePositionPlanner.new(mumbai_vehicle, trip: trip).plan
  pace = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH
  total_hours = plan.path_km / pace
  elapsed_hours = plan.progress * total_hours
  trip.update!(departure_at: Time.current - elapsed_hours.hours, expected_arrival_at: Time.current + (total_hours - elapsed_hours).hours)

  # The vehicle gets its own dedicated Location row (never a hub's or
  # another vehicle's shared row - see regenerate_vehicle_positions.rb's
  # header comment for why).
  point = Location.create!(city: "Nashik", state: "Maharashtra", country: "India", latitude: plan.lat, longitude: plan.lng)
  mumbai_vehicle.update!(current_location_id: point.id, last_known_latitude: plan.lat, last_known_longitude: plan.lng, last_location_at: Time.current - 8.minutes)
  puts "  ✓ Created Indore -> Mumbai trip ##{trip.id} on #{mumbai_vehicle.number} (#{(plan.progress * 100).round}% of the way, near Nashik)"
end

# --- 2. Pick the 5 demo trucks: one per requested journey. Ratlam already
# has 10 real in-transit POC trips (all "via Ujjain", since that's this
# dataset's real route for it - see fleet_monitoring_poc.rb) so two
# different ones stand in for "Indore -> Ratlam" and "Indore -> Ujjain ->
# Ratlam", which are the same real route here; noted in the final report
# rather than inventing a separate Ujjain hub the task said not to add.
def indore_trip_to(destination_hub_code)
  destination = Hub.find_by(code: destination_hub_code)
  return nil unless destination

  Trip.status_in_transit.where(origin_hub_id: INDORE.id, destination_hub_id: destination.id)
      .joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).order(:id).to_a
end

ratlam_trips = indore_trip_to("HUB-RTM")
demo_trips = {
  "Indore -> Ratlam (via Ujjain)" => ratlam_trips[0],
  "Indore -> Bhopal" => indore_trip_to("CC-HUB-019")&.first,
  "Indore -> Ahmedabad (via Jhabua)" => indore_trip_to("CC-HUB-013")&.first,
  "Indore -> Ujjain -> Ratlam" => ratlam_trips[1],
  "Indore -> Mumbai (via Nashik)" => Trip.where(vehicle_id: mumbai_vehicle&.id, status: "in_transit").first
}.compact

puts "\nDemo trucks selected:"
demo_trips.each { |label, trip| puts "  #{label}: #{trip.vehicle.number}" }

# --- 3. Package/weight realism (sections 4-5) for each demo truck's
# busiest waybill: top up to 40-60 packages (varied, not a flat 50) and an
# aggregate weight around ~500kg (varied), always <= the vehicle's own
# capacity. New Package rows only (never duplicating an identifier), no
# Order involved (task section 4: "we do NOT need Orders right now") - so
# these packages' weight lives only in the waybill's own total_weight
# column, consistent with this schema's existing rule that only Order
# carries a weight figure (see Waybill#recalculate_totals!), not Package.
TARGET_PACKAGES_MIN = 40
TARGET_PACKAGES_MAX = 60
TARGET_WEIGHT_KG = 500.0

def topped_up?(waybill)
  waybill.total_packages.to_i >= TARGET_PACKAGES_MIN
end

def next_package_identifiers(count, seed_key)
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

puts "\nPackage/weight top-up:"
def ensure_waybill!(trip)
  existing = trip.waybills.order(total_packages: :desc).first
  return existing if existing

  # A brand-new demo trip (e.g. the Indore -> Mumbai one above) has no
  # packages of its own yet for scripts/data/seed_waybills.rb to group, so
  # it creates one directly here instead - same 12-digit numbering as
  # everywhere else (see realistic_waybill_data.rb).
  number = format("%012d", Random.new(Digest::MD5.hexdigest("waybill-for-trip-#{trip.id}").to_i(16)).rand(100_000_000_000..999_999_999_999))
  number = "#{number[0...-1]}1" while Waybill.exists?(waybill_number: number) # trivial deterministic bump on collision
  Waybill.create!(
    waybill_number: number,
    vehicle: trip.vehicle,
    trip: trip,
    origin_hub_id: trip.origin_hub_id,
    destination_hub_id: trip.destination_hub_id,
    status: "in_transit",
    planned_departure_at: trip.departure_at,
    expected_arrival_at: trip.expected_arrival_at,
    total_packages: 0,
    total_weight: 0
  )
end

demo_trips.each do |label, trip|
  waybill = ensure_waybill!(trip)
  if topped_up?(waybill)
    puts "  ⊘ #{label} (#{trip.vehicle.number}): #{waybill.waybill_number} already has #{waybill.total_packages} packages - skipping (idempotent)"
    next
  end

  rng = Random.new(Digest::MD5.hexdigest("demo-#{waybill.id}").to_i(16))
  target_count = rng.rand(TARGET_PACKAGES_MIN..TARGET_PACKAGES_MAX)
  new_count = target_count - waybill.total_packages.to_i
  # Realistic aggregate weight: target ~500kg with +/-15% variation, but
  # never above the vehicle's own capacity (task section 5, hard rule).
  capacity = trip.vehicle.capacity.to_f
  target_weight = TARGET_WEIGHT_KG * (0.85 + rng.rand * 0.3)
  target_weight = [ target_weight, capacity * 0.6 ].min if capacity.positive? # stay well clear of capacity, not just under it

  identifiers = next_package_identifiers(new_count, "demo-packages-#{waybill.id}")
  Package.transaction do
    identifiers.each do |identifier|
      Package.create!(
        identifier: identifier,
        location_type: "Hub",
        location_id: trip.origin_hub_id,
        status: "in_transit",
        trip_id: trip.id,
        waybill_id: waybill.id
      )
    end
    waybill.update!(total_packages: target_count, total_weight: target_weight.round(2))
  end
  puts "  ✓ #{label} (#{trip.vehicle.number}): #{waybill.waybill_number} -> #{target_count} packages, #{target_weight.round(1)}kg (capacity #{capacity.to_i}kg)"
end

puts "\nDone."
