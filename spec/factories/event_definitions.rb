FactoryBot.define do
  factory :event_definition do
    sequence(:name) { |n| "Test Event #{n}" }
    group { "Fleet / Transport" }
    event_type { "Accident" }
  end
end
