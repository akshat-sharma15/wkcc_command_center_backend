require "rails_helper"

RSpec.describe "Api::V1::Trips", type: :request do
  let(:vehicle) { create(:vehicle) }
  let(:origin) { create(:hub) }
  let(:destination) { create(:hub) }

  describe "authentication" do
    def request_without_auth
      get "/api/v1/trips"
    end

    def request_with_invalid_auth
      get "/api/v1/trips", headers: { "Authorization" => "Bearer not-a-real-token" }
    end

    include_examples "requires api authentication"
  end

  it "supports the full CRUD lifecycle" do
    create_list(:trip, 2)
    get "/api/v1/trips", headers: authenticated_headers
    expect(response.parsed_body.size).to eq(2)

    params = {
      trip: {
        vehicle_id: vehicle.id, origin_hub_id: origin.id, destination_hub_id: destination.id,
        status: "scheduled"
      }
    }
    post "/api/v1/trips", params: params, headers: authenticated_headers
    expect(response).to have_http_status(:created)
    trip_id = response.parsed_body["id"]

    patch "/api/v1/trips/#{trip_id}", params: { trip: { status: "in_transit" } }, headers: authenticated_headers
    expect(response.parsed_body["status"]).to eq("in_transit")

    delete "/api/v1/trips/#{trip_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end

  it "returns 422 when origin and destination hubs are the same" do
    params = {
      trip: { vehicle_id: vehicle.id, origin_hub_id: origin.id, destination_hub_id: origin.id }
    }
    post "/api/v1/trips", params: params, headers: authenticated_headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
