require "rails_helper"

RSpec.describe SlackOauthClient do
  describe ".configured?" do
    it "is true when SLACK_CLIENT_ID/SECRET/REDIRECT_URI are all present" do
      expect(described_class.configured?).to eq(
        ENV["SLACK_CLIENT_ID"].present? && ENV["SLACK_CLIENT_SECRET"].present? && ENV["SLACK_REDIRECT_URI"].present?
      )
    end
  end

  describe ".authorization_url" do
    it "includes client_id, scope, redirect_uri, and the given state, but never the client secret" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SLACK_CLIENT_ID").and_return("client-123")
      allow(ENV).to receive(:fetch).with("SLACK_REDIRECT_URI").and_return("http://localhost:3001/api/v1/integrations/slack/callback")

      url = described_class.authorization_url(state: "state-abc")

      expect(url).to start_with("https://slack.com/oauth/v2/authorize?")
      expect(url).to include("client_id=client-123")
      expect(url).to include("state=state-abc")
      expect(url).to include("scope=chat%3Awrite")
      expect(url).not_to include(ENV["SLACK_CLIENT_SECRET"].to_s) if ENV["SLACK_CLIENT_SECRET"].present?
    end
  end

  describe ".exchange_code" do
    it "returns Slack's parsed success response" do
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_return(
        status: 200,
        body: {
          ok: true,
          access_token: "xoxb-real-token",
          bot_user_id: "B123",
          scope: "chat:write",
          team: { id: "T123", name: "Acme Corp" }
        }.to_json
      )

      result = described_class.exchange_code(code: "auth-code-123")

      expect(result["ok"]).to eq(true)
      expect(result["access_token"]).to eq("xoxb-real-token")
      expect(result.dig("team", "name")).to eq("Acme Corp")
    end

    it "returns Slack's parsed failure response without raising" do
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_return(
        status: 200,
        body: { ok: false, error: "invalid_code" }.to_json
      )

      result = described_class.exchange_code(code: "bad-code")

      expect(result["ok"]).to eq(false)
      expect(result["error"]).to eq("invalid_code")
    end

    it "raises SlackApiError on a transport-level failure" do
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_return(status: 200, body: "not json")

      expect { described_class.exchange_code(code: "x") }.to raise_error(SlackOauthClient::SlackApiError)
    end
  end

  describe ".revoke_token" do
    it "returns true when Slack confirms revocation" do
      stub_request(:post, "https://slack.com/api/auth.revoke")
        .with(headers: { "Authorization" => "Bearer xoxb-real-token" })
        .to_return(status: 200, body: { ok: true, revoked: true }.to_json)

      expect(described_class.revoke_token(bot_token: "xoxb-real-token")).to eq(true)
    end

    it "returns false (never raises) when Slack rejects the token" do
      stub_request(:post, "https://slack.com/api/auth.revoke").to_return(
        status: 200,
        body: { ok: false, error: "invalid_auth" }.to_json
      )

      expect(described_class.revoke_token(bot_token: "already-invalid")).to eq(false)
    end

    it "returns false (never raises) on a network failure" do
      stub_request(:post, "https://slack.com/api/auth.revoke").to_timeout

      expect(described_class.revoke_token(bot_token: "xoxb-x")).to eq(false)
    end
  end

  describe ".post_message" do
    it "returns Slack's parsed success response, including the message timestamp" do
      stub_request(:post, "https://slack.com/api/chat.postMessage")
        .with(
          headers: { "Authorization" => "Bearer xoxb-real-token", "Content-Type" => "application/json" },
          body: { channel: "#alerts", text: "*Vehicle Failure*\nVH-1 failed" }.to_json
        )
        .to_return(status: 200, body: { ok: true, ts: "1234.5678", channel: "C123" }.to_json)

      result = described_class.post_message(bot_token: "xoxb-real-token", channel: "#alerts",
        text: "*Vehicle Failure*\nVH-1 failed")

      expect(result["ok"]).to eq(true)
      expect(result["ts"]).to eq("1234.5678")
    end

    it "returns Slack's parsed failure response without raising (e.g. bot not in channel)" do
      stub_request(:post, "https://slack.com/api/chat.postMessage").to_return(
        status: 200,
        body: { ok: false, error: "not_in_channel" }.to_json
      )

      result = described_class.post_message(bot_token: "xoxb-x", channel: "#alerts", text: "hi")

      expect(result["ok"]).to eq(false)
      expect(result["error"]).to eq("not_in_channel")
    end

    it "raises SlackApiError on a transport-level failure" do
      stub_request(:post, "https://slack.com/api/chat.postMessage").to_timeout

      expect { described_class.post_message(bot_token: "xoxb-x", channel: "#alerts", text: "hi") }
        .to raise_error(SlackOauthClient::SlackApiError)
    end
  end
end
