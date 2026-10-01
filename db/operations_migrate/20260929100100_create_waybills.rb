# Waybill: the transport document for a consignment moving on a vehicle's
# trip. Deliberately reuses existing entities rather than copying them:
# origin/destination are Hub FKs (not free text), the document's contents
# are the existing Package rows (packages.waybill_id, below) and through
# them their Orders/customer_reference - so no WaybillItem, customer or
# order tables. The total_* columns are the document's issued totals
# (a waybill states its own totals), recalculated from those packages by
# Waybill#recalculate_totals!. declared_value is the declared value of the
# goods, a standard waybill/e-way-bill field and the only monetary figure
# the operations schema carries (see RevenueRiskService).
class CreateWaybills < ActiveRecord::Migration[8.1]
  def change
    create_table :waybills do |t|
      t.string :waybill_number, null: false
      t.references :vehicle, null: false, foreign_key: true, index: true
      t.references :trip, null: true, foreign_key: true, index: true
      t.references :origin_hub, null: false, foreign_key: { to_table: :hubs }
      t.references :destination_hub, null: false, foreign_key: { to_table: :hubs }
      t.string :status, null: false, default: "issued"
      t.integer :total_packages, null: false, default: 0
      t.integer :total_orders, null: false, default: 0
      t.decimal :total_weight, precision: 12, scale: 2
      t.integer :customer_count, null: false, default: 0
      t.decimal :declared_value, precision: 14, scale: 2
      t.datetime :planned_departure_at
      t.datetime :expected_arrival_at
      t.datetime :actual_arrival_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :waybills, :waybill_number, unique: true
    add_index :waybills, :status

    add_reference :packages, :waybill, null: true, foreign_key: true, index: true
  end
end
