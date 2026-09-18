puts "Seeding packages..."

trips = Trip.all.to_a
warehouses = Warehouse.all.to_a
hubs = Hub.all.to_a
status_weights = { "pending" => 3, "in_transit" => 3, "received" => 6, "damaged" => 1, "short" => 1, "delivered" => 4 }

60.times do |i|
  identifier = format("PKG-%05d", 10_000 + i)
  next if Package.exists?(identifier: identifier)

  trip = rand < 0.8 ? trips.sample : nil
  location = rand < 0.6 ? warehouses.sample : hubs.sample
  next unless location

  expected = rand(10..200)
  status = status_weights.flat_map { |s, w| [s] * w }.sample
  damaged = status == "damaged" ? rand(1..5) : 0
  short = status == "short" ? rand(1..10) : 0
  received = status.in?(%w[received delivered]) ? expected : [expected - damaged - short, 0].max

  Package.create!(
    identifier: identifier,
    trip: trip,
    location: location,
    expected_quantity: expected,
    received_quantity: received,
    damaged_quantity: damaged,
    short_quantity: short,
    status: status
  )
end
