puts "Seeding payment dues..."

vendors = ["Tata Motors Fleet", "Ashok Leyland Leasing", "Mahindra Logistics", "Indore Central Warehouse Corp", "Fuel Supply Partners", "Independent Owner"]
status_weights = { "pending" => 5, "paid" => 6, "overdue" => 3 }

30.times do
  status = status_weights.flat_map { |s, w| [s] * w }.sample
  due_date =
    case status
    when "overdue" then rand(3..45).days.ago.to_date
    when "paid" then rand(60).days.ago.to_date
    else rand(1..30).days.from_now.to_date
    end

  PaymentDue.create!(
    vendor: vendors.sample,
    amount: rand(5_000..250_000),
    due_date: due_date,
    payment_status: status,
    allow_alerts: true,
    alertable_fields: %w[payment_status amount]
  )
end
