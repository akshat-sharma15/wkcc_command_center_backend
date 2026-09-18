FactoryBot.define do
  factory :api_client do
    sequence(:name) { |n| "Test Client #{n}" }
    scopes { [] }
    active { true }

    transient do
      raw_token { SecureRandom.hex(32) }
    end

    token_digest { ApiClient.digest(raw_token) }

    # Usage: client, token = create(:api_client, :with_known_token)
    trait :with_known_token do
      raw_token { "test-token-#{SecureRandom.hex(8)}" }
    end
  end
end
