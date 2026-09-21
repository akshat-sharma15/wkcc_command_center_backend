# Optional link from an AlertRule to the EventDefinition it's associated
# with (a rule can be field-only, e.g. "hubs.capacity > 80", with no event
# at all). A real FK is possible now that both tables live in the
# operations database — see EventDefinition's move in the preceding
# migration.
class AddEventDefinitionIdToAlertRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :alert_rules, :event_definition, null: true, foreign_key: true
  end
end
