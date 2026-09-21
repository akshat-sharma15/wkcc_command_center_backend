# The triggered/occurrence side of an AlertRule. No automatic triggering
# exists yet (Phase 2+) — this table just needs to exist so the
# association and validations can be tested now.
class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.references :alert_rule, null: false, foreign_key: true

      t.string :group, null: false
      t.bigint :record_id, null: false
      t.string :field, null: false
      t.string :expected_value
      t.string :actual_value

      t.string :severity, null: false
      t.string :status, null: false, default: "open"

      t.datetime :triggered_at, null: false
      t.datetime :resolved_at
      t.jsonb :metadata

      t.timestamps
    end

    add_index :alerts, :group
    add_index :alerts, :status
    add_index :alerts, %i[group record_id]
  end
end
