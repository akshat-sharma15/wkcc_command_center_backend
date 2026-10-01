# Adds exactly 100 synthetic vehicles (TRK-101 .. TRK-200) to the Fleet
# Monitoring POC fleet, taking it from 100 to 200 map vehicles.
#
#   bin/rails runner scripts/data/add_100_vehicles.rb
#
# - Never touches existing vehicles: only numbers from the TRK-101..200 list
#   that don't exist yet are created, so a second run adds nothing.
# - Deterministic: one seeded Random drives every choice, so a fresh
#   environment gets the identical fleet.
# - Placement: 75 vehicles on the operational corridors the app already
#   showcases (Indore/Ujjain/Ratlam/Bhopal, Gujarat, Mumbai/Pune/Nashik,
#   Jaipur/Delhi NCR), 25 on other major Indian corridors. Every origin/
#   destination is a real existing Hub; in-transit vehicles sit on the
#   line between them (via a real waypoint city), parked/maintenance/
#   out-of-service vehicles at their hub with a small spiral offset so no
#   two markers coincide (same convention as db/seeds/fleet_monitoring_poc.rb).
# - Each vehicle gets a real hub, vendor (existing Vendor rows), a new
#   driver (WorkforceMember), and in-transit vehicles an in_transit Trip
#   carrying real backlog packages dispatched from the origin hub.
SEED = 20_260_929
NUMBERS = (101..200).map { |n| "TRK-#{n}" }.freeze
TARGET_POC_TOTAL = 200
AVERAGE_SPEED_KMPH = 42.0 # planning pace used to derive trip durations

# Waypoint cities not guaranteed to exist as Locations yet.
CITIES = {
  "Ujjain" => [ "Madhya Pradesh", 23.1765, 75.7885 ],
  "Dhar" => [ "Madhya Pradesh", 22.6013, 75.3025 ],
  "Dewas" => [ "Madhya Pradesh", 22.9676, 76.0534 ],
  "Sehore" => [ "Madhya Pradesh", 23.2032, 77.0844 ],
  "Jhabua" => [ "Madhya Pradesh", 22.7677, 74.5909 ],
  "Anand" => [ "Gujarat", 22.5645, 72.9289 ],
  "Bharuch" => [ "Gujarat", 21.7051, 72.9959 ],
  "Vapi" => [ "Gujarat", 20.3893, 72.9106 ],
  "Lonavala" => [ "Maharashtra", 18.7546, 73.4062 ],
  "Igatpuri" => [ "Maharashtra", 19.6958, 73.5626 ],
  "Ajmer" => [ "Rajasthan", 26.4499, 74.6399 ],
  "Behror" => [ "Rajasthan", 27.8889, 76.2860 ],
  "Chittorgarh" => [ "Rajasthan", 24.8887, 74.6269 ],
  "Adilabad" => [ "Telangana", 19.6641, 78.5320 ],
  "Kurnool" => [ "Andhra Pradesh", 15.8281, 78.0373 ],
  "Vellore" => [ "Tamil Nadu", 12.9165, 79.1325 ],
  "Kharagpur" => [ "West Bengal", 22.3460, 87.2320 ],
  "Etawah" => [ "Uttar Pradesh", 26.7856, 79.0158 ],
  "Unnao" => [ "Uttar Pradesh", 26.5393, 80.4878 ],
  "Betul" => [ "Madhya Pradesh", 21.9059, 77.8986 ],
  "Krishnagiri" => [ "Tamil Nadu", 12.5186, 78.2137 ]
}.freeze

# [origin hub code, destination hub code, via city, vehicle count]
CORRIDOR_ROUTES = [
  [ "CC-HUB-016", "HUB-RTM", "Ujjain", 10 ],     # Indore -> Ratlam (diversion showcase)
  [ "HUB-RTM", "CC-HUB-016", "Ujjain", 5 ],      # Ratlam -> Indore
  [ "CC-HUB-016", "CC-HUB-019", "Dewas", 6 ],    # Indore -> Bhopal
  [ "CC-HUB-019", "CC-HUB-016", "Sehore", 5 ],   # Bhopal -> Indore
  [ "CC-HUB-016", "CC-HUB-013", "Jhabua", 5 ],   # Indore -> Ahmedabad
  [ "CC-HUB-013", "CC-HUB-015", "Anand", 5 ],    # Ahmedabad -> Vadodara
  [ "CC-HUB-015", "CC-HUB-014", "Bharuch", 5 ],  # Vadodara -> Surat
  [ "CC-HUB-014", "CC-HUB-011", "Vapi", 6 ],     # Surat -> Mumbai
  [ "CC-HUB-011", "CC-HUB-012", "Lonavala", 6 ], # Mumbai -> Pune
  [ "CC-HUB-018", "CC-HUB-011", "Igatpuri", 5 ], # Nashik -> Mumbai
  [ "CC-HUB-002", "CC-HUB-001", "Behror", 6 ],   # Jaipur -> Delhi
  [ "CC-HUB-001", "CC-HUB-002", "Behror", 5 ],   # Delhi -> Jaipur
  [ "CC-HUB-002", "CC-HUB-016", "Chittorgarh", 6 ] # Jaipur -> Indore
].freeze

