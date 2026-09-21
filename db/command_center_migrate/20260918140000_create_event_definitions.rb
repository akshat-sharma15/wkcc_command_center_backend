class CreateEventDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :event_definitions do |t|
      t.string :name, null: false
      t.string :group, null: false
      t.string :event_type, null: false

      t.timestamps
    end

    add_index :event_definitions, :name, unique: true
    add_index :event_definitions, %i[group event_type]
  end
end
