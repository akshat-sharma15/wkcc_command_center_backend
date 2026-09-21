# Reviving command_center's originally-intended purpose (see the root
# task's DB architecture: "COMMAND_CENTER DB: Integrations, Events,
# Alerts" — Events/Alerts were later moved to operations for FK reasons
# specific to their own domain; Integrations was never touched and this
# database otherwise holds nothing but one unused legacy table).
#
# `bot_token` is encrypted at rest via ActiveRecord::Encryption
# (`encrypts :bot_token` in the model) — a text column is required since
# ciphertext is larger than the plaintext token.
#
# Column is `provider`, not `type` — "type" is a reserved Active Record
# column name (single table inheritance discriminator). The API still
# exposes it as `"type"` (see IntegrationSerializer).
class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :integrations do |t|
      t.string :provider, null: false
      t.string :status, null: false, default: "disconnected"
      t.boolean :enabled, null: false, default: true

      t.string :workspace_id
      t.string :workspace_name
      t.string :bot_user_id
      t.string :scope
      t.text :bot_token

      t.timestamps
    end

    add_index :integrations, :provider, unique: true
  end
end
