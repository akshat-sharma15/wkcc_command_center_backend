# Rewrites every synthetic vehicle number (CC-VEH-####, VH-####, TRK-###)
# into a realistic Indian RTO-style registration: STATE (2 letters) + RTO
# code (2 digits) + series (2 letters) + number (4 digits), e.g. "MP09NH4567"
# for a vehicle based at an Indore hub. These are SYNTHETIC demo
# registrations that follow the real formatting convention - not claims
# about actually-registered vehicles.
#
#   bin/rails runner scripts/data/realistic_vehicle_data.rb
#
# The state+RTO prefix comes from the vehicle's own hub's state/city (never
# assigned randomly - see task requirement "don't randomly assign a
# Gujarat registration to a vehicle based in Assam"), so every vehicle at
# the same hub shares the same prefix, exactly as real registrations for
# fleet vehicles based in one city would. Deterministic (MD5-seeded per
# vehicle id) and idempotent: a vehicle whose number already matches the
# realistic format (/\A[A-Z]{2}\d{2}[A-Z]{2}\d{4}\z/) is left untouched.
#
# Stored WITHOUT a space ("MP09NH4567", not "MP09 NH4567"): vehicle.number
# is used as a URL path segment (GET /fleet-monitoring/vehicles/:pnr) and a
# raw space there is an unnecessary encoding risk across the API and the
# truck_monitoring frontend's deep links for zero functional benefit - a
# space is trivial to add back at display time if wanted.
require "digest"

puts "=" * 70
puts "REALISTIC INDIAN VEHICLE REGISTRATION NUMBERS"
puts "=" * 70

FORMAT = /\A[A-Z]{2}\d{2}[A-Z]{2}\d{4}\z/

# TRK-102 is a documented fixture: scripts/alerts/09_test_route_diversion.rb
# and 07_test_truck_failure.rb reference it by this exact string as "the"
# known demo vehicle for those scenarios. Renaming it would silently break
# those existing, working alert-test scripts, so it's the one number this
# script deliberately leaves alone (everything else - the other 99
# TRK-###, all VH-#### and CC-VEH-#### - is still converted).
FIXTURE_EXEMPT_NUMBERS = %w[TRK-102].freeze

STATE_CODES = {
  "Andhra Pradesh" => "AP", "Assam" => "AS", "Bihar" => "BR", "Chandigarh" => "CH",
  "Chhattisgarh" => "CG", "Delhi" => "DL", "Gujarat" => "GJ", "Haryana" => "HR",
  "Jharkhand" => "JH", "Karnataka" => "KA", "Kerala" => "KL", "Madhya Pradesh" => "MP",
  "Maharashtra" => "MH", "Odisha" => "OD", "Punjab" => "PB", "Rajasthan" => "RJ",
  "Tamil Nadu" => "TN", "Telangana" => "TS", "Uttar Pradesh" => "UP",
  "Uttarakhand" => "UK", "West Bengal" => "WB"
}.freeze

# Real RTO codes for the cities that matter most for this demo (Indore
# MP09 is the one explicitly named in the task spec); every other city
# gets a stable deterministic 2-digit code derived from its own name, so
# it's fixed forever but not a real claimed RTO number.
KNOWN_RTO = {
  "Indore" => "09", "Bhopal" => "04", "Gwalior" => "06", "Jabalpur" => "20",
  "Ahmedabad" => "01", "Surat" => "05", "Vadodara" => "06", "Rajkot" => "03",
  "Mumbai" => "01", "Pune" => "12", "Nagpur" => "31", "Nashik" => "15",
  "Jaipur" => "14", "Jodhpur" => "19", "Kota" => "17",
  "Delhi" => "01", "Chandigarh" => "01",
  "Ludhiana" => "05", "Amritsar" => "02", "Jalandhar" => "04",
  "Chennai" => "01", "Coimbatore" => "37", "Madurai" => "58",
  "Bengaluru" => "01", "Mysuru" => "09", "Hyderabad" => "01",
  "Kolkata" => "01", "Lucknow" => "32", "Kanpur" => "25", "Agra" => "80",
  "Meerut" => "55", "Varanasi" => "70", "Patna" => "01", "Ranchi" => "01",
  "Bhubaneswar" => "02", "Raipur" => "01", "Guwahati" => "01",
  "Thiruvananthapuram" => "01", "Kochi" => "07", "Visakhapatnam" => "37",
  "Vijayawada" => "05", "Faridabad" => "05", "Dehradun" => "01"
}.freeze

def rto_number_for(city)
  KNOWN_RTO.fetch(city) { format("%02d", (Digest::MD5.hexdigest(city).to_i(16) % 50) + 1) }
end

def deterministic_suffix(seed_key)
  rng = Random.new(Digest::MD5.hexdigest(seed_key).to_i(16))
  series = Array.new(2) { (65 + rng.rand(26)).chr }.join
  number = format("%04d", rng.rand(1..9999))
  "#{series}#{number}"
end

existing = Vehicle.pluck(:number)
already_realistic = existing.count { |n| n.match?(FORMAT) }
used = existing.select { |n| n.match?(FORMAT) }.to_set

skip_numbers = existing.select { |n| n.match?(FORMAT) } + FIXTURE_EXEMPT_NUMBERS
to_convert = Vehicle.includes(hub: :geo_location).where.not(number: skip_numbers).order(:id)
puts "Exempted fixture vehicle(s): #{FIXTURE_EXEMPT_NUMBERS.join(', ')} (used by scripts/alerts/*)"
puts "Vehicles already realistic: #{already_realistic}"
puts "Vehicles to convert: #{to_convert.count}"

converted = 0
skipped_no_state = []

to_convert.find_each do |vehicle|
  geo = vehicle.hub&.geo_location
  state_code = STATE_CODES[geo&.state]
  unless state_code
    skipped_no_state << vehicle.number
    next
  end

  rto = rto_number_for(geo.city)
  prefix = "#{state_code}#{rto}"
  salt = 0
  candidate = "#{prefix}#{deterministic_suffix("vehicle-#{vehicle.id}")}"
  while used.include?(candidate)
    salt += 1
    candidate = "#{prefix}#{deterministic_suffix("vehicle-#{vehicle.id}-#{salt}")}"
  end
  used << candidate
  vehicle.update_column(:number, candidate) # rubocop:disable Rails/SkipsModelValidations
  converted += 1
end

puts "Converted: #{converted}"
puts "Skipped (hub has no resolvable state): #{skipped_no_state.size} #{skipped_no_state.first(5)}" if skipped_no_state.any?
puts "Total vehicles: #{Vehicle.count}"
puts "Now realistic format: #{Vehicle.pluck(:number).count { |n| n.match?(FORMAT) }}"
puts "Unique check: #{Vehicle.count == Vehicle.distinct.count(:number) ? '✓ all unique' : '✗ DUPLICATES FOUND'}"
puts "\nSample (Indore hub):"
Hub.find_by(code: "CC-HUB-016")&.vehicles&.order(:id)&.limit(5)&.pluck(:number)&.each { |n| puts "  #{n}" }
