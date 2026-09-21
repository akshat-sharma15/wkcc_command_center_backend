FactoryBot.define do
  factory :integration do
    provider { "slack" }
    status { "disconnected" }
    enabled { true }
  end
end
