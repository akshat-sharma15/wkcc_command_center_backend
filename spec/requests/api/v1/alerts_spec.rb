require "rails_helper"

RSpec.describe "Api::V1::Alerts", type: :request do
  it "supports the full flow: create event, then create/list/show/update/delete an alert using it" do
    post "/api/v1/events",
      params: { event: { name: "Truck Accident", group: "Fleet / Transport", type: "Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    event_id = response.parsed_body["id"]

    post "/api/v1/alerts",
      params: {
        alert: {
          name: "Critical Truck Accident",
          event_id: event_id,
          role: "Logistics Manager",
          description: "Notify logistics team when a truck accident occurs."
        }
      },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["role"]).to eq("Logistics Manager")
    expect(body["event"]["id"]).to eq(event_id)
    expect(body["event"]["type"]).to eq("Accident")
    alert_id = body["id"]

    get "/api/v1/alerts", headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.size).to eq(1)

    get "/api/v1/alerts/#{alert_id}", headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["name"]).to eq("Critical Truck Accident")

    patch "/api/v1/alerts/#{alert_id}",
      params: { alert: { role: "Fleet Supervisor" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["role"]).to eq("Fleet Supervisor")

    delete "/api/v1/alerts/#{alert_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)

    delete "/api/v1/events/#{event_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end

  it "returns 422 when the event does not exist" do
    post "/api/v1/alerts",
      params: { alert: { name: "Orphan Alert", event_id: 0, role: "Logistics Manager", description: "x" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 422 when required fields are missing" do
    event = create(:event_definition)
    post "/api/v1/alerts",
      params: { alert: { name: "", event_id: event.id, role: "", description: "" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
