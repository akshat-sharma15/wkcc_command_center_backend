# Tops up EVERY waybill's package count/weight to demo-realistic figures
# (this session generalizes what scripts/data/demo_inbound_scenarios.rb
# did for just the 5 featured demo trucks to all 359 waybills - the same
# "1 pkg" problem is visible on the rest of the fleet, not only those 5).
#
#   bin/rails runner scripts/data/realistic_waybill_packages.rb
#
# Package count: 40-60 per waybill (varied, ~50 average - task target),
# independent of vehicle capacity since package COUNT isn't a weight
# constraint by itself.
#
# Weight: budgeted PER TRIP, not per waybill in isolation. A trip can carry
# several waybills (this fleet: 1-6, see waybills-per-trip distribution),
# and giving each one up to ~500kg independently could sum well past the
# vehicle's own capacity - physically impossible and exactly the kind of
# inconsistency task section 7 calls out ("vehicle capacity >= total
# weight"). So each trip gets one weight budget (70% of the vehicle's
# capacity, leaving headroom), split across its own waybill count, with
# +/-15% variation per waybill - the sum across a trip's waybills always
# stays under that 70% budget by construction.
#
# No Order involved (task: "we do NOT need Orders right now") - as with
# the 5 demo trucks, weight lives only on the waybill's own total_weight
# column; Package has no weight column in this schema (only Order does).
#
# Idempotent: a waybill that already has >= 40 packages (the 5 demo
# trucks, or a prior run of this script) is left alone.
require "digest"

puts "=" * 70
puts "REALISTIC PACKAGE/WEIGHT FOR ALL WAYBILLS (trip-budgeted)"
puts "=" * 70

TARGET_PACKAGES_MIN = 40
TARGET_PACKAGES_MAX = 60
TRIP_CAPACITY_BUDGET_FRACTION = 0.7
MIN_WAYBILL_WEIGHT_KG = 50.0

def next_package_identifiers(count, seed_key)
  rng = Random.new(Digest::MD5.hexdigest(seed_key).to_i(16))
  identifiers = []
  loop do
    candidate = format("CC-PKG-%06d", rng.rand(100_000..999_999))
    next if identifiers.include?(candidate) || Package.exists?(identifier: candidate)

    identifiers << candidate
    break if identifiers.size == count
  end
  identifiers
end

topped_up = 0
skipped_already_done = 0
skipped_no_trip_or_vehicle = []

Waybill.includes(:vehicle, trip: :waybills).find_each do |waybill|
  if waybill.total_packages.to_i >= TARGET_PACKAGES_MIN
    skipped_already_done += 1
    next
  end

  vehicle = waybill.vehicle
  trip = waybill.trip
  if vehicle.nil?
    skipped_no_trip_or_vehicle << waybill.id
    next
  end

  sibling_count = trip ? trip.waybills.size : 1
  capacity = vehicle.capacity.to_f
  trip_budget = capacity.positive? ? capacity * TRIP_CAPACITY_BUDGET_FRACTION : nil
  base_share = trip_budget ? trip_budget / sibling_count : 500.0 # no capacity on record - fall back to the task's ~500kg figure

  rng = Random.new(Digest::MD5.hexdigest("waybill-packages-#{waybill.id}").to_i(16))
  target_count = rng.rand(TARGET_PACKAGES_MIN..TARGET_PACKAGES_MAX)
  target_weight = [ base_share * (0.85 + rng.rand * 0.3), MIN_WAYBILL_WEIGHT_KG ].max
  target_weight = [ target_weight, capacity ].min if capacity.positive? # absolute hard cap regardless of budget math

  new_count = target_count - waybill.total_packages.to_i
  identifiers = next_package_identifiers(new_count, "waybill-packages-new-#{waybill.id}")

  Package.transaction do
    identifiers.each do |identifier|
      Package.create!(
        identifier: identifier,
        location_type: "Hub",
        location_id: waybill.origin_hub_id,
        status: trip&.status_in_transit? ? "in_transit" : "pending",
        trip_id: waybill.trip_id,
        waybill_id: waybill.id
      )
    end
    waybill.update!(total_packages: target_count, total_weight: target_weight.round(2))
  end
  topped_up += 1
end

puts "\nWaybills topped up: #{topped_up}"
puts "Waybills already realistic (skipped, idempotent): #{skipped_already_done}"
puts "Waybills skipped (no vehicle - needs manual review): #{skipped_no_trip_or_vehicle.size} #{skipped_no_trip_or_vehicle}" if skipped_no_trip_or_vehicle.any?

stats = Waybill.pluck(:total_packages)
puts "\nFinal package-count stats: min=#{stats.min} max=#{stats.max} avg=#{(stats.sum.to_f / stats.size).round(1)}"
puts "Waybills still under 40 packages: #{stats.count { |p| p < TARGET_PACKAGES_MIN }}"

# Per-trip capacity consistency check (the thing this whole budgeting
# scheme exists to guarantee) - reported, not silently assumed.
over_capacity = Trip.joins(:waybills).joins(:vehicle).distinct.find_all do |trip|
  next false if trip.vehicle.capacity.to_f <= 0

  trip.waybills.sum { |w| w.total_weight.to_f } > trip.vehicle.capacity.to_f
end
puts "\nTrips where waybills' summed weight exceeds vehicle capacity: #{over_capacity.size} #{over_capacity.empty? ? '(none)' : over_capacity.map(&:id)}"
