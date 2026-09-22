require "rails_helper"

RSpec.describe AlertNotificationMessageBuilder do
  it "uses the rule's own name as the title" do
    vehicle = create(:vehicle, number: "VH-1002", status: "maintenance", allow_alerts: true, alertable_fields: %w[status])
    rule = create(:alert_rule, name: "Critical Vehicle Failure", group: "vehicles", field: "status",
      ensure_target_alertable: false)
    alert = create(:alert, alert_rule: rule, group: "vehicles", record_id: vehicle.id, field: "status",
      actual_value: "maintenance")

    expect(described_class.new(alert).title).to eq("Critical Vehicle Failure")
  end

  it "builds a generic message using the entity's identifying attribute, not hard-coded text" do
    vehicle = create(:vehicle, number: "VH-1002", status: "maintenance", allow_alerts: true, alertable_fields: %w[status])
    rule = create(:alert_rule, group: "vehicles", field: "status", ensure_target_alertable: false)
    alert = create(:alert, alert_rule: rule, group: "vehicles", record_id: vehicle.id, field: "status",
      actual_value: "maintenance")

    expect(described_class.new(alert).message).to eq("Vehicle VH-1002 has status maintenance.")
  end

  it "falls back to a generic label when the record has no identifying attribute or no longer exists" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    rule = create(:alert_rule, group: "vehicles", field: "status", ensure_target_alertable: false)
    alert = create(:alert, alert_rule: rule, group: "vehicles", record_id: 999_999, field: "status",
      actual_value: "maintenance")

    expect(described_class.new(alert).message).to eq("Vehicle #999999 has status maintenance.")
  end

  it "includes rule/entity metadata without any per-model text" do
    vehicle = create(:vehicle, number: "VH-1002", status: "maintenance", allow_alerts: true, alertable_fields: %w[status])
    rule = create(:alert_rule, group: "vehicles", field: "status", severity: "critical",
      ensure_target_alertable: false)
    alert = create(:alert, alert_rule: rule, group: "vehicles", record_id: vehicle.id, field: "status",
      severity: "critical", expected_value: "maintenance", actual_value: "maintenance")

    metadata = described_class.new(alert).metadata
    expect(metadata).to include(
      alert_id: alert.id,
      alert_rule_id: rule.id,
      severity: "critical",
      group: "vehicles",
      record_id: vehicle.id,
      field: "status",
      expected_value: "maintenance",
      actual_value: "maintenance"
    )
  end

  it "works generically for a non-vehicle group (Hub, using its `name` attribute)" do
    hub = create(:hub, name: "Indore Hub", operational_status: "degraded", allow_alerts: true,
      alertable_fields: %w[operational_status])
    rule = create(:alert_rule, group: "hubs", field: "operational_status", ensure_target_alertable: false)
    alert = create(:alert, alert_rule: rule, group: "hubs", record_id: hub.id, field: "operational_status",
      actual_value: "degraded")

    expect(described_class.new(alert).message).to eq("Hub Indore Hub has operational status degraded.")
  end
end
