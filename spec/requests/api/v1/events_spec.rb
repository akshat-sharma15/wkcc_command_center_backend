require "rails_helper"

RSpec.describe "Api::V1::Events", type: :request do
  it "supports the full CRUD lifecycle" do
    create_list(:event_definition, 2)
    get "/api/v1/events", headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.size).to eq(2)

    post "/api/v1/events",
      params: { event: { name: "Truck Accident", group: "Fleet / Transport", type: "Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["group"]).to eq("Fleet / Transport")
    expect(body["type"]).to eq("Accident")
    event_id = body["id"]

    get "/api/v1/events/#{event_id}", headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["name"]).to eq("Truck Accident")

    patch "/api/v1/events/#{event_id}",
      params: { event: { name: "Critical Truck Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["name"]).to eq("Critical Truck Accident")

    delete "/api/v1/events/#{event_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end

  it "returns 422 for a missing name" do
    post "/api/v1/events",
      params: { event: { group: "Fleet / Transport", type: "Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a type that does not belong to the given group" do
    post "/api/v1/events",
      params: { event: { name: "Bad Combo", group: "Hubs", type: "Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"].join).to include("not valid for group")
  end

  it "accepts a valid group/type combination" do
    post "/api/v1/events",
      params: { event: { name: "Truck Accident On Highway", group: "Fleet / Transport", type: "Accident" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
  end

  it "refuses to delete an event definition referenced by an alert" do
    event = create(:event_definition)
    create(:alert, event_definition: event)

    delete "/api/v1/events/#{event.id}", headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
