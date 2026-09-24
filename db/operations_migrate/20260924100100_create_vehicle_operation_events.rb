# Fleet dashboard data foundation only - a small operational event log for
# Fleet KPIs that current vehicles/trips status columns can't answer alone
# (e.g. breakdown history). Deliberately NOT a generic event framework and
# NOT connected to EventDefinition/Alert - see ARCHITECTURE.md's Alert
# system, which this table is intentionally independent from.
class CreateVehicleOperationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicle_operation_events do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :trip, null: true, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :metadata

      t.timestamps
    end

    add_index :vehicle_operation_events, [ :vehicle_id, :occurred_at ]
    add_index :vehicle_operation_events, [ :trip_id, :occurred_at ]
    add_index :vehicle_operation_events, [ :event_type, :occurred_at ]
  end
end
