class AddNotificationChannelsToAlertRules < ActiveRecord::Migration[8.1]
  def change
    add_column :alert_rules, :notification_channels, :string, array: true, null: false, default: []
  end
end
