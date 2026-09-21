require "rails_helper"

RSpec.describe Integration, type: :model do
  it "is valid with a supported provider" do
    expect(build(:integration)).to be_valid
  end

  it "rejects an unsupported provider" do
    expect(build(:integration, provider: "teams")).not_to be_valid
  end

  it "requires a unique provider" do
    create(:integration, provider: "slack")
    expect(build(:integration, provider: "slack")).not_to be_valid
  end

  it "encrypts bot_token at rest" do
    integration = create(:integration, bot_token: "xoxb-super-secret")
    raw = CommandCenterRecord.connection.select_value(
      "SELECT bot_token FROM integrations WHERE id = #{integration.id}"
    )
    expect(raw).not_to include("xoxb-super-secret")
    expect(Integration.find(integration.id).bot_token).to eq("xoxb-super-secret")
  end

  it "is connected? only when status is connected" do
    expect(build(:integration, status: "connected")).to be_connected
    expect(build(:integration, status: "disconnected")).not_to be_connected
  end
end
