FactoryBot.define do
  factory :alert_rule do
    transient do
      # Ensures `create(:alert_rule)` is valid out of the box by finding
      # or creating a business record that has opted this field into
      # alerting — AlertRule's validity is genuinely cross-table (see
      # AlertRule#field_must_be_alertable_on_target_model). Set to false
      # in specs that intentionally test the "not alertable" rejection.
      ensure_target_alertable { true }
    end

    sequence(:name) { |n| "Test Alert Rule #{n}" }
    group { "vehicles" }
    field { "status" }
    operator { "=" }
    value { "FAILURE" }
    severity { "critical" }
    notify { false }
    enabled { true }

    before(:create) do |alert_rule, evaluator|
      next unless evaluator.ensure_target_alertable

      model = AlertRule::ALERTABLE_MODELS[alert_rule.group]
      next if model.nil?
      next if model.where(allow_alerts: true).where("? = ANY (alertable_fields)", alert_rule.field).exists?

      FactoryBot.create(model.model_name.element.to_sym, allow_alerts: true, alertable_fields: [ alert_rule.field ])
    end
  end
end
