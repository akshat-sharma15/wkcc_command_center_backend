# Hub Operations dashboard data foundation only - records discrete hub
# handling events (gate-in, unloading, scanning, sorting, loading, dispatch)
# so later SQL views can derive dwell time, throughput, dock/bay
# utilisation, etc. Deliberately separate from EventDefinition/Alert (see
# ARCHITECTURE.md) - this is operational history for analytics, not part of
# the alerting system. event_type stays a plain string so the vocabulary
# can grow without a second event-framework migration.
class CreateHubOperationsEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :hub_operations_events do |t|
      t.references :hub, null: false, foreign_key: true
      t.references :vehicle, null: true, foreign_key: true
      t.references :trip, null: true, foreign_key: true
      t.references :package, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :dock_reference
      t.string :bay_reference
      t.datetime :occurred_at, null: false
      t.jsonb :metadata

      t.timestamps
    end

    add_index :hub_operations_events, [ :hub_id, :occurred_at ]
    add_index :hub_operations_events, [ :event_type, :occurred_at ]
  end
end
