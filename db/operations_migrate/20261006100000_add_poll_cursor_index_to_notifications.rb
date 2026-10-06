# Backs notification polling (GET /api/v1/notifications/poll): "this
# user's in-app notifications with id > cursor, oldest first" is a single
# index range scan on (recipient_user_id, channel, id).
class AddPollCursorIndexToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_index :notifications, %i[recipient_user_id channel id], name: "index_notifications_on_recipient_channel_id"
  end
end
