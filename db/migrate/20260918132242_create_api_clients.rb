class CreateApiClients < ActiveRecord::Migration[8.1]
  def change
    create_table :api_clients do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :scopes, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :api_clients, :token_digest, unique: true
    add_index :api_clients, :name, unique: true
  end
end
