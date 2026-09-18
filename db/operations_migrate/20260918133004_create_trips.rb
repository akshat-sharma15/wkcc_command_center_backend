class CreateTrips < ActiveRecord::Migration[8.1]
  def change
    create_table :trips do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :origin_hub, null: false, foreign_key: { to_table: :hubs }
      t.references :destination_hub, null: false, foreign_key: { to_table: :hubs }
      t.datetime :departure_at
      t.datetime :expected_arrival_at
      t.datetime :actual_arrival_at
      t.string :status, null: false, default: "scheduled"
      t.text :route_info

      t.timestamps
    end

    add_index :trips, :status
    add_index :trips, :departure_at
  end
end
