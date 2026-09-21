require "rails_helper"

RSpec.describe AlertRule, type: :model do
  it "accepts a valid group/field combination" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    rule = build(:alert_rule, group: "vehicles", field: "status", ensure_target_alertable: false)
    expect(rule).to be_valid
  end

  it "is valid out of the box (factory sets up a matching alertable record)" do
    expect(create(:alert_rule)).to be_persisted
  end

  it "rejects an unsupported group" do
    rule = build(:alert_rule, group: "not_a_real_group")
    expect(rule).not_to be_valid
    expect(rule.errors[:group]).to be_present
  end

  it "rejects a field that is a real column but not listed in any record's alertable_fields" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
    rule = build(:alert_rule, group: "vehicles", field: "status", ensure_target_alertable: false)
    expect(rule).not_to be_valid
    expect(rule.errors[:field]).to be_present
  end

  it "rejects a field that does not exist on the target model at all" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    rule = build(:alert_rule, group: "vehicles", field: "not_a_real_column", ensure_target_alertable: false)
    expect(rule).not_to be_valid
    expect(rule.errors[:field]).to be_present
  end

  it "requires a name" do
    rule = build(:alert_rule, name: nil, ensure_target_alertable: false)
    expect(rule).not_to be_valid
  end

  it "requires recipient_type and recipient_id when notify is true" do
    rule = build(:alert_rule, notify: true, recipient_type: nil, recipient_id: nil, ensure_target_alertable: false)
    expect(rule).not_to be_valid
    expect(rule.errors[:recipient_type]).to be_present
    expect(rule.errors[:recipient_id]).to be_present
  end

  it "does not require recipient_type/recipient_id when notify is false" do
    rule = build(:alert_rule, notify: false, recipient_type: nil, recipient_id: nil, ensure_target_alertable: false)
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    expect(rule).to be_valid
  end

  it "exposes the actual target model via the server-side registry, never constantizing frontend input" do
    rule = build(:alert_rule, group: "vehicles")
    expect(rule.target_model).to eq(Vehicle)
  end

  describe "operator validity for field type" do
    it "accepts an operator valid for a numeric field" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
      rule = build(:alert_rule, group: "vehicles", field: "capacity", operator: ">=", value: 100,
        ensure_target_alertable: false)
      expect(rule).to be_valid
    end

    it "rejects 'contains' on a numeric field" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
      rule = build(:alert_rule, group: "vehicles", field: "capacity", operator: "contains", value: "100",
        ensure_target_alertable: false)
      expect(rule).not_to be_valid
      expect(rule.errors[:operator]).to be_present
    end

    it "rejects '>' on a string field" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      rule = build(:alert_rule, group: "vehicles", field: "status", operator: ">", value: "FAILURE",
        ensure_target_alertable: false)
      expect(rule).not_to be_valid
      expect(rule.errors[:operator]).to be_present
    end
  end

  describe "value type sanity check" do
    it "rejects a non-numeric value for a numeric field" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
      rule = build(:alert_rule, group: "vehicles", field: "capacity", operator: ">", value: "not-a-number",
        ensure_target_alertable: false)
      expect(rule).not_to be_valid
      expect(rule.errors[:value]).to be_present
    end
  end

  describe "severity" do
    it "rejects an unsupported severity" do
      rule = build(:alert_rule, severity: "apocalyptic")
      expect(rule).not_to be_valid
      expect(rule.errors[:severity]).to be_present
    end

    it "accepts every supported severity" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      AlertRule::SEVERITIES.each do |severity|
        rule = build(:alert_rule, group: "vehicles", field: "status", severity: severity,
          ensure_target_alertable: false)
        expect(rule).to be_valid, "expected severity #{severity} to be valid: #{rule.errors.full_messages}"
      end
    end
  end

  describe "recipient_type" do
    it "rejects an unsupported recipient_type" do
      rule = build(:alert_rule, notify: true, recipient_type: "team", recipient_id: 1)
      expect(rule).not_to be_valid
      expect(rule.errors[:recipient_type]).to be_present
    end

    it "accepts 'role' and 'user'" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      %w[role user].each do |type|
        rule = build(:alert_rule, group: "vehicles", field: "status", notify: true, recipient_type: type,
          recipient_id: 1, ensure_target_alertable: false)
        expect(rule).to be_valid, "expected recipient_type #{type} to be valid: #{rule.errors.full_messages}"
      end
    end
  end

  describe "notification_channels" do
    it "rejects an unsupported channel" do
      rule = build(:alert_rule, notification_channels: %w[in_app carrier_pigeon])
      expect(rule).not_to be_valid
      expect(rule.errors[:notification_channels]).to be_present
    end

    it "accepts the supported channels" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      rule = build(:alert_rule, group: "vehicles", field: "status",
        notification_channels: AlertRule::NOTIFICATION_CHANNELS, ensure_target_alertable: false)
      expect(rule).to be_valid
    end
  end

  describe "recipient existence in Superset" do
    it "is not checked when Superset is not configured (this repository's current state)" do
      expect(SupersetDirectory.configured?).to eq(false)
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      rule = build(:alert_rule, group: "vehicles", field: "status", notify: true, recipient_type: "role",
        recipient_id: 999_999, ensure_target_alertable: false)
      expect(rule).to be_valid
    end

    it "rejects a recipient_id that does not resolve, when Superset is configured" do
      allow(SupersetDirectory).to receive(:configured?).and_return(true)
      allow(SupersetDirectory).to receive(:find_role).with(999_999).and_return(nil)
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])

      rule = build(:alert_rule, group: "vehicles", field: "status", notify: true, recipient_type: "role",
        recipient_id: 999_999, ensure_target_alertable: false)
      expect(rule).not_to be_valid
      expect(rule.errors[:recipient_id]).to be_present
    end

    it "accepts a recipient_id that resolves, when Superset is configured" do
      allow(SupersetDirectory).to receive(:configured?).and_return(true)
      allow(SupersetDirectory).to receive(:find_role).with(5).and_return({ id: 5, name: "Operations Manager" })
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])

      rule = build(:alert_rule, group: "vehicles", field: "status", notify: true, recipient_type: "role",
        recipient_id: 5, ensure_target_alertable: false)
      expect(rule).to be_valid
    end
  end

  describe "event_definition association" do
    it "is optional — a field-only rule with no event_definition_id is valid" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      rule = build(:alert_rule, group: "vehicles", field: "status", event_definition_id: nil,
        ensure_target_alertable: false)
      expect(rule).to be_valid
    end

    it "accepts a real event_definition_id and exposes the association" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      event = create(:event_definition)
      rule = build(:alert_rule, group: "vehicles", field: "status", event_definition_id: event.id,
        ensure_target_alertable: false)
      expect(rule).to be_valid
      expect(rule.event_definition).to eq(event)
    end

    it "rejects an event_definition_id that does not exist" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      rule = build(:alert_rule, group: "vehicles", field: "status", event_definition_id: 999_999,
        ensure_target_alertable: false)
      expect(rule).not_to be_valid
      expect(rule.errors[:event_definition_id]).to be_present
    end

    it "nullifies event_definition_id on rules when the EventDefinition is destroyed" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      event = create(:event_definition)
      rule = create(:alert_rule, group: "vehicles", field: "status", event_definition_id: event.id,
        ensure_target_alertable: false)

      event.destroy!

      expect(rule.reload.event_definition_id).to be_nil
    end
  end
end
