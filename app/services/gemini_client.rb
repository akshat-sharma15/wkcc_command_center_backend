# Talks to Google's Gemini API directly over its classic REST
# `generateContent` endpoint (stdlib Net::HTTP — same convention as
# SlackOauthClient; no Ruby Gemini SDK is assumed to exist). The only
# place GEMINI_API_KEY is ever read or transmitted — never logged, never
# included in any error message or returned payload.
#
# NOTE ON API CHOICE: the newer "Interactions API"
# (v1beta/interactions) was tried first but rejects plain API-key auth
# outright ("ACCESS_TOKEN_TYPE_UNSUPPORTED" - it requires a full OAuth2
# access token, which a Google AI Studio API key is not). Verified live
# against the real API: v1beta/models/{model}:generateContent DOES accept
# a plain API key via the x-goog-api-key header and fully supports
# function calling - this is the actual integration path.
#
# NOTE ON THOUGHT SIGNATURES: gemini-3.8-flash is a "thinking" model.
# When it returns a functionCall part, that part carries a
# `thoughtSignature` field that MUST be replayed verbatim on the next
# turn's history (see AiChatService#history_for) - omitting it makes the
# very next request fail with INVALID_ARGUMENT ("Function call is
# missing a thought_signature..."). This is why history stores the RAW
# API parts, not a hand-simplified version of them.
require "net/http"
require "uri"
require "json"

class GeminiClient
  API_BASE = "https://generativelanguage.googleapis.com/v1beta".freeze
  DEFAULT_MODEL = "gemini-3.8-flash".freeze
  REQUEST_TIMEOUT = 30

  # Gemini's free/shared capacity genuinely flaps between 200 and 503
  # ("high demand") from one request to the next (verified live - three
  # consecutive identical requests came back 503, 200, 503) - a short
  # retry absorbs that instead of surfacing it to the chat user. 429
  # (quota exceeded) is retried too since it's equally transient, but not
  # worth retrying indefinitely against a hard per-minute cap.
  RETRYABLE_CODES = %w[429 503].freeze
  MAX_ATTEMPTS = 3
  RETRY_BACKOFF_SECONDS = [ 1, 2 ].freeze

  ApiError = Class.new(StandardError)
  ConfigurationError = Class.new(StandardError)

  def self.configured?
    ENV["GEMINI_API_KEY"].present?
  end

  def initialize(api_key: ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_MODEL", DEFAULT_MODEL))
    raise ConfigurationError, "GEMINI_API_KEY is not set" if api_key.blank?

    @api_key = api_key
    @model = model
  end

  # `contents` is the full conversation history as Gemini's own
  # `contents` array shape: [{ role: "user"|"model", parts: [...] }, ...]
  # - see AiChatService#history_for for how it's built.
  # `tools` is an array of function declarations (see GeminiTools) - this
  # method wraps them in the single `tools: [{ functionDeclarations: [...] }]`
  # entry the API expects.
  # `system_instruction` is a plain string.
  #
  # Returns the parsed response body (a Hash) - callers read
  # `candidates[0].content.parts` for text/functionCall parts.
  def generate(contents:, tools: nil, system_instruction: nil)
    body = { contents: contents }
    body[:tools] = [ { functionDeclarations: tools } ] if tools.present?
    body[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction.present?

    response = post("/models/#{@model}:generateContent", body)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise ApiError, "Gemini returned an unparseable response: #{e.class}"
  end

  private

  def post(path, body)
    uri = URI("#{API_BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = REQUEST_TIMEOUT
    http.open_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-goog-api-key"] = @api_key
    request.body = body.to_json

    response = nil
    MAX_ATTEMPTS.times do |attempt|
      response = http.request(request)
      break if response.is_a?(Net::HTTPSuccess)
      break unless RETRYABLE_CODES.include?(response.code) && attempt < MAX_ATTEMPTS - 1

      sleep(RETRY_BACKOFF_SECONDS[attempt])
    end

    raise ApiError, "Gemini API error (HTTP #{response.code}): #{error_message_from(response)}" unless response.is_a?(Net::HTTPSuccess)

    response
  rescue Timeout::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise ApiError, "Gemini API request failed: #{e.class}"
  end

  # Surfaces Gemini's own error message (e.g. "model overloaded",
  # "invalid argument: ...") for logs/debugging - never includes the API
  # key, which is only ever sent as a header, never part of the body.
  def error_message_from(response)
    JSON.parse(response.body).dig("error", "message") || response.body.to_s.truncate(200)
  rescue JSON::ParserError
    response.body.to_s.truncate(200)
  end
end
