class CreateHubs < ActiveRecord::Migration[8.1]
  def change
    create_table :hubs do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :location
      t.integer :capacity
      t.integer :parking_capacity
      t.integer :available_parking
      t.string :operational_status, null: false, default: "active"

      t.timestamps
    end

    add_index :hubs, :code, unique: true
    add_index :hubs, :operational_status
  end
end
