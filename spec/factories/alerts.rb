FactoryBot.define do
  factory :alert do
    sequence(:name) { |n| "Test Alert #{n}" }
    role { "Logistics Manager" }
    description { "Notify logistics team when this event occurs." }
    event_definition
  end
end
