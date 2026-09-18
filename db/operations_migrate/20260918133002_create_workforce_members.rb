class CreateWorkforceMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :workforce_members do |t|
      t.string :identifier, null: false
      t.string :name, null: false
      t.string :role_type, null: false
      t.references :hub, null: false, foreign_key: true
      t.string :shift
      t.string :attendance_status, null: false, default: "present"

      t.timestamps
    end

    add_index :workforce_members, :identifier, unique: true
    add_index :workforce_members, :role_type
    add_index :workforce_members, :attendance_status
  end
end
