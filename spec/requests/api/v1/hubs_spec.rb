require "rails_helper"

RSpec.describe "Api::V1::Hubs", type: :request do
  describe "authentication" do
    def request_without_auth
      get "/api/v1/hubs"
    end

    def request_with_invalid_auth
      get "/api/v1/hubs", headers: { "Authorization" => "Bearer not-a-real-token" }
    end

    include_examples "requires api authentication"
  end

  it "supports the full CRUD lifecycle" do
    create_list(:hub, 2)
    get "/api/v1/hubs", headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.size).to eq(2)

    post "/api/v1/hubs",
      params: { hub: { name: "New Hub", code: "HUB-NEW", capacity: 100 } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    hub_id = response.parsed_body["id"]

    get "/api/v1/hubs/#{hub_id}", headers: authenticated_headers
    expect(response).to have_http_status(:ok)

    patch "/api/v1/hubs/#{hub_id}",
      params: { hub: { operational_status: "degraded" } },
      headers: authenticated_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["operational_status"]).to eq("degraded")

    delete "/api/v1/hubs/#{hub_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end

  it "returns 422 for invalid params" do
    post "/api/v1/hubs", params: { hub: { name: "" } }, headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
