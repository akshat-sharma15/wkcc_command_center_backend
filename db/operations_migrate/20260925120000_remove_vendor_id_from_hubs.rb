# Hubs are not associated with a Vendor - only vehicles are (see Hub model
# comment). Reverts the `hubs.vendor_id` column added alongside
# `hubs.location_id` in AddFleetMonitoringFieldsToHubs.
class RemoveVendorIdFromHubs < ActiveRecord::Migration[8.1]
  def change
    remove_reference :hubs, :vendor, foreign_key: { to_table: :vendors }
  end
end
