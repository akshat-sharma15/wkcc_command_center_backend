# Fleet Monitoring POC dataset (see Fleet Monitoring API POC plan).
#
# Flags ~100 of the existing ~325 vehicles for exposure through the new
# /api/v1/fleet-monitoring/* endpoints, without touching the other ~225.
# Deterministic and idempotent: reruns are a no-op once the POC vehicles
# have been flagged, and every Location/Vendor lookup below is
# find_or_create_by keyed on a natural key.
#
# Distribution target (task spec): 60-70 IN_TRANSIT, 15-20 PARKED,
# 8-12 MAINTENANCE, 3-7 DAMAGED. This picks 66 / 19 / 10 / 5 = 100.
puts "Seeding Fleet Monitoring POC data..."

if Vehicle.fleet_monitoring_poc.exists?
  puts "  Fleet Monitoring POC vehicles already flagged - skipping (idempotent no-op)."
  return
end

# city name -> [state, latitude, longitude]. Covers every city already used
# by the 52 real Hub#location strings, plus a handful of realistic
# "in-between" waypoint cities for the curated IN_TRANSIT route scenarios
# below (these do not have hubs of their own - they exist only to give an
# in-transit vehicle a geographically sensible current position between its
# origin and destination hub).
CITY_GEO = {
  "Agra" => ["Uttar Pradesh", 27.1767, 78.0081],
  "Ahmedabad" => ["Gujarat", 23.0225, 72.5714],
  "Amritsar" => ["Punjab", 31.6340, 74.8723],
  "Bengaluru" => ["Karnataka", 12.9716, 77.5946],
  "Bhopal" => ["Madhya Pradesh", 23.2599, 77.4126],
  "Bhubaneswar" => ["Odisha", 20.2961, 85.8245],
  "Chandigarh" => ["Chandigarh", 30.7333, 76.7794],
  "Chennai" => ["Tamil Nadu", 13.0827, 80.2707],
  "Coimbatore" => ["Tamil Nadu", 11.0168, 76.9558],
  "Dehradun" => ["Uttarakhand", 30.3165, 78.0322],
  "Delhi" => ["Delhi", 28.6139, 77.2090],
  "Durgapur" => ["West Bengal", 23.5204, 87.3119],
  "Faridabad" => ["Haryana", 28.4089, 77.3178],
  "Guntur" => ["Andhra Pradesh", 16.3067, 80.4365],
  "Guwahati" => ["Assam", 26.1445, 91.7362],
  "Gwalior" => ["Madhya Pradesh", 26.2183, 78.1828],
  "Hyderabad" => ["Telangana", 17.3850, 78.4867],
  "Indore" => ["Madhya Pradesh", 22.7196, 75.8577],
  "Jabalpur" => ["Madhya Pradesh", 23.1815, 79.9864],
  "Jaipur" => ["Rajasthan", 26.9124, 75.7873],
  "Jamshedpur" => ["Jharkhand", 22.8046, 86.2029],
  "Jodhpur" => ["Rajasthan", 26.2389, 73.0243],
  "Kanpur" => ["Uttar Pradesh", 26.4499, 80.3319],
  "Kochi" => ["Kerala", 9.9312, 76.2673],
  "Kolkata" => ["West Bengal", 22.5726, 88.3639],
  "Kota" => ["Rajasthan", 25.2138, 75.8648],
  "Lucknow" => ["Uttar Pradesh", 26.8467, 80.9462],
  "Ludhiana" => ["Punjab", 30.9010, 75.8573],
  "Madurai" => ["Tamil Nadu", 9.9252, 78.1198],
  "Meerut" => ["Uttar Pradesh", 28.9845, 77.7064],
  "Mumbai" => ["Maharashtra", 19.0760, 72.8777],
  "Mysuru" => ["Karnataka", 12.2958, 76.6394],
  "Nagpur" => ["Maharashtra", 21.1458, 79.0882],
  "Nashik" => ["Maharashtra", 20.0059, 73.7910],
  "Patna" => ["Bihar", 25.5941, 85.1376],
  "Pune" => ["Maharashtra", 18.5204, 73.8567],
  "Raipur" => ["Chhattisgarh", 21.2514, 81.6296],
  "Rajkot" => ["Gujarat", 22.3039, 70.8022],
  "Ranchi" => ["Jharkhand", 23.3441, 85.3096],
  "Ratlam" => ["Madhya Pradesh", 23.3315, 75.0367],
  "Salem" => ["Tamil Nadu", 11.6643, 78.1460],
  "Siliguri" => ["West Bengal", 26.7271, 88.3953],
  "Surat" => ["Gujarat", 21.1702, 72.8311],
  "Thiruvananthapuram" => ["Kerala", 8.5241, 76.9366],
  "Vadodara" => ["Gujarat", 22.3072, 73.1812],
  "Varanasi" => ["Uttar Pradesh", 25.3176, 82.9739],
  "Vijayawada" => ["Andhra Pradesh", 16.5062, 80.6480],
  "Visakhapatnam" => ["Andhra Pradesh", 17.6868, 83.2185],
  # Waypoint-only cities (no hub of their own):
  "Dewas" => ["Madhya Pradesh", 22.9676, 76.0534],
  "Udaipur" => ["Rajasthan", 24.5854, 73.7125],
  "Lonavala" => ["Maharashtra", 18.7546, 73.4062],
  "Panipat" => ["Haryana", 29.3909, 76.9635],
  "Vellore" => ["Tamil Nadu", 12.9165, 79.1325],
  "Kharagpur" => ["West Bengal", 22.3460, 87.2320],
  "Bharuch" => ["Gujarat", 21.7051, 72.9959],
  "Durg" => ["Chhattisgarh", 21.1901, 81.2849],
  "Jalandhar" => ["Punjab", 31.3260, 75.5762],
  "Kollam" => ["Kerala", 8.8932, 76.6141],
  "Erode" => ["Tamil Nadu", 11.3410, 77.7172],
  "Gaya" => ["Bihar", 24.7955, 84.9994]
}.freeze

