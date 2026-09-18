class CreatePackages < ActiveRecord::Migration[8.1]
  def change
    create_table :packages do |t|
      t.string :identifier, null: false
      t.references :trip, null: true, foreign_key: true
      # Polymorphic: a package's current location is either a Warehouse or a Hub.
      t.references :location, polymorphic: true, null: false
      t.integer :expected_quantity, null: false, default: 0
      t.integer :received_quantity, null: false, default: 0
      t.integer :damaged_quantity, null: false, default: 0
      t.integer :short_quantity, null: false, default: 0
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :packages, :identifier, unique: true
    add_index :packages, :status
  end
end
