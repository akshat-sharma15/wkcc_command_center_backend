# Brings ANY environment's demo data to the Indian-localised state:
# realistic vehicle registrations, Indian driver names, 12-digit waybill
# numbers, and inbound traffic spread across 20-30 hubs.
#
#   bin/rails runner scripts/data/localize_demo_data.rb
#   FORCE=1 bin/rails runner scripts/data/localize_demo_data.rb   # redo everything
#   ONLY=vehicles,drivers bin/rails runner scripts/data/localize_demo_data.rb
#
# WHY THIS EXISTS, given scripts/data/realistic_{vehicle_data,driver_names,
# waybill_data}.rb already exist and are committed: those were written
# against one specific database and are not portable.
# realistic_driver_names.rb in particular maps FIFTEEN EXACT OLD NAMES
# ("Cedrick Harris Ret." => "Rakesh Rathore", ...), so on any other
# environment - whose Faker seed produced different names - it matches
# nothing and silently does nothing. This script instead detects
# non-conforming records BY FORMAT, so it converges any database to the
# same end state regardless of what it started from.
#
# Safe to commit and run anywhere:
#   - DETERMINISTIC: every generated value is seeded from the record's own
#     id, so the same database always yields the same result, and a rerun
#     never churns values.
#   - IDEMPOTENT: records already in the target format are skipped. Run it
#     twice and the second run reports zero changes.
#   - NON-DESTRUCTIVE: only the columns named below are written. No record
#     is created or deleted, no hub is reassigned, no schema is touched.
#
# These are SYNTHETIC demo values that follow real formatting conventions -
# they are not claims about actually-registered vehicles or real people.
require "digest"

ONLY = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:empty?)
FORCE = ENV["FORCE"].present?
def run?(step) = ONLY.empty? || ONLY.include?(step)

puts "=" * 72
puts "LOCALIZE DEMO DATA#{FORCE ? ' (FORCE: regenerating everything)' : ''}"
puts "=" * 72

# ---------------------------------------------------------------------
# 1. VEHICLE REGISTRATIONS - STATE + RTO + SERIES + NUMBER
# ---------------------------------------------------------------------
# The state/RTO prefix is taken from the vehicle's OWN hub, never at
# random, so every vehicle based at one hub shares a prefix, the way a
# real city-based fleet would. Stored without a space ("MP09VC4568"):
# vehicle.number is used as a URL path segment (/fleet-monitoring/
# vehicles/:pnr) and in frontend deep links, where a raw space is an
# encoding risk for no functional gain - add the space at display time.
VEHICLE_FORMAT = /\A[A-Z]{2}\d{2}[A-Z]{2}\d{4}\z/

# Vehicle numbers referenced verbatim by existing scripts/specs. Renaming
# them would silently break those, so they are left alone unless FORCE.
PROTECTED_VEHICLE_NUMBERS = %w[TRK-102 TRK-SPEC-1].freeze

STATE_CODES = {
  "Andhra Pradesh" => "AP", "Arunachal Pradesh" => "AR", "Assam" => "AS", "Bihar" => "BR",
  "Chandigarh" => "CH", "Chhattisgarh" => "CG", "Delhi" => "DL", "Goa" => "GA",
  "Gujarat" => "GJ", "Haryana" => "HR", "Himachal Pradesh" => "HP", "Jammu and Kashmir" => "JK",
  "Jharkhand" => "JH", "Karnataka" => "KA", "Kerala" => "KL", "Madhya Pradesh" => "MP",
  "Maharashtra" => "MH", "Manipur" => "MN", "Meghalaya" => "ML", "Mizoram" => "MZ",
  "Nagaland" => "NL", "Odisha" => "OD", "Puducherry" => "PY", "Punjab" => "PB",
  "Rajasthan" => "RJ", "Sikkim" => "SK", "Tamil Nadu" => "TN", "Telangana" => "TS",
  "Tripura" => "TR", "Uttar Pradesh" => "UP", "Uttarakhand" => "UK", "West Bengal" => "WB"
}.freeze

