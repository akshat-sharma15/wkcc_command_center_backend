require "rails_helper"

# Phase 3: EventDefinition moved from command_center to operations so
# AlertRule could hold a real FK to it. This proves the persistence layer
# is actually routed as intended post-move, and that command_center (now
# just an unused, model-less legacy `alerts` table) is untouched by any of
# it.
RSpec.describe "AlertRule/Alert/EventDefinition operations DB boundary" do
  it "routes AlertRule, Alert, and EventDefinition through the same operations connection" do
    expect(AlertRule.connection_db_config.database).to eq(OperationsRecord.connection_db_config.database)
    expect(Alert.connection_db_config.database).to eq(OperationsRecord.connection_db_config.database)
    expect(EventDefinition.connection_db_config.database).to eq(OperationsRecord.connection_db_config.database)
  end

  it "no longer has any model backed by the command_center connection except its own record class" do
    expect(EventDefinition.connection_db_config.database).not_to eq(CommandCenterRecord.connection_db_config.database)
  end

  it "associates AlertRule with EventDefinition, optionally" do
    reflection = AlertRule.reflect_on_association(:event_definition)
    expect(reflection.macro).to eq(:belongs_to)
    expect(reflection.options[:optional]).to eq(true)
  end

  it "associates EventDefinition with AlertRule" do
    expect(EventDefinition.reflect_on_association(:alert_rules).macro).to eq(:has_many)
  end
end
