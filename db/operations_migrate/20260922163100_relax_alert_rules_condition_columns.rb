# group/field/operator were NOT NULL from before trigger_type existed
# (every rule was condition-mode). An event-mode rule legitimately has
# all three NULL — model-level presence/absence validations (see
# AlertRule) are the real enforcement; these DB constraints must relax to
# match or every event-mode INSERT raises a raw NotNullViolation instead
# of a clean validation error.
class RelaxAlertRulesConditionColumns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :alert_rules, :group, true
    change_column_null :alert_rules, :field, true
    change_column_null :alert_rules, :operator, true
  end
end
