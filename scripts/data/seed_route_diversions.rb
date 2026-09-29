# Seeds a realistic set of ACTIVE route diversions across India, one per
# listed corridor, on an in-transit TRK vehicle already running that
# corridor. Each goes through RouteDiversionCreator - the same path as
# POST /api/v1/route-diversions - so impact is calculated and the
# route.diversion incident (Alert + in-app/Slack notifications) is
# published exactly as for a real diversion.
#
#   bin/rails runner scripts/data/seed_route_diversions.rb
#
# Idempotent: a corridor that already has an active diversion is skipped.
# Afterwards vehicle positions are re-planned so diverted vehicles sit on
# their diverted path (scripts/data/regenerate_vehicle_positions.rb).
DETOUR_CITIES = {
  "Alwar" => [ "Rajasthan", 27.5530, 76.6346 ],
  "Shajapur" => [ "Madhya Pradesh", 23.4273, 76.2730 ],
  "Karjat" => [ "Maharashtra", 18.9107, 73.3235 ],
  "Raichur" => [ "Karnataka", 16.2076, 77.3463 ],
  "Agra" => [ "Uttar Pradesh", 27.1767, 78.0081 ],
  "Dakor" => [ "Gujarat", 22.7520, 73.1491 ],
  "Tiruvannamalai" => [ "Tamil Nadu", 12.2253, 79.0747 ]
}.freeze

# [origin hub, destination hub, detour city, traffic factor, reason]
CORRIDORS = [
  [ "CC-HUB-002", "CC-HUB-001", "Alwar", 1.15, "Multi-vehicle accident on NH-48 near Shahjahanpur - diverted via Alwar" ],
  [ "CC-HUB-016", "CC-HUB-019", "Shajapur", 1.1, "Protest blockade on the Dewas bypass - diverted via Shajapur" ],
  [ "CC-HUB-011", "CC-HUB-012", "Karjat", 1.3, "Landslide at Khandala ghat - diverted via Karjat" ],
  [ "CC-HUB-026", "CC-HUB-025", "Raichur", 1.1, "Flooding on NH-44 near Kurnool - diverted via Raichur" ],
  [ "CC-HUB-001", "CC-HUB-004", "Agra", 1.05, "Expressway closure near Etawah - diverted via Agra" ],
  [ "CC-HUB-013", "CC-HUB-015", "Dakor", 1.2, "Bridge maintenance near Anand - diverted via Dakor" ],
  [ "CC-HUB-025", "CC-HUB-027", "Tiruvannamalai", 1.25, "Heavy rain on NH-48 near Krishnagiri - diverted via Tiruvannamalai" ]
].freeze

def detour_point(city)
  state, lat, lng = DETOUR_CITIES.fetch(city)
  location = EtaImpactService.via_point_location(city) ||
             Location.create!(city: city, state: state, country: "India", latitude: lat, longitude: lng)
  { location_id: location.id, name: location.city, lat: location.latitude.to_f, lng: location.longitude.to_f }
end

puts "=" * 70
puts "SEED ROUTE DIVERSIONS"
puts "=" * 70

created = 0
CORRIDORS.each do |origin_code, destination_code, city, traffic_factor, reason|
  origin = Hub.includes(:geo_location).find_by!(code: origin_code)
  destination = Hub.includes(:geo_location).find_by!(code: destination_code)
  corridor_trips = FleetMonitoring::HubVehicleFlow.current_trips.where(origin_hub_id: origin.id, destination_hub_id: destination.id)

  if RouteDiversion.active.where(trip_id: corridor_trips.select(:id)).exists?
    puts "  ⊘ #{origin.name} -> #{destination.name}: already diverted"
    next
  end

  trip = corridor_trips.joins(:vehicle).where("vehicles.number LIKE 'TRK-%'").where(id: Waybill.open.select(:trip_id)).order("vehicles.number").first ||
         corridor_trips.joins(:vehicle).order("vehicles.number").first
  next puts("  ⊘ #{origin.name} -> #{destination.name}: no in-transit vehicle on this corridor") unless trip

  diverted_path = [ EtaImpactService.hub_point(origin), detour_point(city), EtaImpactService.hub_point(destination) ]
  diversion = RouteDiversionCreator.create!(vehicle: trip.vehicle, trip: trip, reason: reason,
                                            traffic_factor: traffic_factor, diverted_path: diverted_path)
  created += 1
  puts "  ✓ ##{diversion.id} #{trip.vehicle.number}: #{diversion.original_path.map { |p| p['name'] }.join(' → ')}  ⇒  via #{city} " \
       "(+#{diversion.additional_distance_km} km, +#{diversion.delay_minutes} min, #{diversion.affected_waybills} waybills, alert ##{diversion.alert_id})"
end

puts "\nCreated: #{created}"
puts "Summary: #{RouteDiversionQuery.new.summary.except(:filters)}"
puts "\nRe-planning vehicle positions onto diverted paths..."
load Rails.root.join("scripts/data/regenerate_vehicle_positions.rb")
