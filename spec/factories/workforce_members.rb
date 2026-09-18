FactoryBot.define do
  factory :workforce_member do
    sequence(:identifier) { |n| "WF-TEST-#{n}" }
    name { "Test Worker" }
    role_type { "loader" }
    hub
    shift { "morning" }
    attendance_status { "present" }
  end
end
