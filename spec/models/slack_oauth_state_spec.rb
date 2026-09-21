require "rails_helper"

RSpec.describe SlackOauthState, type: :model do
  it "issues a unique, non-expired state token" do
    oauth_state = SlackOauthState.issue!
    expect(oauth_state.state).to be_present
    expect(oauth_state).not_to be_expired
  end

  it "generates a different token each time" do
    expect(SlackOauthState.issue!.state).not_to eq(SlackOauthState.issue!.state)
  end

  it "is expired? once past its TTL" do
    oauth_state = SlackOauthState.create!(state: "abc", expires_at: 1.minute.ago)
    expect(oauth_state).to be_expired
  end
end
