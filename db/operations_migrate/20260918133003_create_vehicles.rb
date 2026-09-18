class CreateVehicles < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicles do |t|
      t.string :number, null: false
      # Not `type` - that column name triggers Rails single-table inheritance.
      t.string :vehicle_type, null: false
      t.string :status, null: false, default: "active"
      t.integer :capacity
      t.string :vendor
      t.string :current_location
      t.references :hub, null: false, foreign_key: true
      t.references :driver, foreign_key: { to_table: :workforce_members }, null: true

      t.timestamps
    end

    add_index :vehicles, :number, unique: true
    add_index :vehicles, :status
  end
end