OTHER_ROUTES = [
  [ "CC-HUB-020", "CC-HUB-026", "Adilabad", 5 ],   # Nagpur -> Hyderabad
  [ "CC-HUB-026", "CC-HUB-025", "Kurnool", 5 ],    # Hyderabad -> Bengaluru
  [ "CC-HUB-025", "CC-HUB-027", "Krishnagiri", 4 ],# Bengaluru -> Chennai
  [ "CC-HUB-037", "CC-HUB-038", "Kharagpur", 4 ],  # Kolkata -> Bhubaneswar
  [ "CC-HUB-001", "CC-HUB-004", "Etawah", 4 ],     # Delhi -> Lucknow
  [ "CC-HUB-020", "CC-HUB-019", "Betul", 3 ]       # Nagpur -> Bhopal
].freeze

VEHICLE_SPECS = [
  [ "truck", 5000, 4.5 ], [ "truck", 8000, 4.0 ], [ "trailer", 10_000, 3.2 ],
  [ "mini_truck", 2000, 8.0 ], [ "mini_truck", 3500, 7.0 ], [ "van", 1000, 10.5 ]
].freeze

FIRST_NAMES = %w[Rakesh Suresh Mahesh Anil Deepak Rajendra Manoj Sunil Vinod Ramesh Harish Pradeep Santosh Imran Gurpreet Arjun Kiran Naveen Prakash Sanjay].freeze
LAST_NAMES = %w[Yadav Patel Chauhan Verma Singh Solanki Thakur Joshi Rathore Pawar Shaikh Reddy Naidu Das Gill Mishra Kumar Jadhav].freeze

# Status mix per 20 vehicles: 13 in transit, 4 parked, 2 maintenance, 1 out of service.
STATUS_CYCLE = (%w[in_transit] * 13 + %w[parked] * 4 + %w[maintenance] * 2 + %w[out_of_service]).freeze

def city_location(city)
  state, lat, lng = CITIES.fetch(city)
  Location.where(city: city, state: state).order(:id).first ||
    Location.create!(city: city, state: state, country: "India", latitude: lat, longitude: lng)
end

def point(location)
  { lat: location.latitude.to_f, lng: location.longitude.to_f }
end

# Position `fraction` of the way along the polyline, by distance.
def along(path, fraction)
  target = GeoDistance.path_km(path) * fraction
  path.each_cons(2) do |from, to|
    leg = GeoDistance.km(from, to)
    if target <= leg
      t = leg.zero? ? 0 : target / leg
      return { lat: from[:lat] + (to[:lat] - from[:lat]) * t, lng: from[:lng] + (to[:lng] - from[:lng]) * t }
    end
    target -= leg
  end
  path.last
end

def spiral_offset(center, index)
  angle = ((index * 137.50776) % 360.0) * Math::PI / 180.0
  radius_km = 0.3 + (index * 0.35)
  dlat = (radius_km / 111.0) * Math.cos(angle)
  dlng = (radius_km / (111.0 * Math.cos(center[:lat] * Math::PI / 180.0))) * Math.sin(angle)
  { lat: (center[:lat] + dlat).round(6), lng: (center[:lng] + dlng).round(6) }
end

def nearest_city(position, candidates)
  candidates.min_by { |location| GeoDistance.km(position, point(location)) }
end

puts "=" * 70
puts "ADD 100 VEHICLES (TRK-101 .. TRK-200)"
puts "=" * 70

before_poc = Vehicle.fleet_monitoring_poc.count
before_total = Vehicle.count
existing = Vehicle.where(number: NUMBERS).pluck(:number).to_set
missing = NUMBERS.reject { |number| existing.include?(number) }
puts "POC vehicles before: #{before_poc} (all vehicles: #{before_total}); TRK vehicles present: #{existing.size}/100"

rng = Random.new(SEED)
vendors = Vendor.order(:code).to_a
raise "No vendors found - run db/seeds/fleet_monitoring_poc.rb first" if vendors.empty?

hubs = Hub.includes(:geo_location).index_by(&:code)
routes = (CORRIDOR_ROUTES + OTHER_ROUTES).flat_map { |origin, destination, via, count| [ [ origin, destination, via ] ] * count }
raise "Route plan must cover exactly 100 vehicles (has #{routes.size})" unless routes.size == 100

reference_cities = Location.where(id: Hub.where.not(location_id: nil).select(:location_id)).to_a +
                   CITIES.keys.map { |city| city_location(city) }
alertable_fields = %w[status capacity]
created = 0