# Real RTO codes for the cities this dataset actually uses; any other city
# gets a stable 2-digit code derived from its name.
KNOWN_RTO = {
  "Indore" => "09", "Bhopal" => "04", "Jabalpur" => "20", "Gwalior" => "07", "Ujjain" => "13",
  "Ratlam" => "43", "Dewas" => "41", "Sagar" => "15", "Rewa" => "17",
  "Mumbai" => "01", "Pune" => "12", "Nagpur" => "31", "Nashik" => "15", "Thane" => "04",
  "Chhatrapati Sambhajinagar" => "20", "Sambhajinagar" => "20", "Aurangabad" => "20",
  "Ahmedabad" => "01", "Surat" => "05", "Vadodara" => "06", "Rajkot" => "03",
  "Jaipur" => "14", "Jodhpur" => "19", "Udaipur" => "27", "Kota" => "20", "Ajmer" => "06",
  "Delhi" => "01", "New Delhi" => "01", "Gurugram" => "26", "Noida" => "16", "Faridabad" => "51",
  "Lucknow" => "32", "Kanpur" => "78", "Agra" => "80", "Varanasi" => "65", "Prayagraj" => "70",
  "Bengaluru" => "01", "Bangalore" => "01", "Mysuru" => "09", "Hubballi" => "20",
  "Chennai" => "01", "Coimbatore" => "38", "Madurai" => "02", "Salem" => "30",
  "Hyderabad" => "09", "Warangal" => "02", "Vijayawada" => "16", "Visakhapatnam" => "31",
  "Kolkata" => "01", "Howrah" => "05", "Siliguri" => "73", "Durgapur" => "37",
  "Kochi" => "07", "Thiruvananthapuram" => "01", "Kozhikode" => "11",
  "Patna" => "01", "Gaya" => "02", "Ranchi" => "01", "Jamshedpur" => "05", "Dhanbad" => "10",
  "Bhubaneswar" => "02", "Cuttack" => "05", "Raipur" => "01", "Bilaspur" => "10",
  "Guwahati" => "01", "Chandigarh" => "01", "Ludhiana" => "08", "Amritsar" => "02",
  "Dehradun" => "07", "Shimla" => "01", "Panaji" => "01"
}.freeze

SERIES_LETTERS = ("A".."Z").to_a.freeze

def seeded(*parts) = Random.new(Digest::MD5.hexdigest(parts.join(":")).to_i(16))

def rto_prefix_for(vehicle)
  geo = vehicle.hub&.geo_location
  state_code = STATE_CODES[geo&.state.to_s] || "MH"
  city = geo&.city.to_s
  rto = KNOWN_RTO[city] || format("%02d", seeded("rto", city).rand(1..99))
  "#{state_code}#{rto}"
end

def generate_vehicle_number(vehicle, taken)
  prefix = rto_prefix_for(vehicle)
  rng = seeded("vehicle", vehicle.id)
  200.times do
    candidate = "#{prefix}#{SERIES_LETTERS.sample(2, random: rng).join}#{format('%04d', rng.rand(1000..9999))}"
    return candidate unless taken.include?(candidate)
  end
  raise "could not generate a unique registration for vehicle ##{vehicle.id}"
end

if run?("vehicles")
  puts "\n[1/4] VEHICLE REGISTRATIONS"
  taken = Vehicle.pluck(:number).to_set
  changed = 0
  skipped_protected = []

  Vehicle.includes(hub: :geo_location).order(:id).find_each do |vehicle|
    next if !FORCE && vehicle.number =~ VEHICLE_FORMAT

    if PROTECTED_VEHICLE_NUMBERS.include?(vehicle.number) && !FORCE
      skipped_protected << vehicle.number
      next
    end

    old = vehicle.number
    taken.delete(old)
    number = generate_vehicle_number(vehicle, taken)
    vehicle.update!(number: number)
    taken << number
    changed += 1
    puts "  #{old} -> #{number}" if changed <= 10
  end

  puts "  … and #{changed - 10} more" if changed > 10
  puts "  converted: #{changed}"
  puts "  left alone (referenced by existing scripts/specs): #{skipped_protected.join(', ')}" if skipped_protected.any?
  puts "  already correct: #{Vehicle.count - changed - skipped_protected.size}"
end

