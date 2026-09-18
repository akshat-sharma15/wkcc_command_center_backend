puts "Seeding trips..."

vehicles = Vehicle.all.to_a
hubs = Hub.all.to_a
status_weights = { "scheduled" => 3, "in_transit" => 3, "completed" => 5, "cancelled" => 1, "delayed" => 2 }

40.times do
  vehicle = vehicles.sample
  origin, destination = hubs.sample(2)
  next unless origin && destination && origin != destination

  departure = rand(10.days).seconds.ago
  expected_arrival = departure + rand(4..30).hours
  status = status_weights.flat_map { |s, w| [s] * w }.sample
  actual_arrival =
    case status
    when "completed" then expected_arrival + rand(-2..3).hours
    when "delayed" then expected_arrival + rand(2..8).hours
    end

  Trip.create!(
    vehicle: vehicle,
    origin_hub: origin,
    destination_hub: destination,
    departure_at: departure,
    expected_arrival_at: expected_arrival,
    actual_arrival_at: actual_arrival,
    status: status,
    route_info: "#{origin.location} -> #{destination.location}"
  )
end
