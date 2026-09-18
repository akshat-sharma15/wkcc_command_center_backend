FactoryBot.define do
  factory :trip do
    vehicle
    origin_hub { association :hub }
    destination_hub { association :hub }
    departure_at { 1.hour.ago }
    expected_arrival_at { 5.hours.from_now }
    actual_arrival_at { nil }
    status { "scheduled" }
    route_info { "Indore -> Jaipur" }
  end
end
