require "rails_helper"

RSpec.describe "Api::V1::Vehicles", type: :request do
  let(:hub) { create(:hub) }

  describe "authentication" do
    def request_without_auth
      get "/api/v1/vehicles"
    end

    def request_with_invalid_auth
      get "/api/v1/vehicles", headers: { "Authorization" => "Bearer not-a-real-token" }
    end

    include_examples "requires api authentication"
  end

  describe "GET /api/v1/vehicles" do
    it "returns paginated vehicles" do
      create_list(:vehicle, 3, hub: hub)

      get "/api/v1/vehicles", headers: authenticated_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(3)
      expect(response.headers["X-Page"]).to eq("1")
      expect(response.headers["X-Count"]).to eq("3")
    end
  end

  describe "GET /api/v1/vehicles/:id" do
    it "returns the vehicle" do
      vehicle = create(:vehicle, hub: hub)

      get "/api/v1/vehicles/#{vehicle.id}", headers: authenticated_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["number"]).to eq(vehicle.number)
    end

    it "returns 404 for an unknown id" do
      get "/api/v1/vehicles/999999", headers: authenticated_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/vehicles" do
    it "creates a vehicle" do
      params = { vehicle: { number: "VH-9001", vehicle_type: "truck", hub_id: hub.id, capacity: 3000 } }

      post "/api/v1/vehicles", params: params, headers: authenticated_headers

      expect(response).to have_http_status(:created)
      expect(Vehicle.find_by(number: "VH-9001")).to be_present
    end

    it "returns 422 with validation errors for invalid params" do
      params = { vehicle: { number: "", vehicle_type: "", hub_id: hub.id } }

      post "/api/v1/vehicles", params: params, headers: authenticated_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    it "returns 400 when the vehicle param is missing entirely" do
      post "/api/v1/vehicles", params: {}, headers: authenticated_headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/v1/vehicles/:id" do
    it "updates the vehicle" do
      vehicle = create(:vehicle, hub: hub)

      patch "/api/v1/vehicles/#{vehicle.id}",
        params: { vehicle: { status: "maintenance" } },
        headers: authenticated_headers

      expect(response).to have_http_status(:ok)
      expect(vehicle.reload.status).to eq("maintenance")
    end
  end

  describe "DELETE /api/v1/vehicles/:id" do
    it "deletes the vehicle" do
      vehicle = create(:vehicle, hub: hub)

      delete "/api/v1/vehicles/#{vehicle.id}", headers: authenticated_headers

      expect(response).to have_http_status(:no_content)
      expect(Vehicle.find_by(id: vehicle.id)).to be_nil
    end
  end
end
