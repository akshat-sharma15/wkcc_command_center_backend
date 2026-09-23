require "rails_helper"

RSpec.describe RealtimeNotificationPublisher do
  describe ".channel_for" do
    it "is scoped to one user id, never a broadcast-to-everyone channel" do
      expect(described_class.channel_for(42)).to eq("notifications:user:42")
      expect(described_class.channel_for(42)).not_to eq(described_class.channel_for(43))
    end
  end

  describe ".publish" do
    it "publishes the notification payload on that recipient's channel, and only that channel" do
      notification = create(:notification, recipient_user_id: 77, title: "Vehicle Failure", message: "VH-1 failed")

      redis = Redis.new(url: described_class.redis_url)
      received = nil
      subscriber_thread = Thread.new do
        redis.subscribe(described_class.channel_for(77)) do |on|
          on.message { |_channel, payload| received = payload; redis.unsubscribe }
        end
      end
      sleep 0.2 # let the subscriber actually establish before publishing

      described_class.publish(notification)
      subscriber_thread.join(2)

      expect(received).to be_present
      data = JSON.parse(received)
      expect(data["id"]).to eq(notification.id)
      expect(data["alert_id"]).to eq(notification.alert_id)
      expect(data["title"]).to eq("Vehicle Failure")
      expect(data["message"]).to eq("VH-1 failed")
    ensure
      redis&.close
    end
  end
end
