require "rails_helper"

RSpec.describe "Api::V1::Packages", type: :request do
  let(:warehouse) { create(:warehouse) }

  it "supports the full CRUD lifecycle" do
    create_list(:package, 2)
    get "/api/v1/packages", headers: authenticated_headers
    expect(response.parsed_body.size).to eq(2)

    params = {
      package: {
        identifier: "PKG-NEW", location_type: "Warehouse", location_id: warehouse.id,
        expected_quantity: 50, received_quantity: 50
      }
    }
    post "/api/v1/packages", params: params, headers: authenticated_headers
    expect(response).to have_http_status(:created)
    package_id = response.parsed_body["id"]

    patch "/api/v1/packages/#{package_id}",
      params: { package: { status: "received" } },
      headers: authenticated_headers
    expect(response.parsed_body["status"]).to eq("received")

    delete "/api/v1/packages/#{package_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end
end
