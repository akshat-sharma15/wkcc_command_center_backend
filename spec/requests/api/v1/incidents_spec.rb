require "rails_helper"

RSpec.describe "Api::V1::Incidents", type: :request do
  it "lists the incident catalog with event definition ids" do
    IncidentCatalog.ensure_event_definitions!
    get "/api/v1/incidents", headers: authenticated_headers
    expect(response.parsed_body.map { |i| i["key"] }).to eq(%w[vehicle.failure hub.extra_vehicle_request route.diversion])
    expect(response.parsed_body).to all(include("event_definition_id" => be_present))
  end

  it "publishes a truck failure and returns the enriched alert" do
    corridor = build_corridor
    incident_rule(IncidentCatalog::VEHICLE_FAILURE)

    post "/api/v1/incidents/vehicle.failure", params: { entity_id: corridor[:vehicle].id, payload: { failure_type: "Brake" } },
                                              headers: authenticated_headers
    expect(response).to have_http_status(:created)
    incident = response.parsed_body["alerts"].first["incident"]
    expect(incident).to include("failure_type" => "Brake", "waybill_count" => 1)
  end

  it "rejects unknown keys, unknown entities and diversions published here" do
    IncidentCatalog.ensure_event_definitions!
    post "/api/v1/incidents/vehicle.teleport", params: { entity_id: 1 }, headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/v1/incidents/vehicle.failure", params: { entity_id: 0 }, headers: authenticated_headers
    expect(response).to have_http_status(:not_found)

    post "/api/v1/incidents/route.diversion", params: { entity_id: 1 }, headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "exposes the new definitions through GET /api/v1/events" do
    IncidentCatalog.ensure_event_definitions!
    get "/api/v1/events", headers: authenticated_headers
    expect(response.parsed_body.map { |e| e["key"] }).to include("vehicle.failure", "hub.extra_vehicle_request", "route.diversion")
  end
end
