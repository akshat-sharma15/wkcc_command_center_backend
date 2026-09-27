# Shipment/Package/Delivery dashboard data foundation. Purely additive -
# existing polymorphic `location`, `status`, and quantity columns/behavior
# are untouched. order_id is nullable so every existing package remains
# valid without backfill.
class AddOrderAndDeliveryFieldsToPackages < ActiveRecord::Migration[8.1]
  def change
    change_table :packages, bulk: true do |t|
      t.references :order, null: true, foreign_key: true
      t.datetime :promised_delivery_at
      t.datetime :delivered_at
    end

    add_index :packages, :promised_delivery_at
    add_index :packages, :delivered_at
  end
end
