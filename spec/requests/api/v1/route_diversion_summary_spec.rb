require "rails_helper"

RSpec.describe "Route diversion summary and map layer", type: :request do
  it "summarises exactly the filtered diversions" do
    corridor = build_corridor
    active = create(:route_diversion, trip: corridor[:trip], affected_waybills: 2, affected_orders: 3, revenue_risk: 1000, additional_distance_km: 12)
    other_trip = create(:trip, status: "in_transit")
    create(:route_diversion, trip: other_trip, status: "resolved", affected_waybills: 9, revenue_risk: 5000)

    get "/api/v1/route-diversions/summary", headers: authenticated_headers
    expect(response.parsed_body).to include("diverted_routes" => 1, "diverted_vehicles" => 1, "affected_waybills" => 2,
                                            "affected_orders" => 3, "revenue_risk" => 1000.0)
    get "/api/v1/route-diversions", headers: authenticated_headers
    expect(response.parsed_body.map { |d| d["id"] }).to eq([ active.id ])

    get "/api/v1/route-diversions/summary", params: { status: "all" }, headers: authenticated_headers
    expect(response.parsed_body["diverted_vehicles"]).to eq(2)
    get "/api/v1/route-diversions/summary", params: { hub: corridor[:destination].code }, headers: authenticated_headers
    expect(response.parsed_body["diverted_routes"]).to eq(1)
    get "/api/v1/route-diversions/summary", params: { vehicle: "NOPE" }, headers: authenticated_headers
    expect(response.parsed_body).to include("diverted_routes" => 0, "revenue_risk" => nil)

    get "/api/v1/fleet-monitoring/route-diversions", headers: authenticated_headers
    expect(response.parsed_body["summary"]["diverted_routes"]).to eq(1)
    expect(response.parsed_body["diversions"].first).to include("pnr" => "TRK-SPEC-1", "original_path" => be_present, "diverted_path" => be_present)
  end
end
