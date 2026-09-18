FactoryBot.define do
  factory :vehicle do
    sequence(:number) { |n| "VH-TEST-#{n}" }
    vehicle_type { "truck" }
    status { "active" }
    capacity { 2000 }
    vendor { "Test Fleet Vendor" }
    current_location { "Indore, MP" }
    hub
    driver { nil }
  end
end
