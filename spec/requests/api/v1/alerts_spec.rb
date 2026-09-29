require "rails_helper"

RSpec.describe "Api::V1::Alerts", type: :request do
  let(:user_headers) { authenticated_headers.merge("X-Superset-User-Id" => "1") }
  let(:rule) { create(:alert_rule, primary_assignee_type: "user", primary_assignee_id: 1, secondary_assignee_type: "role", secondary_assignee_id: 3) }
  let!(:alert) { create(:alert, alert_rule: rule) }

  it "lists and shows alerts with assignment details" do
    get "/api/v1/alerts", params: { status: "open" }, headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |a| a["id"] }).to eq([ alert.id ])

    get "/api/v1/alerts/#{alert.id}", headers: authenticated_headers
    expect(response.parsed_body).to include("assignment_level" => "primary", "status" => "open")
    expect(response.parsed_body["secondary_assignee"]).to include("type" => "role", "id" => 3)
  end

  it "runs acknowledge -> assign -> escalate -> resolve and keeps the alert" do
    post "/api/v1/alerts/#{alert.id}/acknowledge", headers: user_headers
    expect(response.parsed_body).to include("status" => "acknowledged", "acknowledged_by" => 1)

    post "/api/v1/alerts/#{alert.id}/reassign", params: { assignee_type: "user", assignee_id: 4 }, headers: user_headers
    expect(response.parsed_body["assignee"]).to include("type" => "user", "id" => 4)

    post "/api/v1/alerts/#{alert.id}/escalate", headers: user_headers
    expect(response.parsed_body).to include("assignment_level" => "secondary", "escalation_level" => 1)

    post "/api/v1/alerts/#{alert.id}/resolve", params: { resolution_note: "Replacement vehicle assigned." }, headers: user_headers
    expect(response.parsed_body).to include("status" => "resolved", "resolved_by" => 1, "resolution_note" => "Replacement vehicle assigned.")
    expect(response.parsed_body["history"].size).to eq(4)
    expect(Alert.exists?(alert.id)).to be(true)
  end

  it "returns 422 for an invalid transition and 401 without a user" do
    post "/api/v1/alerts/#{alert.id}/resolve", headers: user_headers
    post "/api/v1/alerts/#{alert.id}/acknowledge", headers: user_headers
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/v1/alerts/#{alert.id}/escalate", headers: authenticated_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "has no delete route" do
    expect { Rails.application.routes.recognize_path("/api/v1/alerts/#{alert.id}", method: :delete) }
      .to raise_error(ActionController::RoutingError)
  end
end
