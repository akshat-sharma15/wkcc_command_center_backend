require "rails_helper"

RSpec.describe "Api::V1::Waybills", type: :request do
  it "lists waybills for a vehicle and shows their packages" do
    corridor = build_corridor
    create(:waybill) # another vehicle's

    get "/api/v1/waybills", params: { vehicle_number: "TRK-SPEC-1" }, headers: authenticated_headers
    expect(response.parsed_body.size).to eq(1)
    expect(response.parsed_body.first).to include("customer" => "CUST-9", "total_packages" => 2, "total_orders" => 1,
                                                  "destination" => include("name" => "Ratlam Test Hub"))

    get "/api/v1/waybills/#{corridor[:waybill].id}", headers: authenticated_headers
    expect(response.parsed_body["packages"].map { |p| p["identifier"] }).to eq(%w[PKG-CORR-0 PKG-CORR-1])
  end
end
