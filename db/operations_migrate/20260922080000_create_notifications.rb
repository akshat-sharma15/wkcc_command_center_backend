# A user-facing notification created because an Alert triggered. One row
# per (notification, recipient, channel) — the fan-out from "one Alert" to
# "N users x M channels" happens before these rows are created (see
# AlertEvaluationJob), not via a join table here.
#
# `recipient_user_id` is a Superset user id — deliberately a plain bigint,
# never a real FK, since Superset users live in a different database (see
# SupersetDirectory). `status` tracks the delivery pipeline
# (pending/delivered/failed); `read_at` is a separate, independent axis
# (has the user seen it), matching the fields list in the task spec.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :alert, null: false, foreign_key: true
      t.bigint :recipient_user_id, null: false
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"

      t.string :title, null: false
      t.text :message
      t.jsonb :metadata

      t.datetime :read_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.integer :attempts, null: false, default: 0
      t.text :error_message
      t.string :external_reference

      t.timestamps
    end

    add_index :notifications, :recipient_user_id
    add_index :notifications, [ :recipient_user_id, :read_at ]
    add_index :notifications, :channel
    add_index :notifications, :status
  end
end