def location_for(city)
  state, lat, lng = CITY_GEO.fetch(city) { raise "No CITY_GEO entry for #{city.inspect}" }
  Location.find_or_create_by!(city: city, state: state) do |l|
    l.country = "India"
    l.latitude = lat
    l.longitude = lng
  end
end

# --- Locations for every existing hub, + backfill hubs.geo_location ---
Hub.find_each do |hub|
  city = hub.location.to_s.split(",").first.to_s.strip
  next if city.blank?

  hub.update_column(:location_id, location_for(city).id) # rubocop:disable Rails/SkipsModelValidations
end
puts "  Locations: #{Location.count}"

# --- Vendors, backfilled from the existing free-text vehicle vendor values ---
VENDOR_NAMES = Vehicle.distinct.pluck(:vendor).compact.sort
VENDOR_NAMES.each_with_index do |name, index|
  Vendor.find_or_create_by!(name: name) { |v| v.code = format("VN-%02d", index + 1) }
end
vendors = Vendor.order(:code).to_a
puts "  Vendors: #{vendors.map(&:name).join(', ')}"

Vehicle.where(vendor_id: nil).find_each do |vehicle|
  vendor = vendors.find { |v| v.name == vehicle.vendor }
  vehicle.update_column(:vendor_id, vendor.id) if vendor # rubocop:disable Rails/SkipsModelValidations
end

# --- Driver phone numbers (deterministic, clearly-POC Indian mobile
# numbers - WorkforceMember has no real phone data to draw from) ---
WorkforceMember.role_type_driver.where(phone_number: nil).find_each do |driver|
  driver.update_column(:phone_number, format("+91 98%08d", 10_000_000 + (driver.id * 731) % 90_000_000)) # rubocop:disable Rails/SkipsModelValidations
end

