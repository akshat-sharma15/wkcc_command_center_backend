class CreateAlertRules < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_rules do |t|
      t.string :name, null: false
      t.string :group, null: false
      t.string :field, null: false
      t.string :operator, null: false
      t.jsonb :value

      t.string :severity, null: false
      t.boolean :notify, null: false, default: false
      t.string :recipient_type
      t.bigint :recipient_id

      t.boolean :enabled, null: false, default: true
      t.bigint :created_by_user_id

      t.timestamps
    end

    add_index :alert_rules, :group
    add_index :alert_rules, :enabled
  end
end
