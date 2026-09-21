# EventDefinition ownership moved to operations (see
# db/operations_migrate/20260922070000_create_operations_event_definitions.rb,
# which copied all existing rows, preserving id, before this ran).
# command_center now owns no application tables — the old, already-unused
# `alerts` table from the Phase 1 refactor remains here untouched (still
# has all its columns/data), per explicit instruction not to remove it as
# part of this work. Its FK to event_definitions has to go, though —
# Postgres won't let event_definitions be dropped while that constraint
# still references it.
class DropEventDefinitions < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :alerts, :event_definitions
    drop_table :event_definitions
  end

  def down
    create_table :event_definitions do |t|
      t.string :name, null: false
      t.string :group, null: false
      t.string :event_type, null: false

      t.timestamps
    end

    add_index :event_definitions, :name, unique: true
    add_index :event_definitions, %i[group event_type]

    add_foreign_key :alerts, :event_definitions
  end
end