NUMBERS.each_with_index do |number, index|
  # Every vehicle consumes the same random draws whether or not it is
  # created, so a partial earlier run still converges on the same fleet.
  origin_code, destination_code, via_city = routes[index]
  status_kind = number == "TRK-102" ? "in_transit" : STATUS_CYCLE[index % STATUS_CYCLE.size]
  type, capacity, kmpl = VEHICLE_SPECS[rng.rand(VEHICLE_SPECS.size)]
  vendor = vendors[rng.rand(vendors.size)]
  progress = number == "TRK-102" ? 0.2 : 0.15 + rng.rand * 0.7
  mileage = 20_000 + rng.rand(160_000)
  driver_name = "#{FIRST_NAMES[rng.rand(FIRST_NAMES.size)]} #{LAST_NAMES[rng.rand(LAST_NAMES.size)]}"
  package_take = 3 + rng.rand(4)
  minutes_ago = 1 + rng.rand(15)
  next unless missing.include?(number)

  origin = hubs.fetch(origin_code)
  destination = hubs.fetch(destination_code)
  raise "Hub #{origin_code}/#{destination_code} has no coordinates" unless origin.geo_location && destination.geo_location

  Vehicle.transaction do
    driver = WorkforceMember.find_or_create_by!(identifier: "DRV-#{number}") do |member|
      member.name = driver_name
      member.role_type = "driver"
      member.hub = origin
      member.shift = index.even? ? "morning" : "evening"
      member.attendance_status = "present"
      member.phone_number = format("+91 97%08d", 10_000_000 + (index * 7919) % 90_000_000)
    end

    path = [ point(origin.geo_location), point(city_location(via_city)), point(destination.geo_location) ]
    position = if status_kind == "in_transit"
      along(path, progress).transform_values { |value| value.round(6) }
    else
      at_hub = Vehicle.where(current_location_id: Location.where(city: origin.geo_location.city).select(:id)).count
      spiral_offset(point(origin.geo_location), at_hub + 1)
    end
    city = status_kind == "in_transit" ? nearest_city(position, reference_cities) : origin.geo_location
    location = Location.create!(city: city.city, state: city.state, country: "India", latitude: position[:lat], longitude: position[:lng])

    vehicle = Vehicle.create!(
      number: number, vehicle_type: type, capacity: capacity,
      status: { "maintenance" => "maintenance", "out_of_service" => "out_of_service" }.fetch(status_kind, "active"),
      vendor: vendor.name, vendor_id: vendor.id, hub: origin, driver: driver,
      current_location: "#{city.city}, #{city.state}", current_location_id: location.id,
      last_known_latitude: position[:lat], last_known_longitude: position[:lng],
      last_location_at: Time.current - minutes_ago.minutes,
      fuel_efficiency_kmpl: kmpl, mileage_km: mileage,
      allow_alerts: true, alertable_fields: alertable_fields, fleet_monitoring_poc: true
    )

    if status_kind == "in_transit"
      hours = GeoDistance.path_km(path) / AVERAGE_SPEED_KMPH
      departure_at = Time.current - (hours * progress).hours
      trip = Trip.create!(
        vehicle: vehicle, origin_hub: origin, destination_hub: destination, status: "in_transit",
        departure_at: departure_at.change(sec: 0), expected_arrival_at: (departure_at + hours.hours).change(sec: 0),
        route_info: "#{origin.name} to #{destination.name} via #{via_city}"
      )
      origin.packages.where(status: %w[pending received], trip_id: nil).order(:id).limit(package_take).each do |package|
        package.update!(trip: trip, status: "in_transit")
      end
    end
    created += 1
  end
end

poc = Vehicle.fleet_monitoring_poc
trk = Vehicle.where(number: NUMBERS).includes(:current_geo_location)
puts "\nCreated this run: #{created}"
puts "POC vehicles after: #{poc.count} (all vehicles: #{Vehicle.count})"
puts "TRK by status: #{trk.group(:status).count}"
puts "TRK in transit: #{Trip.status_in_transit.where(vehicle_id: trk.select(:id)).count}"

checks = {
  "POC total is #{TARGET_POC_TOTAL}" => poc.count == TARGET_POC_TOTAL,
  "all 100 TRK vehicles exist" => trk.count == 100,
  "vehicle numbers unique" => Vehicle.group(:number).having("COUNT(*) > 1").count.empty?,
  "coordinates inside India bounds" => trk.all? { |v| v.last_known_latitude.to_f.between?(6, 37) && v.last_known_longitude.to_f.between?(68, 98) },
  "valid hub references" => trk.all? { |v| v.hub_id && Hub.exists?(v.hub_id) },
  "valid vendor references" => trk.all? { |v| v.vendor_id && Vendor.exists?(v.vendor_id) },
  "valid statuses" => trk.all? { |v| Vehicle.statuses.key?(v.status) },
  "no orphan drivers" => trk.all? { |v| v.driver_id && WorkforceMember.exists?(v.driver_id) },
  "every TRK has a location" => trk.all?(&:current_geo_location)
}
checks.each { |label, ok| puts "  #{ok ? '✓' : '✗'} #{label}" }
abort("\nData consistency checks failed") unless checks.values.all?
