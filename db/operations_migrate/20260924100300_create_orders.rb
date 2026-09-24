# Shipment/Package/Delivery dashboard data foundation. Order is the new,
# minimal customer-facing concept the packages table itself doesn't carry
# (no customer/promised-date fields on Package until now - see below).
# Deliberately excludes customers/consignees/addresses/invoices/order_items
# - out of scope for this MVP.
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :order_number, null: false
      t.string :customer_reference
      t.string :status, null: false, default: "pending"
      t.string :priority
      t.references :origin_hub, null: true, foreign_key: { to_table: :hubs }
      t.references :destination_hub, null: true, foreign_key: { to_table: :hubs }
      t.integer :package_count, null: false, default: 0
      t.decimal :total_weight, precision: 10, scale: 2
      t.datetime :promised_delivery_at
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :orders, :order_number, unique: true
    add_index :orders, :status
    add_index :orders, :promised_delivery_at
  end
end
