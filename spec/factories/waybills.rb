FactoryBot.define do
  factory :waybill do
    sequence(:waybill_number) { |n| "WB-TEST-#{n}" }
    trip
    vehicle { trip.vehicle }
    origin_hub { trip.origin_hub }
    destination_hub { trip.destination_hub }
    status { "in_transit" }
    declared_value { 10_000 }
    expected_arrival_at { trip.expected_arrival_at }
  end
end
