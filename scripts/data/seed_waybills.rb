# Issues waybills for the packages already loaded on every in-transit trip
# of the Fleet Monitoring POC fleet.
#
#   bin/rails runner scripts/data/seed_waybills.rb
#
# One waybill per (trip, consignee): a trip's undelivered packages are
# grouped by their order's customer_reference, and each group becomes one
# waybill whose contents ARE those package rows (packages.waybill_id) -
# nothing is copied. Totals come from Waybill#recalculate_totals!.
#
# Two values have no source in the operations data and are generated as
# clearly-marked demo data (metadata.demo_fields lists them):
#   declared_value      goods value per kg x apportioned weight
#   expected_arrival_at trip ETA + a per-consignee delivery buffer
# Deterministic (seeded per trip) and idempotent: packages that already
# have a waybill are skipped, and waybill numbers derive from trip ids.
VALUE_PER_KG_RANGE = (180..650).freeze # INR per kg, demo
ARRIVAL_BUFFERS_MINUTES = [ 0, 15, 30, 45, 90 ].freeze

puts "=" * 70
puts "SEED WAYBILLS"
puts "=" * 70

trips = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).includes(:vehicle).order(:id)
created = 0
attached = 0

trips.each do |trip|
  packages = trip.packages.where(waybill_id: nil).where.not(status: "delivered").includes(:order).order(:id).to_a
  next if packages.empty?

  rng = Random.new(trip.id)
  groups = packages.group_by { |package| package.order&.customer_reference || "UNASSIGNED" }
  existing = trip.waybills.count

  groups.sort_by(&:first).each_with_index do |(customer, group), index|
    # 12-digit numeric, no letters - see scripts/data/realistic_waybill_data.rb
    # for the rationale and for converting any pre-existing "WB-######" rows.
    number = format("%012d", rng.rand(100_000_000_000..999_999_999_999))
    number = format("%012d", rng.rand(100_000_000_000..999_999_999_999)) while Waybill.exists?(waybill_number: number)
    rate = rng.rand(VALUE_PER_KG_RANGE)
    buffer = ARRIVAL_BUFFERS_MINUTES[rng.rand(ARRIVAL_BUFFERS_MINUTES.size)]

    Waybill.transaction do
      waybill = Waybill.find_or_create_by!(waybill_number: number) do |w|
        w.vehicle = trip.vehicle
        w.trip = trip
        w.origin_hub_id = trip.origin_hub_id
        w.destination_hub_id = trip.destination_hub_id
        w.status = "in_transit"
        w.planned_departure_at = trip.departure_at
        w.expected_arrival_at = trip.expected_arrival_at && trip.expected_arrival_at + buffer.minutes
        w.metadata = { consignee_reference: customer, demo_fields: %w[declared_value expected_arrival_at],
                       declared_value_rate_per_kg: rate }
        created += 1
      end
      Package.where(id: group.map(&:id)).update_all(waybill_id: waybill.id) # rubocop:disable Rails/SkipsModelValidations
      attached += group.size
      waybill.recalculate_totals!
      waybill.update!(declared_value: (waybill.total_weight.to_f * rate).round(2)) if waybill.declared_value.nil?
    end
  end
end

puts "Waybills created: #{created}; packages attached: #{attached}"
puts "Total waybills: #{Waybill.count} (open: #{Waybill.open.count}) across #{Waybill.distinct.count(:trip_id)} trips"
sample = Waybill.joins(:vehicle).order("RANDOM()").first&.vehicle
if sample
  puts "\n#{sample.number} waybills:"
  sample.waybills.order(:waybill_number).each do |w|
    puts "  #{w.waybill_number}  #{w.origin_hub.name} -> #{w.destination_hub.name}  customer=#{w.customer_reference || "#{w.customer_count} customers"}  " \
         "packages=#{w.total_packages} orders=#{w.total_orders} weight=#{w.total_weight}kg value=₹#{w.declared_value.to_i} eta=#{w.expected_arrival_at&.strftime('%H:%M')} #{w.status}"
  end
end
orphans = Package.where.not(waybill_id: nil).where.missing(:waybill).count
puts "\n  #{orphans.zero? ? '✓' : '✗'} no packages point at a missing waybill"
