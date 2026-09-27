class CreateLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :locations do |t|
      t.string :city, null: false
      t.string :state, null: false
      t.string :country, null: false, default: "India"
      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false

      t.timestamps
    end

    add_index :locations, [:city, :state], unique: true
  end
end
