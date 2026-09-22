require "rails_helper"

RSpec.describe "Api::V1::NotificationsStream", type: :request do
  describe "authentication" do
    it "rejects a missing ticket without entering the stream loop" do
      get "/api/v1/notifications/stream"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an invalid/tampered ticket" do
      get "/api/v1/notifications/stream", params: { ticket: "not-a-real-ticket" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired ticket" do
      expired_ticket = Rails.application.message_verifier(:sse_notifications).generate(
        { "user_id" => 42 }, expires_in: -1.second, purpose: :sse_notifications
      )

      get "/api/v1/notifications/stream", params: { ticket: expired_ticket }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a ticket signed for a different purpose" do
      wrong_purpose_ticket = Rails.application.message_verifier(:sse_notifications).generate(
        { "user_id" => 42 }, purpose: :something_else
      )

      get "/api/v1/notifications/stream", params: { ticket: wrong_purpose_ticket }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