# --- Curated IN_TRANSIT route scenarios (real existing hubs, real cities) ---
# Each: [origin_hub_code, destination_hub_code, waypoint_city]. Waypoint is
# a real city geographically between origin and destination, used as the
# vehicle's current_location while it is "in transit" on that route - see
# task section 21 ("Route scenarios").
ROUTES = [
  ["CC-HUB-016", "CC-HUB-019", "Dewas"],       # Indore -> Bhopal
  ["CC-HUB-016", "CC-HUB-008", "Gwalior"],     # Indore -> Agra
  ["CC-HUB-011", "CC-HUB-012", "Lonavala"],    # Mumbai -> Pune
  ["CC-HUB-013", "CC-HUB-002", "Udaipur"],     # Ahmedabad -> Jaipur
  ["CC-HUB-001", "CC-HUB-004", "Kanpur"],      # Delhi -> Lucknow
  ["CC-HUB-001", "CC-HUB-003", "Panipat"],     # Delhi -> Chandigarh
  ["CC-HUB-025", "CC-HUB-027", "Vellore"],     # Bengaluru -> Chennai
  ["CC-HUB-026", "CC-HUB-031", "Guntur"],      # Hyderabad -> Vijayawada
  ["CC-HUB-037", "CC-HUB-038", "Kharagpur"],   # Kolkata -> Bhubaneswar
  ["CC-HUB-014", "CC-HUB-015", "Bharuch"],     # Surat -> Vadodara
  ["CC-HUB-020", "CC-HUB-021", "Durg"],        # Nagpur -> Raipur
  ["CC-HUB-006", "CC-HUB-009", "Jalandhar"],   # Ludhiana -> Amritsar
  ["CC-HUB-028", "CC-HUB-034", "Kollam"],      # Kochi -> Thiruvananthapuram
  ["CC-HUB-029", "CC-HUB-035", "Erode"],       # Coimbatore -> Salem
  ["CC-HUB-039", "CC-HUB-040", "Gaya"]         # Patna -> Ranchi
].freeze

TARGET_IN_TRANSIT = 66
TARGET_PARKED = 19
TARGET_MAINTENANCE = 10
TARGET_DAMAGED = 5

def place_vehicle!(vehicle, location, minutes_ago:)
  vehicle.update!(
    current_location_id: location.id,
    last_known_latitude: location.latitude,
    last_known_longitude: location.longitude,
    last_location_at: Time.current - minutes_ago.minutes,
    fleet_monitoring_poc: true
  )
end

def clear_stale_in_transit_trips(vehicle)
  vehicle.trips.where(status: "in_transit").find_each do |trip|
    trip.update!(status: "completed", actual_arrival_at: trip.expected_arrival_at || trip.departure_at || Time.current)
  end
end

active_pool = Vehicle.status_active.order(:id).to_a
maintenance_pool = Vehicle.status_maintenance.order(:id).to_a
damaged_pool = Vehicle.status_out_of_service.order(:id).to_a

# --- IN_TRANSIT: distribute TARGET_IN_TRANSIT vehicles across ROUTES ---
in_transit_vehicles = active_pool.shift(TARGET_IN_TRANSIT)
base = TARGET_IN_TRANSIT / ROUTES.size
remainder = TARGET_IN_TRANSIT % ROUTES.size

cursor = 0
ROUTES.each_with_index do |(origin_code, destination_code, waypoint_city), route_index|
  count = base + (route_index < remainder ? 1 : 0)
  route_vehicles = in_transit_vehicles[cursor, count] || []
  cursor += count

  origin_hub = Hub.find_by!(code: origin_code)
  destination_hub = Hub.find_by!(code: destination_code)
  waypoint = location_for(waypoint_city)

  route_vehicles.each_with_index do |vehicle, i|
    clear_stale_in_transit_trips(vehicle)

    departure_at = Time.current - (2 + (i % 6)).hours
    expected_arrival_at = Time.current + (2 + (i % 8)).hours

    trip = Trip.create!(
      vehicle: vehicle,
      origin_hub: origin_hub,
      destination_hub: destination_hub,
      status: "in_transit",
      departure_at: departure_at,
      expected_arrival_at: expected_arrival_at,
      route_info: "#{origin_hub.name} to #{destination_hub.name} via #{waypoint_city}"
    )

    # Move a few real backlog packages already sitting at the origin hub
    # onto this trip, so the vehicle's occupied capacity and the Fleet
    # Monitoring packages/search endpoints have real IN_TRANSIT packages to
    # show - not just AT HUB backlog. Caps at 3 so no single vehicle's
    # "occupied capacity" looks absurd relative to its real capacity.
    origin_hub.packages.where(status: %w[pending received]).limit(3).find_each do |package|
      package.update!(trip: trip, status: "in_transit")
    end

    place_vehicle!(vehicle, waypoint, minutes_ago: 1 + (i % 12))
  end
