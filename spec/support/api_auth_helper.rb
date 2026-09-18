module ApiAuthHelper
  # Creates a real ApiClient via the model's own token-issuing method and
  # returns headers ready to pass to a request spec's `get`/`post`/etc.
  def authenticated_headers(scopes: [])
    _client, raw_token = ApiClient.create_with_token!(name: "Test Client #{SecureRandom.hex(4)}", scopes: scopes)
    { "Authorization" => "Bearer #{raw_token}" }
  end
end

RSpec.configure do |config|
  config.include ApiAuthHelper, type: :request
end
