# Responsible-person assignment + lifecycle audit for Alerts. Assignees are
# logical references to Superset users/roles (same convention as
# AlertRule#recipient_type/recipient_id - plain bigint, no FK, never copied
# into this database). Assignment (who owns the incident) is deliberately
# separate from recipients (who gets notified).
class AddAssignmentToAlertRulesAndAlerts < ActiveRecord::Migration[8.1]
  def change
    change_table :alert_rules, bulk: true do |t|
      t.string :primary_assignee_type
      t.bigint :primary_assignee_id
      t.string :secondary_assignee_type
      t.bigint :secondary_assignee_id
      t.integer :escalation_after_minutes
    end

    change_table :alerts, bulk: true do |t|
      t.string :assignee_type
      t.bigint :assignee_id
      t.string :assignment_level
      t.datetime :assigned_at
      t.datetime :acknowledged_at
      t.bigint :acknowledged_by
      t.bigint :resolved_by
      t.text :resolution_note
      t.datetime :escalated_at
      t.bigint :escalated_by
      t.integer :escalation_level, null: false, default: 0
    end

    add_index :alerts, %i[assignee_type assignee_id]
  end
end
