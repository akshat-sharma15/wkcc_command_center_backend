# Road paths for the Fleet Map, fetched once from the Google Routes API and
# reused for every viewer (see FleetMonitoring::RoadRouteService). Lives in
# this app's own database, not the operations database, so the operations
# schema and the Superset views are untouched. Hubs live in the operations
# database, so there are no foreign keys - a route is identified by the
# rounded coordinates of its waypoints (`route_key`).
class CreateRoadRoutes < ActiveRecord::Migration[8.1]
  def change
    create_table :road_routes do |t|
      t.string :route_key, null: false
      t.jsonb :waypoints, null: false, default: []
      t.text :encoded_polyline, null: false
      t.integer :distance_meters
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :road_routes, :route_key, unique: true
  end
end
