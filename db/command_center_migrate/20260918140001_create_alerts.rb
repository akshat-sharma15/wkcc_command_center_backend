class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.string :name, null: false
      t.references :event_definition, null: false, foreign_key: true
      t.string :role, null: false
      t.text :description

      t.timestamps
    end

    add_index :alerts, :name
  end
end
