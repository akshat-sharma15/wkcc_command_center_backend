require "rails_helper"

RSpec.describe "Api::V1::AlertRules", type: :request do
  it "follows the app's existing authentication convention (currently disabled repo-wide)" do
    get "/api/v1/alert-rules"
    expect(response).to have_http_status(:ok)
  end

  it "supports the full CRUD lifecycle" do
    vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status])

    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Failed Vehicle",
        group: "vehicles",
        field: "status",
        operator: "=",
        value: "FAILURE",
        severity: "critical",
        notify: true,
        recipient_type: "role",
        recipient_id: 5,
        notification_channels: %w[in_app slack],
        enabled: true
      }
    }
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["group_label"]).to eq("Vehicles")
    expect(body["field_label"]).to eq("Status")
    expect(body["notification_channels"]).to eq(%w[in_app slack])
    alert_rule_id = body["id"]

    get "/api/v1/alert-rules"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.size).to eq(1)

    get "/api/v1/alert-rules/#{alert_rule_id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["name"]).to eq("Failed Vehicle")

    patch "/api/v1/alert-rules/#{alert_rule_id}", params: { alert_rule: { severity: "warning" } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["severity"]).to eq("warning")

    delete "/api/v1/alert-rules/#{alert_rule_id}"
    expect(response).to have_http_status(:no_content)

    vehicle.destroy!
  end

  it "rejects an invalid group" do
    post "/api/v1/alert-rules", params: {
      alert_rule: { name: "Bad", group: "trips", field: "status", operator: "=", severity: "critical" }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a field not on the target model" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad", group: "vehicles", field: "not_a_column", operator: "=", severity: "critical"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a field not listed in alertable_fields" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
    post "/api/v1/alert-rules", params: {
      alert_rule: { name: "Bad", group: "vehicles", field: "status", operator: "=", severity: "critical" }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an invalid operator for the field's type" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad", group: "vehicles", field: "capacity", operator: "contains", value: 5, severity: "critical"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an invalid severity" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad", group: "vehicles", field: "status", operator: "=", value: "x", severity: "apocalyptic"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not require a recipient when notify is false" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Silent Rule", group: "vehicles", field: "status", operator: "=", value: "x",
        severity: "info", notify: false
      }
    }
    expect(response).to have_http_status(:created)
  end

  it "requires a recipient when notify is true" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Loud Rule", group: "vehicles", field: "status", operator: "=", value: "x",
        severity: "info", notify: true
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "accepts a role recipient" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Role Rule", group: "vehicles", field: "status", operator: "=", value: "x",
        severity: "info", notify: true, recipient_type: "role", recipient_id: 5
      }
    }
    expect(response).to have_http_status(:created)
  end

  it "accepts a user recipient" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "User Rule", group: "vehicles", field: "status", operator: "=", value: "x",
        severity: "info", notify: true, recipient_type: "user", recipient_id: 9
      }
    }
    expect(response).to have_http_status(:created)
  end

  it "rejects an unsupported recipient_type" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad Recipient", group: "vehicles", field: "status", operator: "=", value: "x",
        severity: "info", notify: true, recipient_type: "team", recipient_id: 1
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "creates an event-mode rule and includes event_definition_id/name in the response" do
    event = create(:event_definition, name: "Vehicle Failure")
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Event Linked Rule", trigger_type: "event", event_definition_id: event.id,
        group: nil, field: nil, operator: nil, value: nil, severity: "info"
      }
    }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["trigger_type"]).to eq("event")
    expect(response.parsed_body["event_definition_id"]).to eq(event.id)
    expect(response.parsed_body["event_definition_name"]).to eq("Vehicle Failure")
  end

  it "rejects an event_definition_id that does not exist" do
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad Event", trigger_type: "event", event_definition_id: 999_999,
        group: nil, field: nil, operator: nil, value: nil, severity: "info"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an event-mode rule that also populates condition fields" do
    event = create(:event_definition)
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad Mix", trigger_type: "event", event_definition_id: event.id,
        group: "vehicles", field: "status", operator: "=", value: "x", severity: "info"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a condition-mode rule that also populates event_definition_id" do
    create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
    event = create(:event_definition)
    post "/api/v1/alert-rules", params: {
      alert_rule: {
        name: "Bad Mix", trigger_type: "condition", event_definition_id: event.id,
        group: "vehicles", field: "status", operator: "=", value: "x", severity: "info"
      }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
