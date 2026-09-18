class CreateWarehouses < ActiveRecord::Migration[8.1]
  def change
    create_table :warehouses do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :location
      t.integer :capacity
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :warehouses, :code, unique: true
    add_index :warehouses, :status
  end
end
