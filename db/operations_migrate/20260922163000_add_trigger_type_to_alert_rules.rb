# An AlertRule has exactly one trigger mode, mutually exclusive:
#   "event"     - event_definition_id set; group/field/operator/value NULL
#   "condition" - group/field/operator/value set; event_definition_id NULL
# Default "condition" so every existing rule (which already has
# group/field/operator/value populated, per the pre-trigger_type schema)
# remains valid without a data migration.
class AddTriggerTypeToAlertRules < ActiveRecord::Migration[8.1]
  def change
    add_column :alert_rules, :trigger_type, :string, null: false, default: "condition"
    add_index :alert_rules, :trigger_type
  end
end
