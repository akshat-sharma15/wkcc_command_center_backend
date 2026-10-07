# Paste-into-`rails c` version of scripts/data/localize_demo_data.rb.
# Kept here for reference so the snippet lives in the repo rather than in
# someone's shell history.
#
#   bin/rails c
#   ...then paste this whole file in.
#
# Safe to paste more than once: it only touches records that are NOT
# already in the target format, and every value is seeded from the
# record's own id, so the same record always gets the same value.
# Uses locals/lambdas (no constants) precisely so re-pasting doesn't
# warn about already-initialized constants.

require "digest"
seed = ->(*p) { Random.new(Digest::MD5.hexdigest(p.join(":")).to_i(16)) }

# ---- 1. vehicle numbers -> MP09VC4568 -------------------------------
states = { "Andhra Pradesh" => "AP", "Assam" => "AS", "Bihar" => "BR", "Chandigarh" => "CH",
           "Chhattisgarh" => "CG", "Delhi" => "DL", "Goa" => "GA", "Gujarat" => "GJ",
           "Haryana" => "HR", "Himachal Pradesh" => "HP", "Jharkhand" => "JH",
           "Karnataka" => "KA", "Kerala" => "KL", "Madhya Pradesh" => "MP",
           "Maharashtra" => "MH", "Odisha" => "OD", "Punjab" => "PB", "Rajasthan" => "RJ",
           "Tamil Nadu" => "TN", "Telangana" => "TS", "Uttar Pradesh" => "UP",
           "Uttarakhand" => "UK", "West Bengal" => "WB" }
rtos = { "Indore" => "09", "Bhopal" => "04", "Jabalpur" => "20", "Gwalior" => "07",
         "Ratlam" => "43", "Mumbai" => "01", "Pune" => "12", "Nagpur" => "31", "Nashik" => "15",
         "Ahmedabad" => "01", "Surat" => "05", "Vadodara" => "06", "Jaipur" => "14",
         "Jodhpur" => "19", "Kota" => "20", "Delhi" => "01", "Lucknow" => "32", "Agra" => "80",
         "Varanasi" => "65", "Bengaluru" => "01", "Chennai" => "01", "Hyderabad" => "09",
         "Kolkata" => "01", "Kochi" => "07", "Patna" => "01", "Ranchi" => "01",
         "Bhubaneswar" => "02", "Raipur" => "01", "Guwahati" => "01", "Chandigarh" => "01" }
letters = ("A".."Z").to_a
vformat = /\A[A-Z]{2}\d{2}[A-Z]{2}\d{4}\z/
protected_numbers = %w[TRK-102 TRK-SPEC-1] # referenced verbatim by existing scripts/specs

taken = Vehicle.pluck(:number).to_set
vcount = 0
Vehicle.includes(hub: :geo_location).order(:id).find_each do |v|
  next if v.number =~ vformat || protected_numbers.include?(v.number)

  geo = v.hub&.geo_location
  prefix = "#{states[geo&.state.to_s] || 'MH'}#{rtos[geo&.city.to_s] || format('%02d', seed.('rto', geo&.city).rand(1..99))}"
  rng = seed.("vehicle", v.id)
  number = 200.times.lazy.map { "#{prefix}#{letters.sample(2, random: rng).join}#{format('%04d', rng.rand(1000..9999))}" }
                   .find { |c| !taken.include?(c) }
  taken.delete(v.number); taken << number
  v.update!(number: number)
  vcount += 1
end
puts "vehicles converted: #{vcount}"

# ---- 2. driver names -> Indian --------------------------------------
firsts = %w[Aditya Ajay Akash Amit Anand Anil Ankit Arjun Arun Ashok Deepak Dinesh Gaurav
            Harish Hemant Kiran Mahesh Manish Manoj Mohit Mukesh Naveen Nikhil Nitin Pankaj
            Pradeep Prakash Prashant Praveen Rahul Rajesh Rakesh Ramesh Ravi Rohit Sachin
            Sandeep Sanjay Santosh Satish Shankar Shyam Subhash Sunil Suresh Umesh Vijay
            Vikas Vinod Vishal Yogesh Anjali Asha Geeta Kavita Meena Neha Pooja Priya Radha
            Rekha Seema Sunita Swati Usha Vandana]
lasts = %w[Agarwal Bhatt Chauhan Chouhan Desai Deshmukh Dubey Gupta Iyer Jadhav Jain Joshi
           Kapoor Khanna Kulkarni Kumar Malhotra Mehta Menon Mishra Nair Naidu Pandey Patel
           Patil Pawar Rao Rathore Reddy Sharma Shinde Shukla Singh Solanki Thakur Tiwari
           Verma Yadav]
