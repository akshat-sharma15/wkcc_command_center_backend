require "rails_helper"

RSpec.describe "Api::V1::FleetMonitoring hub vehicles and vehicle detail", type: :request do
  it "returns only the inbound or outbound POC vehicles of a hub" do
    corridor = build_corridor
    outbound_vehicle = create(:vehicle, fleet_monitoring_poc: true)
    create(:trip, vehicle: outbound_vehicle, origin_hub: corridor[:destination], destination_hub: corridor[:origin], status: "in_transit")
    non_poc = create(:vehicle, fleet_monitoring_poc: false)
    create(:trip, vehicle: non_poc, origin_hub: corridor[:origin], destination_hub: corridor[:destination], status: "in_transit")
    code = corridor[:destination].code

    get "/api/v1/fleet-monitoring/hubs/#{code}/vehicles", params: { direction: "inbound" }, headers: authenticated_headers
    expect(response.parsed_body["vehicles"].map { |v| [ v["pnr"], v["direction"] ] }).to eq([ [ "TRK-SPEC-1", "inbound" ] ])
    expect(response.parsed_body["vehicles"].first.keys).to include("lat", "lng", "status", "trip_id", "destination", "eta", "hub_code")

    get "/api/v1/fleet-monitoring/hubs/#{code}/vehicles", params: { direction: "outbound" }, headers: authenticated_headers
    expect(response.parsed_body["vehicles"].map { |v| v["pnr"] }).to eq([ outbound_vehicle.number ])

    get "/api/v1/fleet-monitoring/hubs/#{code}/vehicles", headers: authenticated_headers
    expect(response.parsed_body["vehicles"].size).to eq(2)

    get "/api/v1/fleet-monitoring/hubs/#{code}/vehicles", params: { direction: "up" }, headers: authenticated_headers
    expect(response).to have_http_status(:bad_request)
  end

  it "adds ETA, waybill, incident and diversion fields to the vehicle list and detail" do
    corridor = build_corridor
    diversion = create(:route_diversion, trip: corridor[:trip])

    get "/api/v1/fleet-monitoring/vehicles", headers: authenticated_headers
    row = response.parsed_body.find { |v| v["pnr"] == "TRK-SPEC-1" }
    expect(row).to include("waybill_count" => 1, "diverted" => true, "diversion_id" => diversion.id, "trip_id" => corridor[:trip].id)
    expect(row["predicted_eta"]).to be_present
    expect(row["current_hub"]).to include("name" => "Indore Test Hub")

    get "/api/v1/fleet-monitoring/vehicles/TRK-SPEC-1", headers: authenticated_headers
    expect(response.parsed_body["waybills"].size).to eq(1)
    expect(response.parsed_body["eta_detail"]).to include("diverted" => true)
  end
end
