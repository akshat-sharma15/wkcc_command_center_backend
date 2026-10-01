# Single, scoped data correction: moves MH12IA2709's current location to
# Chhatrapati Sambhajinagar. Touches only this one vehicle - no other
# vehicle, hub, waybill, or alert record is read or written.
#
#   bin/rails runner scripts/data/move_mh12ia2709_to_sambhajinagar.rb
#
# MH12IA2709 has no in-transit trip (parked at its home hub, Pune) at the
# time this was written, so there is no origin/destination/route/waybill/
# ETA to reconcile against - the minimum valid change is exactly what was
# asked: move its current position. If a future run finds it mid-trip
# instead, this only updates position/timestamp and leaves the trip
# alone, since a parked-vehicle position change never needs to touch a
# trip that isn't its own.
#
# Idempotent: does nothing if the vehicle is already at this location.
NUMBER = "MH12IA2709".freeze
CITY = "Chhatrapati Sambhajinagar".freeze
STATE = "Maharashtra".freeze
LAT = 19.8762
LNG = 75.3433

puts "=" * 70
puts "MOVE #{NUMBER} TO #{CITY}"
puts "=" * 70

vehicle = Vehicle.find_by(number: NUMBER)
abort("#{NUMBER} not found") unless vehicle

current = vehicle.current_geo_location
if current && current.city == CITY && current.latitude.to_f == LAT && current.longitude.to_f == LNG
  puts "Already at #{CITY} - no change (idempotent)."
else
  trip = vehicle.trips.status_in_transit.first
  puts "Trip status: #{trip ? "in-transit (##{trip.id}, #{trip.origin_hub.code}->#{trip.destination_hub.code}) - left untouched, out of scope for a parked-vehicle position move" : 'none (parked) - no route/waybill/ETA to reconcile'}"

  location = Location.create!(city: CITY, state: STATE, country: "India", latitude: LAT, longitude: LNG)
  vehicle.update!(current_location_id: location.id, last_known_latitude: LAT, last_known_longitude: LNG, last_location_at: Time.current)
  puts "Moved #{NUMBER}: #{current&.city}, #{current&.state} -> #{CITY}, #{STATE}"
end

vehicle.reload
puts "\nFinal state:"
puts "  location: #{vehicle.current_geo_location.city}, #{vehicle.current_geo_location.state} (#{vehicle.current_geo_location.latitude}, #{vehicle.current_geo_location.longitude})"
puts "  status: #{vehicle.status}"
puts "  trip: #{vehicle.trips.status_in_transit.first&.id || 'none'}"
