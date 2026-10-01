# Stable, code-facing identifier for an EventDefinition (e.g.
# "vehicle.failure"), independent of its human-readable, editable `name`.
# Nullable: user-created definitions from the Events page have no key and
# keep working exactly as before; only definitions the backend itself
# publishes against (see IncidentCatalog) need one.
class AddKeyToEventDefinitions < ActiveRecord::Migration[8.1]
  def change
    add_column :event_definitions, :key, :string
    add_index :event_definitions, :key, unique: true, where: "key IS NOT NULL"
  end
end
