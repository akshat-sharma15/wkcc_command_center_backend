require "rails_helper"

RSpec.describe AlertEvaluationJob do
  def perform(group, record_id, fields)
    described_class.new.perform(group, record_id, fields)
  end

  describe "false -> true creates an Alert" do
    it "creates an open Alert when the condition newly matches" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "active")
      rule = create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)

      vehicle.update_column(:status, "maintenance")

      expect { perform("vehicles", vehicle.id, %w[status]) }.to change(Alert, :count).by(1)
      alert = Alert.last
      expect(alert.alert_rule_id).to eq(rule.id)
      expect(alert.group).to eq("vehicles")
      expect(alert.record_id).to eq(vehicle.id)
      expect(alert.field).to eq("status")
      expect(alert.actual_value).to eq("maintenance")
      expect(alert.status).to eq("open")
      expect(alert.triggered_at).to be_present
    end
  end

  describe "true -> true does not duplicate" do
    it "does not create a second open Alert while the condition remains true" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)

      perform("vehicles", vehicle.id, %w[status])
      expect(Alert.where(status: "open").count).to eq(1)

      vehicle.touch
      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)
      expect(Alert.where(status: "open").count).to eq(1)
    end
  end

  describe "true -> false resolves the existing Alert" do
    it "marks the open Alert resolved and stamps resolved_at" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)
      perform("vehicles", vehicle.id, %w[status])
      open_alert = Alert.find_by(status: "open")
      expect(open_alert).to be_present

      vehicle.update_column(:status, "active")
      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)

      expect(open_alert.reload.status).to eq("resolved")
      expect(open_alert.resolved_at).to be_present
    end

    it "keeps the resolved Alert stored for history" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)
      perform("vehicles", vehicle.id, %w[status])
      vehicle.update_column(:status, "active")
      perform("vehicles", vehicle.id, %w[status])

      expect(Alert.where(status: "resolved").count).to eq(1)
    end
  end

  describe "disabled rule" do
    it "is ignored entirely — no Alert created" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        enabled: false, ensure_target_alertable: false)

      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)
    end
  end

  describe "allow_alerts = false on the record" do
    it "is ignored entirely — no Alert created, regardless of matching rules" do
      # A separate alertable vehicle just to satisfy AlertRule's own
      # "field is alertable on some record" validation — the actual
      # vehicle under test deliberately has allow_alerts: false.
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      vehicle = create(:vehicle, allow_alerts: false, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)

      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)
    end
  end

  describe "a changed field not in the record's alertable_fields" do
    it "is ignored — no rule lookup happens for it" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)

      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)
    end
  end

  describe "an unrecognized group" do
    it "is a no-op rather than constantizing arbitrary input" do
      expect { perform("not_a_real_group", 1, %w[status]) }.not_to raise_error
      expect(Alert.count).to eq(0)
    end
  end

  describe "notify: false" do
    it "still creates the Alert but no Notification records" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        notify: false, ensure_target_alertable: false)

      expect { perform("vehicles", vehicle.id, %w[status]) }
        .to change(Alert, :count).by(1)
        .and change(Notification, :count).by(0)
    end
  end

  describe "notify: true with a resolvable role recipient" do
    it "creates one Notification per user per requested channel" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      # Created before SupersetDirectory is stubbed configured, so
      # AlertRule's own recipient-exists validation is skipped (matching
      # this repo's real unconfigured state) - only the job's own
      # resolution logic below needs the stub.
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        notify: true, recipient_type: "role", recipient_id: 5, notification_channels: %w[in_app slack],
        ensure_target_alertable: false)
      allow(SupersetDirectory).to receive_messages(
        configured?: true,
        users_for_role: [ { id: 10, name: "Alice" }, { id: 11, name: "Bob" } ]
      )

      expect { perform("vehicles", vehicle.id, %w[status]) }.to change(Notification, :count).by(4) # 2 users x 2 channels

      alert = Alert.last
      expect(alert.notifications.pluck(:recipient_user_id, :channel)).to contain_exactly(
        [ 10, "in_app" ], [ 10, "slack" ], [ 11, "in_app" ], [ 11, "slack" ]
      )
    end

    it "enqueues a NotificationDeliveryJob for each Notification created" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        notify: true, recipient_type: "role", recipient_id: 5, notification_channels: %w[in_app],
        ensure_target_alertable: false)
      allow(SupersetDirectory).to receive_messages(configured?: true, users_for_role: [ { id: 10, name: "Alice" } ])

      expect { perform("vehicles", vehicle.id, %w[status]) }.to change(NotificationDeliveryJob.jobs, :size).by(1)
    end

    it "creates no Notifications when the recipient does not resolve (e.g. Superset not configured)" do
      expect(SupersetDirectory.configured?).to eq(false)
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        notify: true, recipient_type: "role", recipient_id: 5, notification_channels: %w[in_app],
        ensure_target_alertable: false)

      expect { perform("vehicles", vehicle.id, %w[status]) }
        .to change(Alert, :count).by(1)
        .and change(Notification, :count).by(0)
    end
  end

  describe "event-mode rules" do
    it "are never evaluated by the condition pipeline, even when an event rule exists alongside a matching condition rule" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "active")
      condition_rule = create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)
      event = create(:event_definition)
      event_rule = create(:alert_rule, trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, ensure_target_alertable: false)

      vehicle.update_column(:status, "maintenance")
      expect { perform("vehicles", vehicle.id, %w[status]) }.to change(Alert, :count).by(1)

      expect(Alert.last.alert_rule_id).to eq(condition_rule.id)
      expect(Alert.where(alert_rule_id: event_rule.id)).to be_empty
    end
  end

  describe "concurrent evaluation for the same record/rule" do
    it "the DB-level uniqueness constraint prevents a duplicate open Alert" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance")
      rule = create(:alert_rule, group: "vehicles", field: "status", operator: "=", value: "maintenance",
        ensure_target_alertable: false)

      # Simulate the race directly: two inserts for the same
      # (alert_rule_id, group, record_id) while both are "open".
      Alert.create!(alert_rule: rule, group: "vehicles", record_id: vehicle.id, field: "status",
        actual_value: "maintenance", severity: "critical", status: "open", triggered_at: Time.current)

      expect { perform("vehicles", vehicle.id, %w[status]) }.not_to change(Alert, :count)
    end
  end
end