end
puts "  IN_TRANSIT vehicles flagged: #{cursor}"

# --- PARKED: active vehicles left over, parked at their home hub ---
parked_vehicles = active_pool.shift(TARGET_PARKED)
parked_vehicles.each_with_index do |vehicle, i|
  clear_stale_in_transit_trips(vehicle)
  place_vehicle!(vehicle, vehicle.hub.geo_location, minutes_ago: 5 + (i % 40))
end
puts "  PARKED vehicles flagged: #{parked_vehicles.size}"

# --- MAINTENANCE: real status=maintenance vehicles, at their home hub ---
maintenance_vehicles = maintenance_pool.shift(TARGET_MAINTENANCE)
maintenance_vehicles.each_with_index do |vehicle, i|
  clear_stale_in_transit_trips(vehicle)
  place_vehicle!(vehicle, vehicle.hub.geo_location, minutes_ago: 30 + (i % 90))
end
puts "  MAINTENANCE vehicles flagged: #{maintenance_vehicles.size}"

# --- DAMAGED: real status=out_of_service vehicles, at their home hub ---
damaged_vehicles = damaged_pool.shift(TARGET_DAMAGED)
damaged_vehicles.each_with_index do |vehicle, i|
  clear_stale_in_transit_trips(vehicle)
  place_vehicle!(vehicle, vehicle.hub.geo_location, minutes_ago: 60 + (i % 180))
end
puts "  DAMAGED vehicles flagged: #{damaged_vehicles.size}"

# --- Spread out vehicles that share a city, so they don't render as
# exactly-overlapping map markers. Every vehicle above was placed at a
# single canonical Location per city (the hub's geo_location, or a route's
# waypoint) via `location_for`/`place_vehicle!` - multiple vehicles in the
# same city therefore point at the identical row. For any such city, give
# each vehicle beyond the first its own new Location row: same city/state
# (locations.rb's uniqueness was relaxed exactly for this), a small
# deterministic offset from the shared center using a golden-angle spiral
# (irrational angle step + monotonically increasing radius), so points are
# realistic, spread out, and never coincide - not random, not recomputed
# on every request.
def spiral_offset(center_lat, center_lng, index)
  angle_rad = ((index * 137.50776) % 360.0) * Math::PI / 180.0
  radius_km = 0.3 + (index * 0.35)
  lat_rad = center_lat * Math::PI / 180.0
  dlat = (radius_km / 111.0) * Math.cos(angle_rad)
  dlng = (radius_km / (111.0 * Math.cos(lat_rad))) * Math.sin(angle_rad)
  [(center_lat + dlat).round(6), (center_lng + dlng).round(6)]
end

jittered = 0
Vehicle.fleet_monitoring_poc.includes(:current_geo_location).group_by(&:current_location_id).each_value do |group|
  next if group.size <= 1

  center = group.first.current_geo_location
  group.sort_by(&:number).each_with_index do |vehicle, index|
    lat, lng = spiral_offset(center.latitude.to_f, center.longitude.to_f, index)
    point = Location.create!(city: center.city, state: center.state, country: center.country, latitude: lat, longitude: lng)
    vehicle.update_column(:current_location_id, point.id) # rubocop:disable Rails/SkipsModelValidations
    jittered += 1
  end
end
puts "  Vehicles spread to distinct in-city points: #{jittered}"

puts "  Total Fleet Monitoring POC vehicles: #{Vehicle.fleet_monitoring_poc.count}"
puts "  Distinct vehicle coordinate points: #{Vehicle.fleet_monitoring_poc.distinct.count(:current_location_id)}"
