class CreateVendors < ActiveRecord::Migration[8.1]
  def change
    create_table :vendors do |t|
      t.string :name, null: false
      t.string :code, null: false

      t.timestamps
    end

    add_index :vendors, :name, unique: true
    add_index :vendors, :code, unique: true
  end
end
