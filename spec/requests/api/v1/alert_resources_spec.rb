require "rails_helper"

RSpec.describe "Api::V1::AlertResources", type: :request do
  describe "GET /api/v1/alert-resources" do
    it "returns only the allowed groups" do
      get "/api/v1/alert-resources"
      expect(response).to have_http_status(:ok)
      keys = response.parsed_body.map { |g| g["key"] }
      expect(keys).to match_array(%w[vehicles hubs packages payments workforce])
    end

    it "never exposes trips or arbitrary models" do
      get "/api/v1/alert-resources"
      keys = response.parsed_body.map { |g| g["key"] }
      expect(keys).not_to include("trips", "users", "employees", "vendors")
    end
  end

  describe "GET /api/v1/alert-resources/:group/fields" do
    it "returns only fields marked alertable on at least one record" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status capacity])
      create(:vehicle, allow_alerts: false, alertable_fields: %w[vendor])

      get "/api/v1/alert-resources/vehicles/fields"
      expect(response).to have_http_status(:ok)
      keys = response.parsed_body.map { |f| f["key"] }
      expect(keys).to match_array(%w[status capacity])
    end

    it "includes correct operators per field type" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status capacity])

      get "/api/v1/alert-resources/vehicles/fields"
      by_key = response.parsed_body.index_by { |f| f["key"] }
      expect(by_key["status"]["operators"]).to eq(%w[= != contains])
      expect(by_key["capacity"]["operators"]).to eq(%w[= != > < >= <=])
      expect(by_key["capacity"]["type"]).to eq("number")
    end

    it "returns 404 for an unsupported group" do
      get "/api/v1/alert-resources/trips/fields"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/alert-resources/:group/fields/:field/options" do
    it "returns the enum values for an enum-backed field" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      get "/api/v1/alert-resources/vehicles/fields/status/options"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to match_array(%w[active maintenance out_of_service])
    end

    it "returns 422 for a field with no finite option set" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity])
      get "/api/v1/alert-resources/vehicles/fields/capacity/options"
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a field that is not alertable" do
      create(:vehicle, allow_alerts: true, alertable_fields: %w[status])
      get "/api/v1/alert-resources/vehicles/fields/vendor/options"
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for an unsupported group" do
      get "/api/v1/alert-resources/trips/fields/status/options"
      expect(response).to have_http_status(:not_found)
    end
  end
end
