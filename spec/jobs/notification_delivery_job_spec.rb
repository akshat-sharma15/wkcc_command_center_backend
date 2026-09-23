require "rails_helper"

RSpec.describe NotificationDeliveryJob do
  def perform(notification_id)
    described_class.new.perform(notification_id)
  end

  describe "in_app delivery" do
    it "publishes to Redis and marks the notification delivered" do
      notification = create(:notification, channel: "in_app", recipient_user_id: 42)
      expect(RealtimeNotificationPublisher).to receive(:publish).with(notification)

      perform(notification.id)

      expect(notification.reload.status).to eq("delivered")
      expect(notification.delivered_at).to be_present
    end

    it "marks failed and re-raises on a transient publish failure (Sidekiq retries)" do
      notification = create(:notification, channel: "in_app")
      allow(RealtimeNotificationPublisher).to receive(:publish).and_raise(Redis::CannotConnectError, "boom")

      expect { perform(notification.id) }.to raise_error(Redis::CannotConnectError)

      expect(notification.reload.status).to eq("failed")
      expect(notification.error_message).to include("boom")
      expect(notification.attempts).to eq(1)
    end
  end

  describe "slack delivery" do
    it "marks failed (no retry) when Slack is not connected — does not call the Slack API" do
      notification = create(:notification, channel: "slack")

      perform(notification.id)

      expect(notification.reload.status).to eq("failed")
      expect(notification.error_message).to eq("Slack is not connected")
    end

    context "with a connected Slack integration" do
      before do
        create(:integration, provider: "slack", status: "connected", bot_token: "xoxb-real-token")
      end

      it "marks failed (no retry) when SLACK_NOTIFICATION_CHANNEL is not configured" do
        notification = create(:notification, channel: "slack")

        perform(notification.id)

        expect(notification.reload.status).to eq("failed")
        expect(notification.error_message).to eq("SLACK_NOTIFICATION_CHANNEL is not configured")
      end

      context "with SLACK_NOTIFICATION_CHANNEL configured" do
        around do |example|
          original = ENV["SLACK_NOTIFICATION_CHANNEL"]
          ENV["SLACK_NOTIFICATION_CHANNEL"] = "#alerts"
          example.run
          ENV["SLACK_NOTIFICATION_CHANNEL"] = original
        end

        it "posts the title+message and marks delivered with Slack's ts as external_reference" do
          notification = create(:notification, channel: "slack", title: "Vehicle Failure", message: "VH-1 failed")
          stub_request(:post, "https://slack.com/api/chat.postMessage")
            .with(body: { channel: "#alerts", text: "*Vehicle Failure*\nVH-1 failed" }.to_json)
            .to_return(status: 200, body: { ok: true, ts: "1111.2222" }.to_json)

          perform(notification.id)

          notification.reload
          expect(notification.status).to eq("delivered")
          expect(notification.external_reference).to eq("1111.2222")
        end

        it "marks failed (no retry) when Slack reports a logical error" do
          notification = create(:notification, channel: "slack")
          stub_request(:post, "https://slack.com/api/chat.postMessage").to_return(
            status: 200,
            body: { ok: false, error: "not_in_channel" }.to_json
          )

          perform(notification.id)

          expect(notification.reload.status).to eq("failed")
          expect(notification.error_message).to eq("not_in_channel")
        end

        it "marks failed and re-raises on a transient Slack transport failure (Sidekiq retries)" do
          notification = create(:notification, channel: "slack")
          stub_request(:post, "https://slack.com/api/chat.postMessage").to_timeout

          expect { perform(notification.id) }.to raise_error(SlackOauthClient::SlackApiError)

          expect(notification.reload.status).to eq("failed")
        end
      end
    end
  end

  describe "Alert survives a Slack delivery failure" do
    it "the Alert row is untouched regardless of Notification delivery outcome" do
      alert = create(:alert)
      notification = create(:notification, alert: alert, channel: "slack")

      perform(notification.id)

      expect(notification.reload.status).to eq("failed")
      expect(alert.reload).to be_persisted
      expect(alert.status).to eq("open")
    end
  end

  it "is a no-op for a since-deleted notification" do
    expect { perform(999_999) }.not_to raise_error
  end
end
