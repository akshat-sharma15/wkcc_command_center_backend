require "rails_helper"

RSpec.describe Notification, type: :model do
  it "is valid with the required fields" do
    expect(build(:notification)).to be_valid
  end

  it "rejects an unsupported channel (e.g. email)" do
    expect(build(:notification, channel: "email")).not_to be_valid
  end

  it "rejects an unsupported status" do
    expect(build(:notification, status: "read")).not_to be_valid
  end

  describe "#read?/#mark_read!" do
    it "is unread by default and becomes read after mark_read!" do
      notification = create(:notification)
      expect(notification).not_to be_read
      notification.mark_read!
      expect(notification.reload).to be_read
      expect(notification.read_at).to be_present
    end
  end

  describe "#mark_delivered!" do
    it "sets status delivered, delivered_at, and clears any prior error" do
      notification = create(:notification, status: "failed", error_message: "boom")
      notification.mark_delivered!(external_reference: "1234.5678")
      expect(notification.status).to eq("delivered")
      expect(notification.delivered_at).to be_present
      expect(notification.external_reference).to eq("1234.5678")
      expect(notification.error_message).to be_nil
    end
  end

  describe "#mark_failed!" do
    it "sets status failed, failed_at, error_message, and increments attempts" do
      notification = create(:notification)
      notification.mark_failed!("channel_not_found")
      expect(notification.status).to eq("failed")
      expect(notification.failed_at).to be_present
      expect(notification.error_message).to eq("channel_not_found")
      expect(notification.attempts).to eq(1)

      notification.mark_failed!("channel_not_found")
      expect(notification.attempts).to eq(2)
    end
  end

  describe "scopes" do
    it ".unread returns only notifications with no read_at" do
      unread = create(:notification)
      read = create(:notification, read_at: Time.current)
      expect(Notification.unread).to include(unread)
      expect(Notification.unread).not_to include(read)
    end

    it ".for_recipient scopes to one recipient_user_id" do
      mine = create(:notification, recipient_user_id: 5)
      other = create(:notification, recipient_user_id: 6)
      expect(Notification.for_recipient(5)).to include(mine)
      expect(Notification.for_recipient(5)).not_to include(other)
    end
  end
end
