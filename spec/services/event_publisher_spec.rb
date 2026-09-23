require "rails_helper"

RSpec.describe EventPublisher do
  def publish(**overrides)
    defaults = { entity_type: "Vehicle", entity_id: 123, payload: { vehicle_number: "VH-1" } }
    described_class.publish(**defaults.merge(overrides))
  end

  describe "false -> true creates an Alert" do
    it "creates an open Alert for an enabled event-mode rule matching the event_definition" do
      event = create(:event_definition, name: "Vehicle Failure")
      rule = create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      expect { publish(event_definition: event) }.to change(Alert, :count).by(1)

      alert = Alert.last
      expect(alert.alert_rule_id).to eq(rule.id)
      expect(alert.group).to eq("events:Vehicle")
      expect(alert.record_id).to eq(123)
      expect(alert.field).to eq(event.event_type)
      expect(alert.status).to eq("open")
      expect(alert.triggered_at).to be_present
      expect(alert.metadata).to include(
        "event_definition_id" => event.id,
        "event_definition_name" => "Vehicle Failure",
        "entity_type" => "Vehicle",
        "entity_id" => 123,
        "payload" => { "vehicle_number" => "VH-1" }
      )
    end
  end

  describe "duplicate while open" do
    it "does not create a second Alert for the same event_definition/entity while one is open" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      publish(event_definition: event)
      expect(Alert.where(status: "open").count).to eq(1)

      expect { publish(event_definition: event) }.not_to change(Alert, :count)
      expect(Alert.where(status: "open").count).to eq(1)
    end
  end

  describe "a new legitimate occurrence after the previous one resolved" do
    it "creates another Alert once the prior open Alert for that entity is no longer open" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      publish(event_definition: event)
      Alert.last.update!(status: "resolved", resolved_at: Time.current)

      expect { publish(event_definition: event) }.to change(Alert, :count).by(1)
      expect(Alert.where(status: "open").count).to eq(1)
    end
  end

  describe "separate entities are never collapsed" do
    it "creates a distinct Alert per entity_id for the same event_definition" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      publish(event_definition: event, entity_id: 1)
      expect { publish(event_definition: event, entity_id: 2) }.to change(Alert, :count).by(1)
      expect(Alert.where(status: "open").count).to eq(2)
    end

    it "creates a distinct Alert per entity_type for the same event_definition and entity_id" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      publish(event_definition: event, entity_type: "Vehicle", entity_id: 1)
      expect { publish(event_definition: event, entity_type: "Hub", entity_id: 1) }.to change(Alert, :count).by(1)
      expect(Alert.where(status: "open").count).to eq(2)
    end
  end

  describe "validation" do
    it "rejects an event_definition that has not been persisted" do
      event = build(:event_definition)
      expect { publish(event_definition: event) }.to raise_error(EventPublisher::InvalidEvent)
    end

    it "rejects a since-deleted event_definition" do
      event = create(:event_definition)
      event_id = event.id
      event.destroy!
      expect { publish(event_definition: EventDefinition.new(id: event_id)) }
        .to raise_error(EventPublisher::InvalidEvent)
    end

    it "rejects a blank entity_type" do
      event = create(:event_definition)
      expect { publish(event_definition: event, entity_type: "") }.to raise_error(EventPublisher::InvalidEvent)
    end

    it "rejects a blank entity_id" do
      event = create(:event_definition)
      expect { publish(event_definition: event, entity_id: nil) }.to raise_error(EventPublisher::InvalidEvent)
    end
  end

  describe "rule matching" do
    it "ignores condition-mode rules entirely, even ones sharing severity/name" do
      event = create(:event_definition)
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      create(:alert_rule, trigger_type: "condition", group: "vehicles", field: "status", operator: "=",
        value: "FAILURE", ensure_target_alertable: false)

      expect { publish(event_definition: event) }.not_to change(Alert, :count)
    end

    it "ignores event rules for a different event_definition" do
      event = create(:event_definition)
      other_event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: other_event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      expect { publish(event_definition: event) }.not_to change(Alert, :count)
    end

    it "ignores a disabled event rule" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, enabled: false, ensure_target_alertable: false)

      expect { publish(event_definition: event) }.not_to change(Alert, :count)
    end

    it "creates an Alert per matching enabled rule when more than one rule targets the same event" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id, name: "Rule A",
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id, name: "Rule B",
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      expect { publish(event_definition: event) }.to change(Alert, :count).by(2)
    end
  end

  describe "notification fan-out (via the shared AlertNotifier)" do
    it "creates no Notifications when notify is false" do
      event = create(:event_definition)
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, notify: false, ensure_target_alertable: false)

      expect { publish(event_definition: event) }
        .to change(Alert, :count).by(1)
        .and change(Notification, :count).by(0)
    end

    it "creates one Notification per resolved recipient per channel and enqueues delivery" do
      event = create(:event_definition, name: "Vehicle Failure")
      create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, notify: true, recipient_type: "role",
        recipient_id: 5, notification_channels: %w[in_app slack], ensure_target_alertable: false)
      allow(SupersetDirectory).to receive_messages(
        configured?: true,
        users_for_role: [ { id: 10, name: "Alice" }, { id: 11, name: "Bob" } ]
      )

      expect { publish(event_definition: event) }
        .to change(Notification, :count).by(4)
        .and change(NotificationDeliveryJob.jobs, :size).by(4)

      alert = Alert.last
      expect(alert.notifications.pluck(:recipient_user_id, :channel)).to contain_exactly(
        [ 10, "in_app" ], [ 10, "slack" ], [ 11, "in_app" ], [ 11, "slack" ]
      )
      expect(alert.notifications.first.title).to eq(alert.alert_rule.name)
      expect(alert.notifications.first.message).to include("Vehicle Failure")
    end
  end
end
