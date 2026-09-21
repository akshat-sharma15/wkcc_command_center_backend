FactoryBot.define do
  factory :alert do
    alert_rule
    group { alert_rule.group }
    record_id { 1 }
    field { alert_rule.field }
    expected_value { "FAILURE" }
    actual_value { "FAILURE" }
    severity { "critical" }
    status { "open" }
    triggered_at { Time.current }
  end
end
