require "rails_helper"

RSpec.describe "Api::V1::RouteDiversions", type: :request do
  it "creates a diversion from hub/location waypoints, calculates impact and publishes the incident" do
    corridor = build_corridor
    dhar = create(:location, city: "Dhar", latitude: 22.6013, longitude: 75.3025)
    incident_rule(IncidentCatalog::ROUTE_DIVERSION)

    post "/api/v1/route-diversions", params: {
      route_diversion: {
        vehicle_id: corridor[:vehicle].id, reason: "Bridge closure", traffic_factor: 1.1,
        original_path: [ { hub_id: corridor[:origin].id }, { location_id: corridor[:ujjain].id }, { hub_id: corridor[:destination].id } ],
        diverted_path: [ { hub_id: corridor[:origin].id }, { location_id: dhar.id }, { hub_id: corridor[:destination].id } ]
      }
    }, headers: authenticated_headers, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body).to include("trip_id" => corridor[:trip].id, "status" => "active", "affected_waybills" => 1, "revenue_risk" => 50_000.0)
    expect(body["additional_distance_km"]).to be > 0
    expect(body["alert_id"]).to be_present
    expect(Alert.find(body["alert_id"]).metadata.dig("incident", "diversion_id")).to eq(body["id"])
    expect(VehicleOperationEvent.where(event_type: "ROUTE_DEVIATION", trip: corridor[:trip])).to exist

    get "/api/v1/fleet-monitoring/route-diversions/#{body['id']}", headers: authenticated_headers
    expect(response.parsed_body["diverted_path"].map { |p| p["name"] }).to eq([ "Indore Test Hub", "Dhar", "Ratlam Test Hub" ])

    post "/api/v1/route-diversions/#{body['id']}/resolve", headers: authenticated_headers
    expect(response.parsed_body["status"]).to eq("resolved")
  end

  it "rejects a vehicle with no in-transit trip and malformed waypoints" do
    post "/api/v1/route-diversions", params: { route_diversion: { vehicle_id: create(:vehicle).id, reason: "x", diverted_path: [ { hub_id: 1 } ] } },
                                     headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)

    corridor = build_corridor
    post "/api/v1/route-diversions", params: { route_diversion: { vehicle_id: corridor[:vehicle].id, reason: "x", diverted_path: [ { name: "nowhere" } ] } },
                                     headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
