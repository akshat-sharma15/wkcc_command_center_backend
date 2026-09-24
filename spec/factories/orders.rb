FactoryBot.define do
  factory :order do
    sequence(:order_number) { |n| "ORD-TEST-#{n}" }
    customer_reference { "CUST-1" }
    status { "pending" }
    priority { "standard" }
    origin_hub { association :hub }
    destination_hub { association :hub }
    package_count { 1 }
    total_weight { 10.5 }
    promised_delivery_at { 2.days.from_now }
    delivered_at { nil }
  end
end
