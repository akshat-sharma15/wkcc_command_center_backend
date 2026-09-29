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
  UPDATE_MESSAGE_URL = "https://slack.com/api/chat.update"
  JOIN_CHANNEL_URL = "https://slack.com/api/conversations.join"

  # chat:write alone only lets the bot post to channels it has already
  # been invited into — chat.postMessage otherwise fails with
  # "not_in_channel". chat:write.public covers public channels without an
  # invite, and channels:join lets #join_channel self-heal (see below) as
  # a fallback for whichever channels chat:write.public doesn't cover.
  # NOTE: scopes are fixed at the time a workspace authorizes the app —
  # a workspace connected before this change must disconnect/reconnect
  # Slack once to pick these up.
  BOT_SCOPES = "chat:write,chat:write.public,channels:join"

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
  # `blocks` (optional Block Kit layout) renders the rich message; `text`
  # stays the notification/accessibility fallback Slack requires.
  def self.post_message(bot_token:, channel:, text:, blocks: nil)
    uri = URI(POST_MESSAGE_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"
    request["Content-Type"] = "application/json"
    request.body = { channel: channel, text: text, blocks: blocks.presence }.compact.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    JSON.parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise SlackApiError, "Slack chat.postMessage failed: #{e.class}"
  end

  # Re-renders a previously posted message (e.g. an incident whose status
  # changed). Same raise/return convention as #post_message.
  def self.update_message(bot_token:, channel:, ts:, text:, blocks: nil)
    uri = URI(UPDATE_MESSAGE_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"
    request["Content-Type"] = "application/json"
    request.body = { channel: channel, ts: ts, text: text, blocks: blocks.presence }.compact.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    JSON.parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise SlackApiError, "Slack chat.update failed: #{e.class}"
  end

  # Self-heal path for "not_in_channel": have the bot join the (public)
  # channel itself instead of requiring a human to run /invite in Slack.
  # Only works with the channels:join scope (see BOT_SCOPES) and only for
  # public channels — Slack has no API for a bot to join a private
  # channel uninvited, same convention as #post_message re: raise/return.
  def self.join_channel(bot_token:, channel:)
    uri = URI(JOIN_CHANNEL_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"
    request["Content-Type"] = "application/json"
    request.body = { channel: channel }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    JSON.parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError, Errno::ECONNREFUSED => e
    raise SlackApiError, "Slack conversations.join failed: #{e.class}"
  end
end
