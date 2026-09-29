require "rails_helper"

RSpec.describe "Waybill search", type: :request do
  before { build_corridor[:waybill].update!(waybill_number: "WB-100123") }

  it "suggests waybills after 3 characters, ignoring case and hyphens" do
    get "/api/v1/fleet-monitoring/search/suggestions", params: { q: "wb1" }, headers: authenticated_headers
    expect(response.parsed_body["suggestions"]["waybills"].map { |w| w["waybill_number"] }).to eq([ "WB-100123" ])

    get "/api/v1/fleet-monitoring/search/suggestions", params: { q: "wb" }, headers: authenticated_headers
    expect(response).to have_http_status(:bad_request)
  end

  it "returns waybill detail with vehicle, trip, route, customer, counts and ETA" do
    get "/api/v1/fleet-monitoring/search/waybill", params: { waybill_number: "wb100123" }, headers: authenticated_headers
    expect(response.parsed_body).to include("waybill_number" => "WB-100123", "vehicle_pnr" => "TRK-SPEC-1", "customer" => "CUST-9",
                                            "package_count" => 2, "order_count" => 1)
    expect(response.parsed_body["destination"]).to include("name" => "Ratlam Test Hub")
    expect(response.parsed_body["predicted_eta"]).to be_present

    get "/api/v1/fleet-monitoring/search/waybill", params: { waybill_number: "WB-999" }, headers: authenticated_headers
    expect(response).to have_http_status(:not_found)
  end
end
