require "rails_helper"

# The SSE stream is deprecated (in-app delivery is polling - see
# notifications_poll_spec.rb). It must answer immediately and never hold a
# request thread, whatever the client sends.
RSpec.describe "Api::V1::NotificationsStream (deprecated)", type: :request do
  it "answers 204 immediately, with or without a ticket, so old EventSource clients stop reconnecting" do
    ticket = Rails.application.message_verifier(:sse_notifications).generate({ "user_id" => 1 }, purpose: :sse_notifications)
    [ {}, { ticket: ticket }, { ticket: "garbage" } ].each do |params|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get "/api/v1/notifications/stream", params: params
      expect(response).to have_http_status(:no_content)
      expect(response.headers["Deprecation"]).to eq("true")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end
  end

  it "no longer uses ActionController::Live (no streaming threads)" do
    expect(Api::V1::NotificationsStreamController.ancestors).not_to include(ActionController::Live)
  end
end
