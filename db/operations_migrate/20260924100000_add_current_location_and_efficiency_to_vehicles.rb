# Command Centre MVP data foundation (Fleet dashboard). Purely additive:
# current_location (string) is untouched, this only adds a current-position
# cache (lat/long + when it was last updated) and two point-in-time fleet
# metrics. No telemetry history, no ingestion pipeline - see ARCHITECTURE.md
# scope notes for why this is deliberately minimal.
class AddCurrentLocationAndEfficiencyToVehicles < ActiveRecord::Migration[8.1]
  def change
    change_table :vehicles, bulk: true do |t|
      t.decimal :last_known_latitude, precision: 9, scale: 6
      t.decimal :last_known_longitude, precision: 9, scale: 6
      t.datetime :last_location_at
      t.decimal :mileage_km, precision: 10, scale: 2
      t.decimal :fuel_efficiency_kmpl, precision: 6, scale: 2
    end
  end
end
