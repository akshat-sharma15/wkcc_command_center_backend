# Alert-system refactor Phase 1: lets each record opt into alerting and
# declare which of its own columns may be targeted by an AlertRule.
# Deliberately excludes Trips (per explicit product decision) — a "routes"
# alertable group was considered but dropped; there's no Route (or
# equivalent) business model independent of alerting, and a model
# shouldn't be invented solely to serve the alert system.
class AddAlertConfigurationToBusinessModels < ActiveRecord::Migration[8.1]
  TABLES = %i[vehicles hubs packages payment_dues workforce_members].freeze

  def change
    TABLES.each do |table|
      add_column table, :allow_alerts, :boolean, null: false, default: false
      add_column table, :alertable_fields, :string, array: true, null: false, default: []
    end
  end
end
