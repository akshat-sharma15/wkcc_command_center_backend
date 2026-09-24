FactoryBot.define do
  factory :vehicle_operation_event do
    vehicle
    trip { nil }
    event_type { "BREAKDOWN" }
    occurred_at { Time.current }
    metadata { {} }
  end
end
