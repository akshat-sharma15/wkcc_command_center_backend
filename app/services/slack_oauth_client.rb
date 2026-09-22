# Talks to Slack's OAuth v2 endpoints directly (stdlib Net::HTTP — no HTTP
# client gem exists in this project yet, and one call site doesn't
# justify adding one). The only place SLACK_CLIENT_SECRET and bot tokens
# are ever read or transmitted — never logged, never returned as-is to a
# caller outside this class.
#
# Explicit requires: Net::HTTP/URI are stdlib, not autoloaded by Rails.
# RSpec never caught the missing require because WebMock itself requires
# "net/http" as part of its own setup, masking it in the test environment.
require "net/http"
require "uri"

class SlackOauthClient
  AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize"
  TOKEN_URL = "https://slack.com/api/oauth.v2.access"
  REVOKE_URL = "https://slack.com/api/auth.revoke"
  POST_MESSAGE_URL = "https://slack.com/api/chat.postMessage"

  # Bot scope needed for the eventual purpose of this integration (posting
  # alerts to Slack, built in a later phase) — requested now so
  # reconnecting the workspace isn't required again once delivery ships.
  BOT_SCOPES = "chat:write"

  SlackApiError = Class.new(StandardError)

  def self.configured?
    ENV["SLACK_CLIENT_ID"].present? && ENV["SLACK_CLIENT_SECRET"].present? && ENV["SLACK_REDIRECT_URI"].present?
  end

  def self.authorization_url(state:)
    params = {
      client_id: ENV.fetch("SLACK_CLIENT_ID"),
      scope: BOT_SCOPES,
      redirect_uri: ENV.fetch("SLACK_REDIRECT_URI"),
      state: state
    }
    "#{AUTHORIZE_URL}?#{params.to_query}"
  end

  # Returns the parsed Slack response hash (includes "ok", and on success
  # "access_token"/"team"/"bot_user_id"/"scope"; on failure "error").
  # Never raises on a Slack-reported failure (ok: false) — that's a normal
  # outcome the caller handles; only a transport-level failure raises.
  def self.exchange_code(code:)
    response = Net::HTTP.post_form(
      URI(TOKEN_URL),
      client_id: ENV.fetch("SLACK_CLIENT_ID"),
      client_secret: ENV.fetch("SLACK_CLIENT_SECRET"),
      code: code,
      redirect_uri: ENV.fetch("SLACK_REDIRECT_URI")
    )
    JSON.parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError => e
    raise SlackApiError, "Slack token exchange failed: #{e.class}"
  end

  # Best-effort revocation — Slack recommends revoking a token that will
  # no longer be used rather than just forgetting it locally. Swallows
  # failures (network/Slack-side) since disconnect must still succeed
  # locally either way; nothing sensitive is logged.
  def self.revoke_token(bot_token:)
    uri = URI(REVOKE_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    JSON.parse(response.body)["ok"] == true
  rescue StandardError
    false
  end

  # Posts a message to a channel using the connected workspace's bot
  # token. Returns Slack's parsed response hash (never raises on a
  # Slack-reported failure — "ok": false is a normal outcome the caller
  # handles, e.g. the bot not being in the target channel). Only a
  # transport-level failure raises, same convention as #exchange_code.
  def self.post_message(bot_token:, channel:, text:)
    uri = URI(POST_MESSAGE_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"
    request["Content-Type"] = "application/json"
    request.body = { channel: channel, text: text }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    JSON.parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise SlackApiError, "Slack chat.postMessage failed: #{e.class}"
  end
end
