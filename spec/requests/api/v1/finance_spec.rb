require "rails_helper"

RSpec.describe "Api::V1::Finance", type: :request do
  describe "authentication" do
    def request_without_auth
      get "/api/v1/finance"
    end

    def request_with_invalid_auth
      get "/api/v1/finance", headers: { "Authorization" => "Bearer not-a-real-token" }
    end

    include_examples "requires api authentication"
  end

  it "supports the full CRUD lifecycle" do
    create_list(:payment_due, 2)
    get "/api/v1/finance", headers: authenticated_headers
    expect(response.parsed_body.size).to eq(2)

    params = { payment_due: { vendor: "New Vendor", amount: 42_000, due_date: 15.days.from_now.to_date } }
    post "/api/v1/finance", params: params, headers: authenticated_headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to have_key("aging_days")
    payment_due_id = response.parsed_body["id"]

    patch "/api/v1/finance/#{payment_due_id}",
      params: { payment_due: { payment_status: "paid" } },
      headers: authenticated_headers
    expect(response.parsed_body["payment_status"]).to eq("paid")

    delete "/api/v1/finance/#{payment_due_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end
end