fset = firsts.to_set
lset = lasts.to_set
indian = ->(n) { p2 = n.to_s.split; p2.size == 2 && fset.include?(p2[0]) && lset.include?(p2[1]) }

dcount = 0
WorkforceMember.role_type_driver.order(:id).find_each do |d|
  next if indian.(d.name)

  rng = seed.("driver", d.id)
  d.update!(name: "#{firsts.sample(random: rng)} #{lasts.sample(random: rng)}")
  dcount += 1
end
puts "drivers converted:  #{dcount}"

# ---- 3. waybill numbers -> 12 digits ---------------------------------
wtaken = Waybill.pluck(:waybill_number).to_set
wcount = 0
Waybill.order(:id).find_each do |w|
  next if w.waybill_number =~ /\A\d{12}\z/

  rng = seed.("waybill", w.id)
  number = 200.times.lazy.map { format("%012d", rng.rand(100_000_000_000..999_999_999_999)) }
                   .find { |c| !wtaken.include?(c) }
  wtaken.delete(w.waybill_number); wtaken << number
  w.update!(waybill_number: number)
  wcount += 1
end
puts "waybills converted: #{wcount}"

# ---- 4. spread inbound traffic across 20-30 hubs ---------------------
# "Inbound at a hub" is derived, not stored: an in-transit trip whose
# DESTINATION is that hub. Only the destination is repointed - origin is
# left alone so the trip's packages (which sit at the origin hub) stay
# valid - and the waybills/position/ETA are kept in step with it.
trips = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
            .includes(:vehicle, :origin_hub, :waybills).to_a
by_dest = trips.group_by(&:destination_hub_id)
pace = FleetMonitoring::VehiclePositionPlanner::PLANNING_SPEED_KMPH
icount = 0

if by_dest.size < 20 && trips.any?
  located = Hub.includes(:geo_location).select { |h| h.geo_location }
  pts = located.to_h { |h| [h.id, { lat: h.geo_location.latitude.to_f, lng: h.geo_location.longitude.to_f }] }
  spare = located.reject { |h| by_dest.key?(h.id) }

  (20 - by_dest.size).times do
    _, donor = by_dest.max_by { |_, l| l.size }
    break if donor.nil? || donor.size <= 1 || (target = spare.shift).nil?

    trip = donor.pop
    from = pts[trip.origin_hub_id] or next
    to = pts[target.id]
    km = GeoDistance.km(from, to)
    next if km.zero?

    rng = seed.("inbound", trip.id)
    progress = 0.2 + rng.rand * 0.6
    hours = [km / pace, 0.5].max
    pos = { lat: from[:lat] + (to[:lat] - from[:lat]) * progress,
            lng: from[:lng] + (to[:lng] - from[:lng]) * progress }

    Trip.transaction do
      trip.update!(destination_hub_id: target.id,
                   route_info: "#{trip.origin_hub.name} to #{target.name}",
                   departure_at: Time.current - (hours * progress).hours,
                   expected_arrival_at: Time.current + (hours * (1 - progress)).hours)
      trip.waybills.each { |wb| wb.update!(destination_hub_id: target.id, expected_arrival_at: trip.expected_arrival_at) }
      loc = Location.create!(city: target.geo_location.city, state: target.geo_location.state, country: "India",
                             latitude: pos[:lat].round(6), longitude: pos[:lng].round(6))
      trip.vehicle.update!(current_location_id: loc.id, last_known_latitude: pos[:lat].round(6),
                           last_known_longitude: pos[:lng].round(6), last_location_at: Time.current)
    end
    by_dest[target.id] = [trip]
    icount += 1
  end
end
puts "trips repointed:    #{icount} (hubs receiving inbound: #{by_dest.size})"

# ---- summary ---------------------------------------------------------
vn = Vehicle.pluck(:number)
wn = Waybill.pluck(:waybill_number)
dn = WorkforceMember.role_type_driver.pluck(:name)
puts "-" * 50
puts "vehicles RTO format : #{vn.count { |n| n =~ vformat }}/#{vn.size}  unique=#{vn.uniq.size == vn.size}"
puts "waybills 12-digit   : #{wn.count { |n| n =~ /\A\d{12}\z/ }}/#{wn.size}  unique=#{wn.uniq.size == wn.size}"
puts "drivers Indian      : #{dn.count { |n| indian.(n) }}/#{dn.size}"
puts "hubs with inbound   : #{Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).distinct.count(:destination_hub_id)}"



to run this script, you can use the following command in your terminal:
cat scripts/data/console_localize_demo_data.rb | bin/rails cV
