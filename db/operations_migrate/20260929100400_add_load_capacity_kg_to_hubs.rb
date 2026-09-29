# Physical load capacity of a hub in kilograms, for projected-load /
# utilisation (see HubLoadService). The pre-existing integer `capacity`
# column has no defined unit anywhere in the schema, seeds or docs, so it
# is left untouched rather than reinterpreted; utilisation is reported as
# unavailable for a hub whose load_capacity_kg is not set.
class AddLoadCapacityKgToHubs < ActiveRecord::Migration[8.1]
  def change
    add_column :hubs, :load_capacity_kg, :decimal, precision: 12, scale: 2
  end
end