# ---------------------------------------------------------------------
# 2. DRIVER NAMES
# ---------------------------------------------------------------------
# Detected by POOL MEMBERSHIP, not by matching specific old names, so this
# works on an environment whose Faker seed produced entirely different
# names. A driver whose name is already drawn from these pools is left
# untouched, which is what makes reruns a no-op.
# Kept deliberately WIDE. A narrow pool is worse than useless here: it
# rejects perfectly good Indian names it simply doesn't know ("Radha
# Joshi", "Vijay Menon") and rewrites them for no reason, churning data
# on every environment that happens to use a different valid set.
FIRST_NAMES = %w[
  Aarav Abhishek Aditya Ajay Akash Amit Anand Anil Ankit Arjun Arun Ashok Ashish Avinash
  Balaji Bharat Bhavesh Chetan Deepak Devendra Dinesh Gaurav Girish Gopal Harish Hemant
  Imran Jagdish Jatin Kailash Karan Kiran Krishna Kunal Lokesh Madhav Mahesh Manish Manoj
  Mohan Mohit Mukesh Narendra Naveen Nikhil Nitin Omkar Pankaj Parag Pavan Pradeep Prakash
  Pramod Prashant Praveen Raghav Rahul Raj Rajesh Rakesh Ramesh Ranjan Ravi Rohit Sachin
  Sandeep Sanjay Santosh Satish Shankar Shiv Shyam Srinivas Subhash Sudhir Sunil Suresh
  Tarun Uday Umesh Varun Venkat Vijay Vikas Vikram Vinay Vinod Vishal Vivek Yash Yogesh
  Anjali Anita Aruna Asha Deepika Divya Geeta Indira Jyoti Kavita Lakshmi Lata Madhuri
  Meena Meera Nandini Neha Nisha Pooja Prerna Priya Radha Rani Rekha Sangeeta Savita Seema
  Shilpa Shobha Sneha Sudha Sunita Swati Uma Usha Vandana Vidya
].freeze

LAST_NAMES = %w[
  Agarwal Aggarwal Ahuja Arora Bansal Bhatia Bhatt Bhosale Chauhan Chopra Chouhan Das
  Deshmukh Desai Dhawan Dubey Dutta Gandhi Ghosh Gowda Goyal Gupta Hegde Iyer Iyengar
  Jadhav Jain Jha Joshi Kadam Kale Kapoor Kaur Khanna Khurana Kulkarni Kumar Malhotra
  Mehra Mehta Menon Meena Mishra Mukherjee Nair Naidu Nayak Pandey Patel Pathak Patil
  Pawar Pillai Prasad Raj Rao Rathore Reddy Saxena Sen Sharma Shetty Shinde Shukla Singh
  Sinha Solanki Subramanian Thakur Tiwari Trivedi Varma Verma Yadav
].freeze

NAME_POOL = FIRST_NAMES.to_set.freeze
SURNAME_POOL = LAST_NAMES.to_set.freeze

def indian_name?(name)
  parts = name.to_s.split
  parts.size == 2 && NAME_POOL.include?(parts[0]) && SURNAME_POOL.include?(parts[1])
end

if run?("drivers")
  puts "\n[2/4] DRIVER NAMES"
  drivers = WorkforceMember.role_type_driver.order(:id)
  changed = 0

  drivers.find_each do |driver|
    next if !FORCE && indian_name?(driver.name)

    rng = seeded("driver", driver.id)
    name = "#{FIRST_NAMES.sample(random: rng)} #{LAST_NAMES.sample(random: rng)}"
    old = driver.name
    driver.update!(name: name)
    changed += 1
    puts "  #{old.inspect} -> #{name}" if changed <= 10
  end

  puts "  … and #{changed - 10} more" if changed > 10
  puts "  converted: #{changed}"
  puts "  already Indian: #{drivers.count - changed}"
end

# ---------------------------------------------------------------------
# 3. WAYBILL NUMBERS - 12 DIGITS
# ---------------------------------------------------------------------
WAYBILL_FORMAT = /\A\d{12}\z/

if run?("waybills")
  puts "\n[3/4] WAYBILL NUMBERS"
  taken = Waybill.pluck(:waybill_number).to_set
  changed = 0

  Waybill.order(:id).find_each do |waybill|
    next if !FORCE && waybill.waybill_number =~ WAYBILL_FORMAT

    old = waybill.waybill_number
    taken.delete(old)
    rng = seeded("waybill", waybill.id)
    number = nil
    200.times do
      candidate = format("%012d", rng.rand(100_000_000_000..999_999_999_999))
      next if taken.include?(candidate)

      number = candidate
      break
    end
    raise "could not generate a unique waybill number for ##{waybill.id}" unless number

    waybill.update!(waybill_number: number)
    taken << number
    changed += 1
    puts "  #{old} -> #{number}" if changed <= 10
  end

  puts "  … and #{changed - 10} more" if changed > 10
  puts "  converted: #{changed}"
  puts "  already 12-digit: #{Waybill.count - changed}"
end

# ---------------------------------------------------------------------
# 4. INBOUND TRAFFIC SPREAD ACROSS 20-30 HUBS
# ---------------------------------------------------------------------
# "Inbound at a hub" is derived, never stored: it is simply an in-transit
# trip whose destination is that hub (FleetMonitoring::HubVehicleFlow).
# So spreading inbound traffic means repointing some trips' DESTINATION.
# Origin is deliberately never touched - the trip's packages sit at the
# origin hub, so leaving it alone keeps that relationship valid.
#
# Each repointed trip is kept fully consistent: its waybills' destination
# and arrival follow the trip, the vehicle is repositioned onto the new
# route, and departure/arrival are re-anchored to that position so
# predicted-vs-planned ETA stays in agreement.
INBOUND_HUB_MIN = 20
INBOUND_HUB_MAX = 30

