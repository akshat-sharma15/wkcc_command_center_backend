puts "Seeding vehicles..."

hubs = Hub.all.to_a
drivers_by_hub = WorkforceMember.role_type_driver.group_by(&:hub_id)
vendors = ["Tata Motors Fleet", "Ashok Leyland Leasing", "Mahindra Logistics", "Independent Owner"]
vehicle_types = %w[truck mini_truck trailer van]
status_weights = { "active" => 7, "maintenance" => 2, "out_of_service" => 1 }

25.times do |i|
  number = format("VH-%04d", 1000 + i)
  next if Vehicle.exists?(number: number)

  hub = hubs.sample
  driver = drivers_by_hub[hub.id]&.sample

  Vehicle.create!(
    number: number,
    vehicle_type: vehicle_types.sample,
    status: status_weights.flat_map { |status, w| [status] * w }.sample,
    capacity: [1000, 2000, 5000, 8000].sample,
    vendor: vendors.sample,
    current_location: hub.location,
    hub: hub,
    driver: driver,
    allow_alerts: true,
    alertable_fields: %w[status capacity]
  )
end
