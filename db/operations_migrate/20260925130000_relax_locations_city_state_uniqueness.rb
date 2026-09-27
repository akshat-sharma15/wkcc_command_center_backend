# A Location was originally "one canonical point per city" (unique on
# [city, state]), which is why every POC vehicle currently parked/in-transit
# in the same city was pointed at the exact same row - and so rendered as
# exactly overlapping map markers. Hubs and route waypoints still want a
# single canonical point (unchanged, still looked up by city/state), but
# vehicles now get their own distinct nearby point within the same city, so
# a city can legitimately have several Location rows. Uniqueness moves from
# a hard DB constraint to "callers that want the canonical point look it up
# and reuse it" (db/seeds/fleet_monitoring_poc.rb's `location_for`).
class RelaxLocationsCityStateUniqueness < ActiveRecord::Migration[8.1]
  def change
    remove_index :locations, [:city, :state], unique: true
    add_index :locations, [:city, :state]
  end
end
