# Moves EventDefinition ownership from command_center to operations (so
# AlertRule, now in operations, can hold a real FK to it — see the next
# migration). Schema is an exact copy of the original command_center
# table (db/command_center_migrate/20260918140000_create_event_definitions.rb)
# — no redesign, same columns/indexes/uniqueness.
#
# Copies any existing rows from command_center.event_definitions,
# preserving id, then resets the sequence so future inserts continue
# after the highest copied id. The source table in command_center is left
# untouched here — it's dropped in a separate, later migration only after
# this data is verified to have landed correctly.
class CreateOperationsEventDefinitions < ActiveRecord::Migration[8.1]
  def up
    create_table :event_definitions do |t|
      t.string :name, null: false
      t.string :group, null: false
      t.string :event_type, null: false

      t.timestamps
    end

    add_index :event_definitions, :name, unique: true
    add_index :event_definitions, %i[group event_type]

    copy_rows_from_command_center
  end

  def down
    drop_table :event_definitions
  end

  private

  def copy_rows_from_command_center
    source_rows = CommandCenterRecord.connection.select_all(
      'SELECT id, name, "group", event_type, created_at, updated_at FROM event_definitions ORDER BY id'
    )
    return if source_rows.to_a.empty?

    source_rows.each do |row|
      execute(<<~SQL.squish)
        INSERT INTO event_definitions (id, name, "group", event_type, created_at, updated_at)
        VALUES (
          #{row['id']},
          #{connection.quote(row['name'])},
          #{connection.quote(row['group'])},
          #{connection.quote(row['event_type'])},
          #{connection.quote(row['created_at'])},
          #{connection.quote(row['updated_at'])}
        )
      SQL
    end

    # Keep the sequence consistent with the preserved ids so the next
    # INSERT (without an explicit id) doesn't collide.
    execute(<<~SQL.squish)
      SELECT setval(
        pg_get_serial_sequence('event_definitions', 'id'),
        (SELECT MAX(id) FROM event_definitions)
      )
    SQL
  end
end
