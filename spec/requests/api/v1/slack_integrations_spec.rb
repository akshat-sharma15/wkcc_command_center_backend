require "rails_helper"

RSpec.describe "Api::V1::SlackIntegrations", type: :request do
  describe "GET /api/v1/integrations/slack" do
    it "reports disconnected when no integration exists" do
      get "/api/v1/integrations/slack"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "connected" => false })
    end

    it "reports disconnected when the integration exists but isn't connected" do
      create(:integration, status: "disconnected")
      get "/api/v1/integrations/slack"
      expect(response.parsed_body).to eq({ "connected" => false })
    end

    it "reports connected with workspace info, and never a token, when connected" do
      create(:integration, status: "connected", workspace_id: "T123", workspace_name: "Acme Corp",
        bot_token: "xoxb-should-never-appear")

      get "/api/v1/integrations/slack"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["connected"]).to eq(true)
      expect(body["integration"]).to eq(
        "id" => Integration.last.id,
        "type" => "slack",
        "status" => "connected",
        "enabled" => true,
        "workspace" => { "id" => "T123", "name" => "Acme Corp" }
      )
      expect(response.body).not_to include("xoxb-should-never-appear")
    end

    it "follows the app's existing authentication convention (currently disabled repo-wide)" do
      get "/api/v1/integrations/slack"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/integrations/slack/connect" do
    it "returns an authorization_url and never a secret" do
      get "/api/v1/integrations/slack/connect"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["authorization_url"]).to start_with("https://slack.com/oauth/v2/authorize?")
      expect(response.body).not_to include(ENV.fetch("SLACK_CLIENT_SECRET", "unset-in-test"))
    end

    it "generates a real, persisted OAuth state (CSRF protection)" do
      expect { get "/api/v1/integrations/slack/connect" }.to change(SlackOauthState, :count).by(1)
      state = SlackOauthState.last.state
      expect(response.parsed_body["authorization_url"]).to include("state=#{state}")
    end
  end

  describe "GET /api/v1/integrations/slack/callback" do
    def stub_slack_success(team_id: "T123", team_name: "Acme Corp")
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_return(
        status: 200,
        body: {
          ok: true,
          access_token: "xoxb-new-token",
          bot_user_id: "B999",
          scope: "chat:write",
          team: { id: team_id, name: team_name }
        }.to_json
      )
    end

    it "rejects a missing/invalid state and redirects to the frontend with an error" do
      get "/api/v1/integrations/slack/callback", params: { code: "abc", state: "not-a-real-state" }

      expect(response).to have_http_status(:found)
      uri = URI.parse(response.headers["Location"])
      expect(uri.host).to eq("localhost")
      expect(uri.port).to eq(9000)
      expect(Rack::Utils.parse_query(uri.query)).to include("slack" => "error", "reason" => "invalid_state")
    end

    it "rejects an expired state" do
      oauth_state = SlackOauthState.create!(state: "expired-state", expires_at: 1.minute.ago)
      get "/api/v1/integrations/slack/callback", params: { code: "abc", state: oauth_state.state }

      expect(response).to have_http_status(:found)
      expect(Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["slack"]).to eq("error")
    end

    it "surfaces a Slack-reported error (e.g. user cancelled) without calling the token endpoint" do
      get "/api/v1/integrations/slack/callback", params: { error: "access_denied" }

      expect(response).to have_http_status(:found)
      query = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
      expect(query).to eq("slack" => "error", "reason" => "access_denied")
    end

    it "handles a Slack-side token exchange failure" do
      oauth_state = SlackOauthState.issue!
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_return(
        status: 200,
        body: { ok: false, error: "invalid_code" }.to_json
      )

      get "/api/v1/integrations/slack/callback", params: { code: "bad", state: oauth_state.state }

      expect(response).to have_http_status(:found)
      query = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
      expect(query).to eq("slack" => "error", "reason" => "invalid_code")
      expect(Integration.find_by(provider: "slack")).to be_nil
    end

    it "handles Slack being unreachable" do
      oauth_state = SlackOauthState.issue!
      stub_request(:post, "https://slack.com/api/oauth.v2.access").to_timeout

      get "/api/v1/integrations/slack/callback", params: { code: "x", state: oauth_state.state }

      expect(response).to have_http_status(:found)
      expect(Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["reason"]).to eq("slack_unreachable")
    end

    it "on success, stores the integration, redirects to the frontend, and consumes the state" do
      oauth_state = SlackOauthState.issue!
      stub_slack_success

      get "/api/v1/integrations/slack/callback", params: { code: "good-code", state: oauth_state.state }

      expect(response).to have_http_status(:found)
      query = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
      expect(query).to eq("slack" => "success")

      integration = Integration.find_by(provider: "slack")
      expect(integration.status).to eq("connected")
      expect(integration.workspace_id).to eq("T123")
      expect(integration.workspace_name).to eq("Acme Corp")
      expect(integration.bot_token).to eq("xoxb-new-token")
      expect(SlackOauthState.exists?(oauth_state.id)).to eq(false)
    end

    it "reconnecting the same (or a different) workspace updates the existing row rather than duplicating it" do
      create(:integration, status: "connected", workspace_id: "T_OLD", workspace_name: "Old Co",
        bot_token: "xoxb-old")
      oauth_state = SlackOauthState.issue!
      stub_slack_success(team_id: "T_NEW", team_name: "New Co")

      expect do
        get "/api/v1/integrations/slack/callback", params: { code: "good-code", state: oauth_state.state }
      end.not_to change(Integration, :count)

      integration = Integration.find_by(provider: "slack")
      expect(integration.workspace_id).to eq("T_NEW")
      expect(integration.bot_token).to eq("xoxb-new-token")
    end

    it "a used state cannot be replayed" do
      oauth_state = SlackOauthState.issue!
      stub_slack_success

      get "/api/v1/integrations/slack/callback", params: { code: "good-code", state: oauth_state.state }
      expect(Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["slack"]).to eq("success")

      get "/api/v1/integrations/slack/callback", params: { code: "good-code", state: oauth_state.state }
      expect(Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["slack"]).to eq("error")
    end
  end

  describe "DELETE /api/v1/integrations/slack/:id" do
    it "disconnects, clears the token, and revokes it with Slack" do
      integration = create(:integration, status: "connected", bot_token: "xoxb-to-revoke",
        workspace_id: "T1", workspace_name: "Co")
      revoke_stub = stub_request(:post, "https://slack.com/api/auth.revoke")
        .with(headers: { "Authorization" => "Bearer xoxb-to-revoke" })
        .to_return(status: 200, body: { ok: true }.to_json)

      delete "/api/v1/integrations/slack/#{integration.id}"

      expect(response).to have_http_status(:no_content)
      expect(revoke_stub).to have_been_requested
      integration.reload
      expect(integration.status).to eq("disconnected")
      expect(integration.enabled).to eq(false)
      expect(integration.bot_token).to be_nil
      # Disconnecting keeps workspace history rather than wiping it -
      # only the credential itself is destroyed.
      expect(integration.workspace_id).to eq("T1")
    end

    it "returns 404 for a non-existent integration" do
      delete "/api/v1/integrations/slack/999999"
      expect(response).to have_http_status(:not_found)
    end

    it "does not affect other integrations" do
      slack = create(:integration, provider: "slack", status: "connected")
      # A hypothetical future second provider row - built via `.new` +
      # `save(validate: false)` since PROVIDERS only allows "slack" today.
      other = Integration.new(provider: "teams", status: "connected", enabled: true)
      other.save!(validate: false)

      delete "/api/v1/integrations/slack/#{slack.id}"

      expect(response).to have_http_status(:no_content)
      expect(other.reload.status).to eq("connected") # untouched by disconnecting slack
    end
  end
end
