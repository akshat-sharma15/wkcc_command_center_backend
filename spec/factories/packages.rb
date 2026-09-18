FactoryBot.define do
  factory :package do
    sequence(:identifier) { |n| "PKG-TEST-#{n}" }
    trip { nil }
    association :location, factory: :warehouse
    expected_quantity { 100 }
    received_quantity { 100 }
    damaged_quantity { 0 }
    short_quantity { 0 }
    status { "pending" }
  end
end
