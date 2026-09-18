class CreatePaymentDues < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_dues do |t|
      t.string :vendor, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.date :due_date, null: false
      t.string :payment_status, null: false, default: "pending"

      t.timestamps
    end

    add_index :payment_dues, :payment_status
    add_index :payment_dues, :due_date
  end
end
