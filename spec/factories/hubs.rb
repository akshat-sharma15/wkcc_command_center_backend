FactoryBot.define do
  factory :hub do
    sequence(:name) { |n| "Test Hub #{n}" }
    sequence(:code) { |n| "HUB-TEST-#{n}" }
    location { "Indore, MP" }
    capacity { 500 }
    parking_capacity { 40 }
    available_parking { 10 }
    operational_status { "active" }
  end
end
