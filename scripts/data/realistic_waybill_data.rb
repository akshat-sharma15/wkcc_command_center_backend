# Rewrites every waybill_number that isn't already a realistic 12-digit
# numeric identifier (no letters, no hyphens - e.g. the seed generator's
# old "WB-061650") into one, e.g. "831047296150".
#
#   bin/rails runner scripts/data/realistic_waybill_data.rb
#
# Deterministic: each new number is derived from the waybill's own id via
# an MD5-seeded RNG, so reruns always produce the same result for the same
# row - not sequential-looking, not random-each-run. Idempotent: a waybill
# whose number already matches /\A\d{12}\z/ is left untouched, so this is
# safe to run again after real 12-digit numbers exist (e.g. from a prior
# run, or created directly in that format going forward - see
# scripts/data/seed_waybills.rb, updated to emit this format for new
# waybills too).
require "digest"

puts "=" * 70
puts "REALISTIC WAYBILL NUMBERS (12-digit numeric, no prefix)"
puts "=" * 70

FORMAT = /\A\d{12}\z/

def deterministic_12_digit(seed_key)
  rng = Random.new(Digest::MD5.hexdigest(seed_key).to_i(16))
  first = rng.rand(1..9) # avoid a leading zero, purely cosmetic
  "#{first}#{Array.new(11) { rng.rand(0..9) }.join}"
end

existing = Waybill.pluck(:waybill_number)
already_realistic = existing.count { |n| n.match?(FORMAT) }
to_convert = Waybill.where.not(waybill_number: existing.select { |n| n.match?(FORMAT) })

puts "Waybills already 12-digit numeric: #{already_realistic}"
puts "Waybills to convert: #{to_convert.count}"

used = existing.select { |n| n.match?(FORMAT) }.to_set
converted = 0

to_convert.find_each do |waybill|
  candidate = deterministic_12_digit("waybill-#{waybill.id}")
  salt = 0
  while used.include?(candidate)
    salt += 1
    candidate = deterministic_12_digit("waybill-#{waybill.id}-#{salt}")
  end
  used << candidate
  waybill.update_column(:waybill_number, candidate) # rubocop:disable Rails/SkipsModelValidations
  converted += 1
end

puts "Converted: #{converted}"
puts "Total waybills: #{Waybill.count}"
puts "Now 12-digit numeric: #{Waybill.pluck(:waybill_number).count { |n| n.match?(FORMAT) }}"
puts "Unique check: #{Waybill.count == Waybill.distinct.count(:waybill_number) ? '✓ all unique' : '✗ DUPLICATES FOUND'}"
puts "\nSample:"
Waybill.order(:id).limit(5).pluck(:waybill_number).each { |n| puts "  #{n}" }
