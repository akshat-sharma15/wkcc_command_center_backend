FactoryBot.define do
  factory :warehouse do
    sequence(:name) { |n| "Test Warehouse #{n}" }
    sequence(:code) { |n| "WH-TEST-#{n}" }
    location { "Ahmedabad, GJ" }
    capacity { 5000 }
    status { "active" }
  end
end
