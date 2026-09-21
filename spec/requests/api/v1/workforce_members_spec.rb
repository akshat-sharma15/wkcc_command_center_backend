require "rails_helper"

RSpec.describe "Api::V1::WorkforceMembers", type: :request do
  let(:hub) { create(:hub) }

  it "supports the full CRUD lifecycle" do
    create_list(:workforce_member, 2, hub: hub)
    get "/api/v1/workforce_members", headers: authenticated_headers
    expect(response.parsed_body.size).to eq(2)

    post "/api/v1/workforce_members",
      params: { workforce_member: { identifier: "WF-NEW", name: "New Worker", role_type: "guard", hub_id: hub.id } },
      headers: authenticated_headers
    expect(response).to have_http_status(:created)
    member_id = response.parsed_body["id"]

    patch "/api/v1/workforce_members/#{member_id}",
      params: { workforce_member: { attendance_status: "absent" } },
      headers: authenticated_headers
    expect(response.parsed_body["attendance_status"]).to eq("absent")

    delete "/api/v1/workforce_members/#{member_id}", headers: authenticated_headers
    expect(response).to have_http_status(:no_content)
  end
end
