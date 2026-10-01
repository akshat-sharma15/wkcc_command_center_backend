class AddSoftDeleteToAlertRules < ActiveRecord::Migration[8.1]
  def change
    add_column :alert_rules, :deleted_at, :datetime

    add_index :alert_rules, :deleted_at
  end
end
