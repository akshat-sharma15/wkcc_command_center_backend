require "rails_helper"

RSpec.describe "Api::V1::AlertRecipients", type: :request do
  it "reads roles without writing to Superset, returning [] since it's not configured here" do
    expect(SupersetDirectory.configured?).to eq(false)
    get "/api/v1/alert-recipients/roles"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it "reads users without writing to Superset, returning [] since it's not configured here" do
    get "/api/v1/alert-recipients/users"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it "returns roles from SupersetDirectory when configured, read-only" do
    allow(SupersetDirectory).to receive_messages(
      configured?: true,
      roles: [ { id: 5, name: "Operations Manager" } ]
    )
    get "/api/v1/alert-recipients/roles"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([ { "id" => 5, "name" => "Operations Manager" } ])
  end
end
