FactoryBot.define do
  factory :payment_due do
    vendor { "Test Vendor" }
    amount { 15_000 }
    due_date { 10.days.from_now.to_date }
    payment_status { "pending" }
  end
end