if run?("inbound")
  puts "\n[4/4] INBOUND SPREAD (target: #{INBOUND_HUB_MIN}-#{INBOUND_HUB_MAX} hubs)"

  trips = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
              .includes(:vehicle, :origin_hub, :destination_hub, :waybills).to_a
  by_destination = trips.group_by(&:destination_hub_id)
  puts "  in-transit POC trips: #{trips.size} across #{by_destination.size} destination hubs"

  if trips.empty?
    puts "  ⊘ no in-transit POC trips - nothing to spread"
  elsif by_destination.size >= INBOUND_HUB_MIN
    puts "  ✓ already spread across #{by_destination.size} hubs - no change (idempotent)"
  else
    located = Hub.includes(:geo_location).select { |h| h.geo_location }
    points = located.to_h { |h| [ h.id, { lat: h.geo_location.latitude.to_f, lng: h.geo_location.longitude.to_f } ] }
    unused = located.reject { |h| by_destination.key?(h.id) }
    needed = INBOUND_HUB_MIN - by_destination.size
    pace = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH
    moved = 0

    needed.times do
      # Always take from whichever destination is currently most crowded,
      # and only while it still has a trip to spare.
      donor_id, donor_trips = by_destination.max_by { |_, list| list.size }
      break if donor_trips.nil? || donor_trips.size <= 1

      target = unused.shift
      break unless target

      trip = donor_trips.pop
      origin_point = points[trip.origin_hub_id] or next
      target_point = points[target.id]
      distance = GeoDistance.km(origin_point, target_point)
      next if distance.zero?

      rng = seeded("inbound", trip.id)
      progress = 0.2 + rng.rand * 0.6
      total_hours = [ distance / pace, 0.5 ].max
      elapsed = total_hours * progress
      position = {
        lat: origin_point[:lat] + (target_point[:lat] - origin_point[:lat]) * progress,
        lng: origin_point[:lng] + (target_point[:lng] - origin_point[:lng]) * progress
      }

      Trip.transaction do
        trip.update!(destination_hub_id: target.id,
                     route_info: "#{trip.origin_hub.name} to #{target.name}",
                     departure_at: Time.current - elapsed.hours,
                     expected_arrival_at: Time.current + (total_hours - elapsed).hours)
        trip.waybills.each do |waybill|
          waybill.update!(destination_hub_id: target.id,
                          planned_departure_at: trip.departure_at,
                          expected_arrival_at: trip.expected_arrival_at)
        end
        location = Location.create!(city: target.geo_location.city, state: target.geo_location.state,
                                    country: "India", latitude: position[:lat].round(6), longitude: position[:lng].round(6))
        trip.vehicle.update!(current_location_id: location.id,
                             last_known_latitude: position[:lat].round(6),
                             last_known_longitude: position[:lng].round(6),
                             last_location_at: Time.current - rng.rand(1..15).minutes)
      end

      by_destination[target.id] = [ trip ]
      moved += 1
      puts "  #{trip.vehicle.number}: now inbound to #{target.code} #{target.name}"
    end

    puts "  repointed: #{moved} trip(s); destinations now: #{by_destination.size} hubs"
  end
end

# ---------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------
puts "\n" + "=" * 72
puts "RESULT"
puts "=" * 72
vehicles = Vehicle.pluck(:number)
waybills = Waybill.pluck(:waybill_number)
drivers = WorkforceMember.role_type_driver.pluck(:name)
inbound_hubs = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).distinct.count(:destination_hub_id)

puts "  vehicles in RTO format : #{vehicles.count { |n| n =~ VEHICLE_FORMAT }} / #{vehicles.size}"
puts "  vehicle numbers unique : #{vehicles.uniq.size == vehicles.size}"
puts "  drivers with Indian names: #{drivers.count { |n| indian_name?(n) }} / #{drivers.size}"
puts "  waybills 12-digit      : #{waybills.count { |n| n =~ WAYBILL_FORMAT }} / #{waybills.size}"
puts "  waybill numbers unique : #{waybills.uniq.size == waybills.size}"
puts "  hubs receiving inbound : #{inbound_hubs}"
puts "\nRerun to confirm idempotency - a second run should report 0 conversions."
