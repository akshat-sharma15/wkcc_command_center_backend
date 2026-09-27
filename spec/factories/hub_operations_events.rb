FactoryBot.define do
  factory :hub_operations_event do
    hub
    vehicle { nil }
    trip { nil }
    package { nil }
    event_type { "GATE_IN" }
    dock_reference { nil }
    bay_reference { nil }
    occurred_at { Time.current }
    metadata { {} }
  end
end
