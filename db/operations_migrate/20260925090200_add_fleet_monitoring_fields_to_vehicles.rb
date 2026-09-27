# Fleet Monitoring POC (additive only - see ARCHITECTURE.md / API.md for the
# existing `current_location`/`vendor` free-text columns this deliberately
# does not touch). `current_location_id`/`vendor_id` are a normalized,
# optional alternative source of truth for the Fleet Monitoring API;
# `fleet_monitoring_poc` flags the ~100-vehicle POC subset exposed through
# it without deleting or otherwise disturbing the other ~225 vehicles.
class AddFleetMonitoringFieldsToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_reference :vehicles, :current_location, foreign_key: { to_table: :locations }, null: true
    add_reference :vehicles, :vendor, foreign_key: { to_table: :vendors }, null: true
    add_column :vehicles, :fleet_monitoring_poc, :boolean, null: false, default: false

    add_index :vehicles, :fleet_monitoring_poc
  end
end
