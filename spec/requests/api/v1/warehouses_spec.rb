require "rails_helper"

RSpec.describe "Api::V1::Warehouses", type: :request do
  describe "authentication" do
    def request_without_auth
      get "/api/v1/warehouses"
    end

    def request_with_invalid_auth
      get "/api/v1/warehouses", headers: { "Authorization" => "Bearer not-a-real-token" }
    end

    include_examples "requires api authentication"
  end

  it "supports the full CRUD lifecycle" do
    create_list(:warehouse, 2)
    get "/api/v1/warehouses", headers: authenticated_headers
    expect(response.parsed_body.size).to eq(2)

    post "/api/v1/warehouses",
      params: { warehouse: { name: "New WH", code: "WH-NEW", capacity: 500 } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    warehouse_id = response.parsed_body["id"]

    patch "/api/v1/warehouses/#{warehouse_id}",
      params: { warehouse: { status: "inactive" } },
      headers: authenticated_headers
    expect(response.parsed_body["status"]).to eq("inactive")

    delete "/api/v1/warehouses/#{warehouse_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end
end
