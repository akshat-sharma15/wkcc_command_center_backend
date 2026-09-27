# Fleet Monitoring POC (additive only - existing `location` free-text
# column on hubs is untouched). `location_id` gives hubs real lat/lng for
# the map; `vendor_id` records which vendor operates the hub, for the
# frontend's hub "Operator" field.
class AddFleetMonitoringFieldsToHubs < ActiveRecord::Migration[8.1]
  def change
    add_reference :hubs, :location, foreign_key: { to_table: :locations }, null: true
    add_reference :hubs, :vendor, foreign_key: { to_table: :vendors }, null: true
  end
end
