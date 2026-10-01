# A real operational diversion of a vehicle's in-transit trip. There is no
# Route model (see ARCHITECTURE.md - Trip is the route/lane record), so the
# original and diverted paths are stored as ordered waypoint lists
# ([{name, lat, lng, location_id?}, ...]) alongside the trip, rather than
# inventing a routing platform. The numeric impact columns are the
# calculated incident snapshot persisted by RouteDiversionImpactService;
# impact_snapshot keeps the full calculation (including values that are
# explicitly unavailable) for audit/display.
class CreateRouteDiversions < ActiveRecord::Migration[8.1]
  def change
    create_table :route_diversions do |t|
      t.references :vehicle, null: false, foreign_key: true, index: true
      t.references :trip, null: false, foreign_key: true, index: true
      t.references :alert, null: true, foreign_key: true, index: true
      t.jsonb :original_path, null: false, default: []
      t.jsonb :diverted_path, null: false, default: []
      t.text :reason, null: false
      t.string :status, null: false, default: "active"
      t.datetime :diverted_at, null: false
      t.datetime :resolved_at

      t.decimal :original_distance_km, precision: 9, scale: 2
      t.decimal :diverted_distance_km, precision: 9, scale: 2
      t.decimal :additional_distance_km, precision: 9, scale: 2
      t.datetime :original_eta
      t.datetime :revised_eta
      t.integer :delay_minutes

      t.decimal :traffic_factor, precision: 4, scale: 2, null: false, default: 1.0
      t.decimal :fuel_impact_litres, precision: 9, scale: 2
      t.integer :affected_waybills
      t.integer :affected_packages
      t.integer :affected_orders
      t.decimal :revenue_risk, precision: 14, scale: 2
      t.jsonb :impact_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :route_diversions, :status
    add_index :route_diversions, %i[vehicle_id status]
  end
end
