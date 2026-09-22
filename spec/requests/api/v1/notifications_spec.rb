require "rails_helper"

RSpec.describe "Api::V1::Notifications", type: :request do
  let(:headers) { { "X-Superset-User-Id" => "42" } }

  describe "authentication" do
    it "requires X-Superset-User-Id" do
      get "/api/v1/notifications"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a blank X-Superset-User-Id" do
      get "/api/v1/notifications", headers: { "X-Superset-User-Id" => "" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/notifications" do
    it "returns only the authenticated user's notifications, never another user's" do
      mine = create(:notification, recipient_user_id: 42, title: "Mine")
      create(:notification, recipient_user_id: 43, title: "Not mine")

      get "/api/v1/notifications", headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |n| n["id"] }
      expect(ids).to eq([ mine.id ])
    end

    it "never accepts a client-supplied recipient_user_id override" do
      create(:notification, recipient_user_id: 43, title: "Not mine")

      get "/api/v1/notifications", params: { recipient_user_id: 43 }, headers: headers

      expect(response.parsed_body).to eq([])
    end
  end

  describe "GET /api/v1/notifications/:id" do
    it "returns the caller's own notification" do
      notification = create(:notification, recipient_user_id: 42, title: "Mine")

      get "/api/v1/notifications/#{notification.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["title"]).to eq("Mine")
    end

    it "returns 404 for another user's notification" do
      other = create(:notification, recipient_user_id: 43)

      get "/api/v1/notifications/#{other.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/notifications/unread" do
    it "returns only unread notifications for the authenticated user" do
      unread = create(:notification, recipient_user_id: 42, read_at: nil)
      create(:notification, recipient_user_id: 42, read_at: Time.current)
      create(:notification, recipient_user_id: 43, read_at: nil)

      get "/api/v1/notifications/unread", headers: headers

      expect(response.parsed_body.map { |n| n["id"] }).to eq([ unread.id ])
    end
  end

  describe "PATCH /api/v1/notifications/:id/read" do
    it "marks the caller's own notification read" do
      notification = create(:notification, recipient_user_id: 42, read_at: nil)

      patch "/api/v1/notifications/#{notification.id}/read", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["read"]).to eq(true)
      expect(notification.reload.read_at).to be_present
    end

    it "returns 404 for another user's notification — never marks it, never confirms it exists" do
      other = create(:notification, recipient_user_id: 43, read_at: nil)

      patch "/api/v1/notifications/#{other.id}/read", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(other.reload.read_at).to be_nil
    end
  end

  describe "GET /api/v1/notifications/sse-ticket" do
    it "issues a ticket scoped to the authenticated user" do
      get "/api/v1/notifications/sse-ticket", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ticket"]).to be_present
      expect(body["expires_in"]).to eq(60)

      payload = Rails.application.message_verifier(:sse_notifications).verify(body["ticket"], purpose: :sse_notifications)
      expect(payload["user_id"]).to eq(42)
    end

    it "requires authentication like every other notifications endpoint" do
      get "/api/v1/notifications/sse-ticket"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
